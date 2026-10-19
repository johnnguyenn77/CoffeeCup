import Foundation

/// Owns only four source usages on explicitly enabled external keyboard services.
/// The persisted journal makes repeated launches idempotent and preserves the pre-swap values.
@MainActor
final class KeyboardModifierEngine {
    private let provider: KeyboardHIDProviding
    private let store: KeyboardModifierStoring
    private(set) var preferences: KeyboardModifierPreferences
    private(set) var keyboards: [ExternalKeyboard] = []
    private(set) var appliedKeyboardIDs: Set<String> = []
    private var failedKeyboardIDs: Set<String> = []

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
    func refresh() throws -> [ExternalKeyboard] {
        let connected = try provider.keyboards()
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
                    catch { throw rollBackFailedEnable(keyboard) ?? error }
                    appliedKeyboardIDs.insert(keyboard.id)
                } else {
                    try restore(keyboard)
                }
            } catch { if firstError == nil { firstError = error } }
        }
        if let firstError { throw firstError }
        return keyboards
    }

    func selectKeyboard(_ id: String) throws {
        guard keyboards.contains(where: { $0.id == id }) else { throw KeyboardModifierError.deviceUnavailable }
        try update { $0.selectedKeyboardID = id }
    }

    func setEnabled(_ enabled: Bool, for id: String) throws {
        guard let keyboard = keyboards.first(where: { $0.id == id }) else {
            throw KeyboardModifierError.deviceUnavailable
        }
        failedKeyboardIDs.remove(id)
        if enabled {
            try update { $0.enabledKeyboardIDs.insert(id) }
            do {
                try apply(keyboard, explicitlyEnabled: true)
                appliedKeyboardIDs.insert(id)
            } catch {
                throw rollBackFailedEnable(keyboard) ?? error
            }
        } else {
            try update { $0.enabledKeyboardIDs.remove(id) }
            appliedKeyboardIDs.remove(id)
            try restore(keyboard)
        }
    }

    func restoreBeforeQuit() throws {
        // Keep the opt-in preference for the next launch, but remove CoffeeCup's live remaps now.
        let connected = try provider.keyboards()
        keyboards = connected.filter(\.isSelectable)
        var firstError: Error?
        for keyboard in connected {
            do { try restore(keyboard) }
            catch { if firstError == nil { firstError = error } }
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
                guard explicitlyEnabled || modifiedSources.isEmpty || current == lease.original else {
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
                if restored != current { try provider.setMapping(restored, for: serviceID) }
                try update { $0.leases.removeValue(forKey: key) }
            } catch { if firstError == nil { firstError = error } }
        }
        if let firstError { throw firstError }
    }

    private func rollBackFailedEnable(_ keyboard: ExternalKeyboard) -> Error? {
        // Roll back every interface, including when a reconnect fails partway through.
        // Stop retrying until the user opts in again, rather than fighting another remapper.
        failedKeyboardIDs.insert(keyboard.id)
        appliedKeyboardIDs.remove(keyboard.id)
        var cleanupError: Error?
        do { try update { $0.enabledKeyboardIDs.remove(keyboard.id) } }
        catch { cleanupError = error }
        do { try restore(keyboard) }
        catch { cleanupError = error }
        return cleanupError
    }

    private func update(_ change: (inout KeyboardModifierPreferences) -> Void) throws {
        var updated = preferences
        change(&updated)
        try store.save(updated)
        preferences = updated
    }
}
