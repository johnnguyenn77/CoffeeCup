import CoreGraphics
import Foundation

/// Pure filtering policy: tests create events locally but never post them to macOS.
nonisolated struct CatModeInputFilter {
    enum Action { case allow, suppress, beginUnlock, finishUnlock }
    private var exitRequested = false

    mutating func action(for type: CGEventType, event: CGEvent) -> Action {
        if type.rawValue == CatModeSystemDefinedKey.eventTypeValue {
            return CatModeSystemDefinedKey.shouldSuppress(event) ? .suppress : .allow
        }
        // Passing modifier releases avoids stuck Command/Option/Control after unlocking.
        if type == .flagsChanged { return .allow }
        let escape = event.getIntegerValueField(.keyboardEventKeycode) == 53
        if type == .keyUp, escape, exitRequested { return .finishUnlock }
        if type == .keyDown, escape,
           event.flags.contains([.maskControl, .maskAlternate, .maskCommand]) {
            guard !exitRequested else { return .suppress }
            exitRequested = true
            return .beginUnlock
        }
        return .suppress
    }
}

/// The input run loop exists only during Cat Mode. It sleeps waiting for events,
/// never polls, and releases input without waiting for the app's main thread.
nonisolated final class CatModeInputSession: @unchecked Sendable {
    enum StopReason: Sendable { case requested, unlocked, disabled }
    let id = UUID()

    private let onStopped: @MainActor @Sendable (UUID, StopReason) -> Void
    private let lock = NSLock()
    private var stopping = false
    private var started = false
    private var finished = false
    private var runLoop: CFRunLoop?
    // Prepared before starting the thread; only the event thread uses filter/timer.
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var filter = CatModeInputFilter()
    private var unlockTimer: CFRunLoopTimer?
    #if COFFEECUP_CORE_TESTS
    private var onFinishedForTesting: @Sendable () -> Void = { }
    #endif

    private init(onStopped: @escaping @MainActor @Sendable (UUID, StopReason) -> Void) {
        self.onStopped = onStopped
    }

    static func make(onStopped: @escaping @MainActor @Sendable (UUID, StopReason) -> Void)
        -> CatModeInputSession? {
        let session = CatModeInputSession(onStopped: onStopped)
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .mouseMoved,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .scrollWheel, .tabletPointer, .tabletProximity]
        let mask = types.reduce(CGEventMask(1) << CatModeSystemDefinedKey.eventTypeValue) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                return Unmanaged<CatModeInputSession>.fromOpaque(info).takeUnretainedValue()
                    .handle(type: type, event: event)
            }, userInfo: Unmanaged.passUnretained(session).toOpaque()) else { return nil }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return nil
        }
        session.tap = tap
        session.source = source
        return session
    }

    func start() {
        lock.lock()
        guard !started, !stopping, source != nil else { lock.unlock(); return }
        started = true
        lock.unlock()
        // Capturing self keeps the C callback's unretained context alive until teardown.
        let thread = Thread { [self] in
            guard let source else { return }
            let loop = CFRunLoopGetCurrent()!
            lock.lock()
            runLoop = loop
            let shouldRun = !stopping
            lock.unlock()
            CFRunLoopAddSource(loop, source, .defaultMode)
            if shouldRun { CFRunLoopRun() }
            CFRunLoopRemoveSource(loop, source, .defaultMode)
            if let unlockTimer { CFRunLoopTimerInvalidate(unlockTimer) }
            if let tap { CFMachPortInvalidate(tap) }
            lock.lock()
            runLoop = nil
            finished = true
            lock.unlock()
            #if COFFEECUP_CORE_TESTS
            onFinishedForTesting()
            #endif
        }
        thread.name = "CoffeeCup Cat Mode input"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop(reason: StopReason = .requested) {
        lock.lock()
        guard !stopping else { lock.unlock(); return }
        stopping = true
        let loop = runLoop
        lock.unlock()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let loop {
            // A queued block also handles a stop arriving just before CFRunLoopRun starts.
            CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) {
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            CFRunLoopWakeUp(loop)
        }
        DispatchQueue.main.async { [onStopped, id] in onStopped(id, reason) }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stop(reason: .disabled)
            return Unmanaged.passUnretained(event)
        }
        switch filter.action(for: type, event: event) {
        case .allow: return Unmanaged.passUnretained(event)
        case .suppress: return nil
        case .beginUnlock:
            // Normally Escape's key-up ends the session. The one-shot fallback handles
            // a missing key-up and runs here even if the UI thread is temporarily busy.
            unlockTimer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault,
                CFAbsoluteTimeGetCurrent() + 0.15, 0, 0, 0) { [weak self] _ in
                    self?.stop(reason: .unlocked)
                }
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), unlockTimer, .defaultMode)
            return nil
        case .finishUnlock:
            stop(reason: .unlocked)
            return nil
        }
    }

    #if COFFEECUP_CORE_TESTS
    // Exercise the actual thread/run-loop lifecycle without installing a global tap
    // or requesting Accessibility. This code is excluded from the shipping binary.
    static func simulated(onFinished: @escaping @Sendable () -> Void = { },
                          onStopped: @escaping @MainActor @Sendable (UUID, StopReason) -> Void)
        -> CatModeInputSession {
        let session = CatModeInputSession(onStopped: onStopped)
        var context = CFRunLoopSourceContext(version: 0, info: nil, retain: nil, release: nil,
            copyDescription: nil, equal: nil, hash: nil, schedule: nil, cancel: nil, perform: { _ in })
        session.source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)
        session.onFinishedForTesting = onFinished
        return session
    }

    var isRunningForTesting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return runLoop != nil && !stopping
    }

    var isFinishedForTesting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    func performForTesting(_ block: @escaping @Sendable () -> Void) {
        lock.lock()
        let loop = runLoop
        lock.unlock()
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(loop)
    }

    func handleForTesting(type: CGEventType, event: CGEvent) {
        _ = handle(type: type, event: event)
    }
    #endif
}
