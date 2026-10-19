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

    private let provider = KeyboardHIDService()
    private var engine: KeyboardModifierEngine?
    private var manager: IOHIDManager?
    private var refreshWork: DispatchWorkItem?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var isRunning = false

    init() {
        do {
            engine = try KeyboardModifierEngine(provider: provider, store: KeyboardModifierDefaultsStore(),
                                                bootSessionID: KeyboardHIDService.bootSessionID())
        } catch { errorMessage = error.localizedDescription }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        // Discovery only: do not open/seize keyboards or subscribe to key events.
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOHIDManagerOptions.independentDevices.rawValue)
        let callback: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<KeyboardModifierController>.fromOpaque(context).takeUnretainedValue().scheduleRefresh()
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
        ) { [weak self] _ in MainActor.assumeIsolated { self?.scheduleRefresh() } }
        // Some KVMs keep an emulated keyboard connected; verify its service state periodically too.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh() // Handles keyboards already connected before CoffeeCup launches.
        scheduleRefresh()
    }

    func refresh() {
        guard isRunning, let engine else { return }
        do { try engine.refresh(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
        publishState()
    }

    func selectKeyboard(_ id: String) {
        do { try engine?.selectKeyboard(id); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
        publishState()
    }

    func setSwapEnabled(_ enabled: Bool) {
        guard let engine, let selectedKeyboardID else { return }
        do { try engine.setEnabled(enabled, for: selectedKeyboardID); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
        publishState()
    }

    func stop() {
        isRunning = false
        refreshWork?.cancel()
        refreshWork = nil
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
        do { try engine?.restoreBeforeQuit() }
        catch { errorMessage = error.localizedDescription }
        swapsModifiers = false
    }

    private func scheduleRefresh() {
        guard isRunning else { return }
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func publishState() {
        guard let engine else { return }
        if keyboards != engine.keyboards { keyboards = engine.keyboards }
        selectedKeyboardID = engine.preferences.selectedKeyboardID
        swapsModifiers = selectedKeyboardID.map { engine.appliedKeyboardIDs.contains($0) } ?? false
    }
}
