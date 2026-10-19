import Foundation

nonisolated struct KeyboardModifierSnapshot: Sendable {
    var keyboards: [ExternalKeyboard] = []
    var selectedKeyboardID: String?
    var swapsModifiers = false
    var needsPeriodicVerification = false
    var errorMessage: String?
}

/// All engine, preference-journal and HID access is confined to this queue. Only
/// immutable snapshots cross to the UI; no permanent background thread is needed.
nonisolated final class KeyboardModifierWorker: @unchecked Sendable {
    enum Operation: Sendable {
        case refresh(invalidateDiscovery: Bool)
        case select(String)
        case setEnabled(Bool, String)
    }

    private let queue = DispatchQueue(label: "CoffeeCup.keyboard", qos: .utility)
    private var engine: KeyboardModifierEngine?

    init(engine: KeyboardModifierEngine? = nil) {
        self.engine = engine
    }

    func perform(_ operation: Operation,
                 completion: @escaping @MainActor @Sendable (KeyboardModifierSnapshot) -> Void) {
        queue.async { [self] in
            let state: KeyboardModifierSnapshot
            do {
                if engine == nil {
                    engine = try KeyboardModifierEngine(provider: KeyboardHIDService(),
                        store: KeyboardModifierDefaultsStore(), bootSessionID: KeyboardHIDService.bootSessionID())
                }
                if let engine {
                    switch operation {
                    case .refresh(let invalidate):
                        try engine.refresh(invalidateDiscovery: invalidate)
                    case .select(let id):
                        try engine.refresh(invalidateDiscovery: true)
                        try engine.selectKeyboard(id)
                    case .setEnabled(let enabled, let id):
                        try engine.refresh(invalidateDiscovery: true)
                        try engine.setEnabled(enabled, for: id)
                    }
                }
                state = snapshot()
            } catch {
                state = snapshot(error: error.localizedDescription)
            }
            DispatchQueue.main.async { completion(state) }
        }
    }

    /// Termination must finish restoring live mappings before the process exits.
    /// Work queued before quit completes first; nothing on this queue waits on the UI.
    func restoreBeforeQuit() -> KeyboardModifierSnapshot {
        queue.sync {
            do { try engine?.restoreBeforeQuit(); return snapshot() }
            catch { return snapshot(error: error.localizedDescription) }
        }
    }

    private func snapshot(error: String? = nil) -> KeyboardModifierSnapshot {
        guard let engine else { return KeyboardModifierSnapshot(errorMessage: error) }
        let selection = engine.preferences.selectedKeyboardID
        return KeyboardModifierSnapshot(keyboards: engine.keyboards,
            selectedKeyboardID: selection,
            swapsModifiers: selection.map { engine.appliedKeyboardIDs.contains($0) } ?? false,
            needsPeriodicVerification: engine.needsPeriodicVerification,
            errorMessage: error)
    }
}
