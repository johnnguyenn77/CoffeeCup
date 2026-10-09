import AppKit
import ApplicationServices
import Combine
import CoreGraphics

@MainActor
final class CatModeController: ObservableObject {
    static let shared = CatModeController()

    private static let functionKeyModeRestorePendingKey = "CoffeeCup.catMode.functionKeyModeRestorePending"
    private static let savedFunctionKeyModeKey = "CoffeeCup.catMode.savedFunctionKeyMode"
    private static let functionKeyRestoreFailureMessage = "CoffeeCup couldn’t restore your function-row setting. Check System Settings → Keyboard → Keyboard Shortcuts → Function Keys."

    @Published private(set) var isActive = false
    @Published private(set) var errorMessage: String?

    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var eventTapContext: CatModeEventTapContext?

    func restoreFunctionKeyModeAfterUnexpectedQuit() {
        guard UserDefaults.standard.bool(forKey: Self.functionKeyModeRestorePendingKey) else { return }
        guard restoreSavedFunctionKeyMode() else {
            errorMessage = Self.functionKeyRestoreFailureMessage
            return
        }
        errorMessage = nil
    }

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

        if restoreSavedFunctionKeyMode() {
            errorMessage = nil
        } else {
            errorMessage = Self.functionKeyRestoreFailureMessage
        }
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
                if self.errorMessage == nil {
                    self.errorMessage = "Cat Mode stopped because macOS disabled its input blocker."
                }
            }
        )

        guard prepareFunctionKeyMode() else { return }

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
            failToStart("Could not start Cat Mode. Check CoffeeCup’s Accessibility permission and try again.")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            failToStart("Could not start Cat Mode’s input monitor.")
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

    private func prepareFunctionKeyMode() -> Bool {
        guard !UserDefaults.standard.bool(forKey: Self.functionKeyModeRestorePendingKey) else {
            errorMessage = Self.functionKeyRestoreFailureMessage
            return false
        }

        guard let previousMode = FunctionKeyModeSetting.read() else {
            errorMessage = "Could not read the current function-row setting. Cat Mode was not started."
            return false
        }

        UserDefaults.standard.set(previousMode.rawValue, forKey: Self.savedFunctionKeyModeKey)
        UserDefaults.standard.set(true, forKey: Self.functionKeyModeRestorePendingKey)
        guard UserDefaults.standard.synchronize() else {
            clearSavedFunctionKeyMode()
            errorMessage = "Could not save your function-row setting. Cat Mode was not started."
            return false
        }

        if FunctionKeyModeSetting.read() == .standardFunctionKeys
            || (FunctionKeyModeSetting.write(true)
                && FunctionKeyModeSetting.read() == .standardFunctionKeys) {
            return true
        }

        failToStart("Could not switch the function row to standard F keys. Cat Mode was not started.")
        return false
    }

    private func failToStart(_ message: String) {
        if restoreSavedFunctionKeyMode() {
            errorMessage = message
        } else {
            errorMessage = Self.functionKeyRestoreFailureMessage
        }
    }

    @discardableResult
    private func restoreSavedFunctionKeyMode() -> Bool {
        guard UserDefaults.standard.bool(forKey: Self.functionKeyModeRestorePendingKey) else {
            return true
        }
        guard let rawValue = UserDefaults.standard.string(forKey: Self.savedFunctionKeyModeKey),
              let previousMode = FunctionKeyModeSnapshot(rawValue: rawValue),
              FunctionKeyModeSetting.restore(previousMode) else {
            return false
        }

        clearSavedFunctionKeyMode()
        return true
    }

    private func clearSavedFunctionKeyMode() {
        UserDefaults.standard.removeObject(forKey: Self.functionKeyModeRestorePendingKey)
        UserDefaults.standard.removeObject(forKey: Self.savedFunctionKeyModeKey)
        UserDefaults.standard.synchronize()
    }
}

private enum FunctionKeyModeSnapshot: String {
    case missing
    case mediaKeys
    case standardFunctionKeys
}

private enum FunctionKeyModeSetting {
    private static let preferenceKey = "com.apple.keyboard.fnState"

    static func read() -> FunctionKeyModeSnapshot? {
        guard let result = runDefaults(["read", "-g", preferenceKey]) else { return nil }
        guard result.status == 0 else { return .missing }

        switch result.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes":
            return .standardFunctionKeys
        case "0", "false", "no":
            return .mediaKeys
        default:
            return nil
        }
    }

    static func write(_ useStandardFunctionKeys: Bool) -> Bool {
        guard let result = runDefaults([
            "write", "-g", preferenceKey, "-bool", useStandardFunctionKeys ? "true" : "false"
        ]) else { return false }
        return result.status == 0
    }

    static func restore(_ snapshot: FunctionKeyModeSnapshot) -> Bool {
        switch snapshot {
        case .missing:
            guard let result = runDefaults(["delete", "-g", preferenceKey]) else { return false }
            return result.status == 0 || read() == .missing
        case .mediaKeys:
            return write(false) && read() == .mediaKeys
        case .standardFunctionKeys:
            return write(true) && read() == .standardFunctionKeys
        }
    }

    private static func runDefaults(_ arguments: [String]) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(data: output, encoding: .utf8) ?? ""
        )
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
