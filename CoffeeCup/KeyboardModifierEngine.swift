import Foundation

/// Owns only four source usages on explicitly enabled external keyboard services.
/// The persisted journal makes repeated launches idempotent and preserves the pre-swap values.
nonisolated final class KeyboardModifierEngine {
    private let provider: KeyboardHIDProviding
    private let store: KeyboardModifierStoring
    private(set) var preferences: KeyboardModifierPreferences
    private(set) var keyboards: [ExternalKeyboard] = []
    private(set) var appliedKeyboardIDs: Set<String> = []
    private var failedKeyboardIDs: Set<String> = []
    private var connectedServiceIDs: Set<UInt64> = []

    var needsPeriodicVerification: Bool {
        keyboards.contains { preferences.enabledKeyboardIDs.contains($0.id) }
            || preferences.leases.values.contains { connectedServiceIDs.contains($0.serviceID) }
    }

    init(provider: KeyboardHIDProviding, store: KeyboardModifierStoring, bootSessionID: String) throws {
        self.provider = provider
        self.store = store
        var preferences = try store.load() ?? KeyboardModifierPreferences(bootSessionID: bootSessionID)
        if preferences.bootSessionID != bootSessionID {
            // HID registry IDs can be reused after reboot. Never restore a lease from a different boot.
            preferences.bootSessionID = bootSessionID
            preferences.leases = [:]
            try store.save(preferences)
        }
        self.preferences = preferences
    }

    @discardableResult
    func refresh(invalidateDiscovery: Bool = false) throws -> [ExternalKeyboard] {
        if invalidateDiscovery { provider.invalidateDiscoveryCache() }
        let connected: [ExternalKeyboard]
        do { connected = try provider.keyboards() }
        catch {
            // Discovery is temporarily unavailable. Hide stale controls and stop
            // connected-device polling, but retain preferences and recovery leases.
            keyboards = []
            connectedServiceIDs = []
            appliedKeyboardIDs = []
            throw error
        }
        connectedServiceIDs = Set(connected.flatMap(\.serviceIDs))
        keyboards = connected.filter(\.isSelectable)
        appliedKeyboardIDs = []
        // Keep missing services' leases until the next boot. A temporarily incomplete enumeration
        // must never discard the only original-map snapshot for a service that is still alive.
        if !keyboards.contains(where: { $0.id == preferences.selectedKeyboardID }), let first = keyboards.first {
            try update { $0.selectedKeyboardID = first.id }
        }

        var firstError: Error?
        for keyboard in connected {
            do {
                if !keyboard.isSelectable {
                    // A mouse may have been enabled before helper interfaces were filtered.
                    // Restore our old mappings even though it no longer appears in the selector.
                    if preferences.enabledKeyboardIDs.contains(keyboard.id)
                        || preferences.leases.values.contains(where: { $0.keyboardID == keyboard.id }) {
                        if let error = rollBackFailedEnable(keyboard) { throw error }
                    }
                    continue
                }
                if preferences.enabledKeyboardIDs.contains(keyboard.id), !failedKeyboardIDs.contains(keyboard.id) {
                    do { try apply(keyboard, explicitlyEnabled: false) }
                    catch {
                        // KVM transitions can remove a service halfway through a refresh. Undo
                        // partial writes, but retain the saved opt-in and retry on the next scan.
                        let retry = (error as? KeyboardModifierError)?.canRetryAfterReconnect == true
                        let cleanupError = rollBackFailedEnable(keyboard, disablePreference: !retry)
                        throw cleanupError.map { preferredError(error, $0) } ?? error
                    }
                    appliedKeyboardIDs.insert(keyboard.id)
                } else {
                    try restore(keyboard)
                }
            } catch {
                if case .deviceUnavailable? = error as? KeyboardModifierError {
                    forgetConnection(keyboard)
                }
                firstError = preferredError(firstError, error)
            }
        }
        if let firstError { throw firstError }
        return keyboards
    }

    func selectKeyboard(_ id: String) throws {
        guard keyboards.contains(where: { $0.id == id }) else { throw KeyboardModifierError.deviceUnavailable }
        try update { $0.selectedKeyboardID = id }
    }

    func setEnabled(_ enabled: Bool, for id: String) throws {
        if !enabled {
            try update { $0.enabledKeyboardIDs.remove(id) }
            appliedKeyboardIDs.remove(id)
            failedKeyboardIDs.remove(id)
            if let keyboard = keyboards.first(where: { $0.id == id }) { try restore(keyboard) }
            return
        }
        guard let keyboard = keyboards.first(where: { $0.id == id }) else {
            throw KeyboardModifierError.deviceUnavailable
        }
        failedKeyboardIDs.remove(id)
        try update { $0.enabledKeyboardIDs.insert(id) }
        do {
            try apply(keyboard, explicitlyEnabled: true)
            appliedKeyboardIDs.insert(id)
        } catch {
            // An unplug during an explicit enable must not erase the user's opt-in.
            let disconnected: Bool
            if case .deviceUnavailable? = error as? KeyboardModifierError { disconnected = true }
            else { disconnected = false }
            let cleanupError = rollBackFailedEnable(keyboard, disablePreference: !disconnected)
            if disconnected { forgetConnection(keyboard) }
            throw cleanupError.map { preferredError(error, $0) } ?? error
        }
    }

    func restoreBeforeQuit() throws {
        // Keep the opt-in preference for the next launch, but remove CoffeeCup's live remaps now.
        let connected = try provider.keyboards()
        keyboards = connected.filter(\.isSelectable)
        var firstError: Error?
        for keyboard in connected {
            do { try restore(keyboard) }
            catch { firstError = preferredError(firstError, error) }
        }
        appliedKeyboardIDs = []
        if let firstError { throw firstError }
    }

    private func apply(_ keyboard: ExternalKeyboard, explicitlyEnabled: Bool) throws {
        for serviceID in keyboard.serviceIDs {
            let key = String(serviceID)
            let current = try provider.mapping(for: serviceID)
            if let lease = preferences.leases[key] {
                guard lease.keyboardID == keyboard.id else { throw KeyboardModifierError.deviceUnavailable }
                if WindowsKeyboardMapping.isApplied(to: current) { continue }
                let modifiedSources = current.filter { WindowsKeyboardMapping.sources.contains($0.source) }
                guard explicitlyEnabled || modifiedSources.isEmpty
                        || ModifierKeyMapping.equivalent(current, lease.original) else {
                    throw KeyboardModifierError.changedElsewhere
                }
            } else {
                try update {
                    $0.leases[key] = KeyboardMappingLease(keyboardID: keyboard.id,
                        serviceID: serviceID, original: current)
                }
            }
            try provider.setMapping(WindowsKeyboardMapping.applying(to: current), for: serviceID)
        }
    }

    private func restore(_ keyboard: ExternalKeyboard) throws {
        var firstError: Error?
        for serviceID in keyboard.serviceIDs {
            let key = String(serviceID)
            guard let lease = preferences.leases[key], lease.keyboardID == keyboard.id else { continue }
            do {
                let current = try provider.mapping(for: serviceID)
                let restored = WindowsKeyboardMapping.restoring(original: lease.original, current: current)
                if !ModifierKeyMapping.equivalent(restored, current) {
                    try provider.setMapping(restored, for: serviceID)
                }
                try update { $0.leases.removeValue(forKey: key) }
            } catch { firstError = preferredError(firstError, error) }
        }
        if let firstError { throw firstError }
    }

    private func rollBackFailedEnable(_ keyboard: ExternalKeyboard, disablePreference: Bool = true) -> Error? {
        // Roll back every interface, including when a reconnect fails partway through.
        // Stop retrying until the user opts in again, rather than fighting another remapper.
        if disablePreference { failedKeyboardIDs.insert(keyboard.id) }
        appliedKeyboardIDs.remove(keyboard.id)
        var cleanupError: Error?
        if disablePreference {
            do { try update { $0.enabledKeyboardIDs.remove(keyboard.id) } }
            catch { cleanupError = error }
        }
        do { try restore(keyboard) }
        catch { cleanupError = preferredError(cleanupError, error) }
        return cleanupError
    }

    private func preferredError(_ previous: Error?, _ next: Error) -> Error {
        guard let previous else { return next }
        // A disappearing service must not hide a settings/journal failure from
        // another interface or keyboard in the same scan.
        if (previous as? KeyboardModifierError)?.canRetryAfterReconnect == true,
           (next as? KeyboardModifierError)?.canRetryAfterReconnect != true { return next }
        if (previous as? KeyboardModifierError)?.canRetryAfterReconnect == true,
           case .deviceUnavailable? = next as? KeyboardModifierError { return next }
        return previous
    }

    private func forgetConnection(_ keyboard: ExternalKeyboard) {
        keyboards.removeAll { $0.id == keyboard.id }
        connectedServiceIDs.subtract(keyboard.serviceIDs)
        appliedKeyboardIDs.remove(keyboard.id)
    }

    private func update(_ change: (inout KeyboardModifierPreferences) -> Void) throws {
        var updated = preferences
        change(&updated)
        guard updated != preferences else { return }
        try store.save(updated)
        preferences = updated
    }
}
