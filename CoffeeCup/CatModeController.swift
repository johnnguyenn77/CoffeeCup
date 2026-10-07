import AppKit
import ApplicationServices
import Combine
import CoreGraphics

@MainActor
final class CatModeController: ObservableObject {
    static let shared = CatModeController()

    @Published private(set) var isActive = false
    @Published private(set) var errorMessage: String?

    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var eventTapContext: CatModeEventTapContext?

    func setActive(_ active: Bool) {
        active ? start() : stop()
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }

        eventTap = nil
        eventTapSource = nil
        eventTapContext = nil
        isActive = false
        errorMessage = nil
    }

    private func start() {
        guard !isActive else { return }

        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            errorMessage = "Allow CoffeeCup in System Settings → Privacy & Security → Accessibility, then try again."
            return
        }

        let context = CatModeEventTapContext(
            requestExit: { [weak self] in
                self?.stop()
            },
            reportTapDisabled: { [weak self] in
                guard let self else { return }
                self.stop()
                self.errorMessage = "Cat Mode stopped because macOS disabled its input blocker."
            }
        )

        let eventTypes: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .mouseMoved,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .scrollWheel, .tabletPointer, .tabletProximity
        ]
        let eventMask = eventTypes.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: catModeEventTapCallback,
            userInfo: Unmanaged.passUnretained(context).toOpaque()
        ) else {
            errorMessage = "Could not start Cat Mode. Check CoffeeCup’s Accessibility permission and try again."
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            errorMessage = "Could not start Cat Mode’s input monitor."
            return
        }

        eventTap = tap
        eventTapSource = source
        eventTapContext = context
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true
        errorMessage = nil
    }
}

private final class CatModeEventTapContext {
    private let lock = NSLock()
    private var exitRequested = false
    private let requestExit: () -> Void
    private let reportTapDisabled: () -> Void

    init(requestExit: @escaping () -> Void, reportTapDisabled: @escaping () -> Void) {
        self.requestExit = requestExit
        self.reportTapDisabled = reportTapDisabled
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .flagsChanged {
            // Let modifier transitions through so the unlock chord doesn't leave
            // macOS believing a modifier key is still held after Cat Mode ends.
            return Unmanaged.passUnretained(event)
        }

        let unlockModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        if type == .keyDown,
           event.getIntegerValueField(.keyboardEventKeycode) == 53,
           event.flags.contains(unlockModifiers) {
            lock.lock()
            let shouldRequestExit = !exitRequested
            exitRequested = true
            lock.unlock()

            if shouldRequestExit {
                // Keep the tap installed briefly to swallow Escape's key-up too.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [requestExit] in
                    requestExit()
                }
            }
            return nil
        }

        return nil
    }

    func handleDisabledTap() {
        reportTapDisabled()
    }
}

private let catModeEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<CatModeEventTapContext>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        DispatchQueue.main.async { [context] in
            context.handleDisabledTap()
        }
        return Unmanaged.passUnretained(event)
    }

    return context.handle(type: type, event: event)
}
