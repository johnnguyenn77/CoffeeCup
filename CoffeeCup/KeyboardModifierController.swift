import AppKit
import Combine
import IOKit.hid

@MainActor
final class KeyboardModifierController: ObservableObject {
    static let shared = KeyboardModifierController()

    @Published private(set) var keyboards: [ExternalKeyboard] = []
    @Published private(set) var selectedKeyboardID: String?
    @Published private(set) var swapsModifiers = false
    @Published private(set) var errorMessage: String?

    var selectedKeyboard: ExternalKeyboard? { keyboards.first { $0.id == selectedKeyboardID } }
    var hasKeyboards: Bool { !keyboards.isEmpty }

    private let worker: KeyboardModifierWorker
    private let monitorsDevices: Bool
    private let scheduleRefreshWork: (TimeInterval, DispatchWorkItem) -> Void
    private static let recoveryDelays: [TimeInterval] = [0.35, 1, 2]
    private var manager: IOHIDManager?
    private var refreshWork: DispatchWorkItem?
    private var recoveryGeneration = 0
    private var recoveryAttempt = 0
    private var isRecovering = false
    private var hasRetriedCurrentFailure = false
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var isRunning = false
    private var isSleeping = false
    private var generation = 0
    private var pendingOperations = 0
    private var refreshPending = false
    private var refreshAgain = false
    private var refreshCompletions: [() -> Void] = []
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var needsPeriodicVerification = false

    init() {
        worker = KeyboardModifierWorker()
        monitorsDevices = true
        scheduleRefreshWork = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    init(engine: KeyboardModifierEngine,
         scheduleRefreshWork: @escaping (TimeInterval, DispatchWorkItem) -> Void = { delay, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
         }) {
        worker = KeyboardModifierWorker(engine: engine)
        self.scheduleRefreshWork = scheduleRefreshWork
        // Simulated controllers use the same worker, but never observe real devices or poll.
        monitorsDevices = false
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        isSleeping = false
        generation += 1
        refresh(invalidateDiscovery: true) // Includes devices connected before launch.
        guard monitorsDevices else { return }
        // Discovery only: do not open/seize keyboards or subscribe to key events.
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOHIDManagerOptions.independentDevices.rawValue)
        let callback: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<KeyboardModifierController>.fromOpaque(context).takeUnretainedValue().devicesDidChange()
            }
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, callback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, callback, context)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 6] as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        self.manager = manager
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated {
            self?.isSleeping = false
            self?.devicesDidChange()
        } }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated {
            self?.isSleeping = true
            self?.cancelRecovery()
            self?.updateVerificationTimer()
        } }
        devicesDidChange()
    }

    func refresh(invalidateDiscovery: Bool = false, completion: (() -> Void)? = nil) {
        guard isRunning else { return }
        if let completion { refreshCompletions.append(completion) }
        if refreshPending {
            refreshAgain = refreshAgain || invalidateDiscovery
            return
        }
        refreshPending = true
        submit(.refresh(invalidateDiscovery: invalidateDiscovery)) { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            if self.refreshAgain {
                self.refreshAgain = false
                self.refresh(invalidateDiscovery: true)
            } else {
                let completions = self.refreshCompletions
                self.refreshCompletions.removeAll()
                completions.forEach { $0() }
            }
        }
    }

    /// Used by deterministic tests to await snapshots, not by normal UI interaction.
    func waitUntilIdle() async {
        guard pendingOperations > 0 else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    func selectKeyboard(_ id: String) {
        submit(.select(id))
    }

    func setSwapEnabled(_ enabled: Bool, for keyboardID: String? = nil) {
        guard let targetID = keyboardID ?? selectedKeyboardID else { return }
        submit(.setEnabled(enabled, targetID))
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation += 1 // Ignore snapshots queued before shutdown/restart.
        cancelRecovery()
        hasRetriedCurrentFailure = false
        timer?.invalidate()
        timer = nil
        if let manager {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
        manager = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        sleepObserver = nil
        refreshPending = false
        refreshAgain = false
        refreshCompletions.removeAll()
        publishState(worker.restoreBeforeQuit())
        swapsModifiers = false
        pendingOperations = 0
        finishIdleWaiters()
    }

    func devicesDidChange() {
        guard isRunning else { return }
        hasRetriedCurrentFailure = false
        beginRecovery()
    }

    private func cancelRecovery() {
        recoveryGeneration += 1
        refreshWork?.cancel()
        refreshWork = nil
        isRecovering = false
        recoveryAttempt = 0
    }

    private func beginRecovery() {
        cancelRecovery()
        guard isRunning, !isSleeping else { return }
        isRecovering = true
        scheduleNextRecoveryRefresh()
    }

    private func scheduleNextRecoveryRefresh() {
        guard isRunning, !isSleeping, recoveryAttempt < Self.recoveryDelays.count else {
            isRecovering = false
            return
        }
        let delay = Self.recoveryDelays[recoveryAttempt]
        recoveryAttempt += 1
        let scheduledGeneration = recoveryGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, !self.isSleeping,
                  self.recoveryGeneration == scheduledGeneration else { return }
            self.refreshWork = nil
            self.refresh(invalidateDiscovery: true) { [weak self] in
                guard let self, self.isRunning,
                      self.recoveryGeneration == scheduledGeneration else { return }
                self.scheduleNextRecoveryRefresh()
            }
        }
        refreshWork = work
        // A short, bounded settling sequence also handles KVMs that enumerate late.
        // It runs even when the connected-device verification timer has stopped.
        scheduleRefreshWork(delay, work)
    }

    private func submit(_ operation: KeyboardModifierWorker.Operation, completion: (() -> Void)? = nil) {
        guard isRunning else { return }
        let submittedGeneration = generation
        pendingOperations += 1
        worker.perform(operation) { [weak self] state in
            guard let self, self.isRunning, self.generation == submittedGeneration else { return }
            self.publishState(state)
            self.pendingOperations -= 1
            completion?()
            self.finishIdleWaiters()
        }
    }

    private func publishState(_ state: KeyboardModifierSnapshot) {
        if keyboards != state.keyboards { keyboards = state.keyboards }
        if selectedKeyboardID != state.selectedKeyboardID { selectedKeyboardID = state.selectedKeyboardID }
        if swapsModifiers != state.swapsModifiers { swapsModifiers = state.swapsModifiers }
        if errorMessage != state.errorMessage { errorMessage = state.errorMessage }
        needsPeriodicVerification = state.needsPeriodicVerification
        updateVerificationTimer()
        if state.needsDiscoveryRecovery {
            let shouldRecover = !hasRetriedCurrentFailure && !isRecovering
            hasRetriedCurrentFailure = true
            if shouldRecover { beginRecovery() }
        } else {
            hasRetriedCurrentFailure = false
        }
    }

    private func updateVerificationTimer() {
        guard monitorsDevices, isRunning, !isSleeping, needsPeriodicVerification else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        // KVMs may reset a mapping without a hot-plug event. Preserve the five-second
        // fallback ONLY for managed connected devices; ordinary idle mode has no timer.
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.5
        self.timer = timer
    }

    private func finishIdleWaiters() {
        guard pendingOperations == 0 else { return }
        let waiters = idleWaiters
        idleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
