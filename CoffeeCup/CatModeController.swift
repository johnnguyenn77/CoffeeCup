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

    private var inputSession: CatModeInputSession?

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
        let session = inputSession
        inputSession = nil
        session?.stop()
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

        guard let session = CatModeInputSession.make(onStopped: { [weak self] id, reason in
            guard let self, self.inputSession?.id == id else { return }
            self.stop()
            if reason == .disabled, self.errorMessage == nil {
                self.errorMessage = "Cat Mode stopped because macOS disabled its input blocker."
            }
        }) else {
            failToStart("Could not start Cat Mode. Check CoffeeCup’s Accessibility permission and try again.")
            return
        }

        inputSession = session
        session.start()
        isActive = true
        errorMessage = nil
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

nonisolated enum CatModeSystemDefinedKey {
    // NSEventTypeSystemDefined / NX_SYSDEFINED is 14. Its auxiliary-control
    // subtype (8) packs the NX_KEYTYPE value into the upper 16 bits of data1.
    static let eventTypeValue: UInt32 = 14
    private static let auxiliaryControlButtonsSubtype: Int16 = 8

    // Suppress function-row media actions, but deliberately leave power and
    // unknown system-defined events untouched.
    private static let suppressedKeyTypes: Set<Int> = [
        0, 1,             // Volume up/down
        2, 3,             // Display brightness up/down
        7,                // Mute
        11, 12,           // Contrast up/down
        13, 14, 15,       // Launch panel, eject, video mirroring
        16, 17, 18, 19, 20, // Playback controls
        21, 22, 23        // Keyboard illumination
    ]

    static func shouldSuppress(_ event: CGEvent) -> Bool {
        // The dedicated CF run loop doesn't get AppKit's per-event autorelease pool.
        return autoreleasepool {
            guard let systemEvent = NSEvent(cgEvent: event),
                  systemEvent.subtype.rawValue == auxiliaryControlButtonsSubtype else {
                return false
            }
            let keyType = Int((systemEvent.data1 >> 16) & 0xFFFF)
            return suppressedKeyTypes.contains(keyType)
        }
    }
}
