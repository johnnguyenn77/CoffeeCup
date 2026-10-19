import Foundation

@MainActor
final class MemoryKeyboardStore: KeyboardModifierStoring {
    var value: KeyboardModifierPreferences?
    var failSave = false
    var failLoad = false
    var saveCount = 0
    var failOnSave: Int?

    func load() throws -> KeyboardModifierPreferences? {
        if failLoad { throw KeyboardModifierError.invalidPreferences }
        return value
    }
    func save(_ preferences: KeyboardModifierPreferences) throws {
        saveCount += 1
        if failSave || failOnSave == saveCount { throw KeyboardModifierError.cannotSave }
        value = preferences
    }
}

@MainActor
final class FakeKeyboardHID: KeyboardHIDProviding {
    var connected: [ExternalKeyboard] = []
    var values: [UInt64: [ModifierKeyMapping]] = [:]
    var writes: [UInt64] = []
    var failNextWrite: UInt64?

    func keyboards() throws -> [ExternalKeyboard] { connected }
    func mapping(for serviceID: UInt64) throws -> [ModifierKeyMapping] {
        guard connected.contains(where: { $0.serviceIDs.contains(serviceID) }) else {
            throw KeyboardModifierError.deviceUnavailable
        }
        return values[serviceID] ?? []
    }
    func setMapping(_ mapping: [ModifierKeyMapping], for serviceID: UInt64) throws {
        if failNextWrite == serviceID { failNextWrite = nil; throw KeyboardModifierError.mappingNotApplied }
        values[serviceID] = mapping
        writes.append(serviceID)
    }
}

@main
enum KeyboardModifierTests {
    @MainActor static func main() throws {
        if CommandLine.arguments.contains("--inspect") {
            let provider = KeyboardHIDService()
            for keyboard in try provider.keyboards() {
                print("\(keyboard.name) | \(keyboard.id) | interfaces=\(keyboard.serviceIDs.count) | selectable=\(keyboard.isSelectable)")
            }
            let engine = try KeyboardModifierEngine(provider: provider, store: MemoryKeyboardStore(),
                bootSessionID: KeyboardHIDService.bootSessionID())
            try engine.refresh()
            print("Keyboard selector: \(engine.keyboards.map(\.name).joined(separator: ", "))")
            return
        }
        if let option = CommandLine.arguments.firstIndex(of: "--verify-live-swap") {
            guard CommandLine.arguments.indices.contains(option + 1) else {
                fatalError("Supply the exact keyboard ID from --inspect")
            }
            try verifyLiveSwap(id: CommandLine.arguments[option + 1])
            return
        }

        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            checks += 1
        }
        check(ExternalKeyboard.isExternal(builtIn: nil, transport: "USB", name: "Gaming Keyboard"),
              "USB keyboards can omit the Built-In property")
        check(ExternalKeyboard.isExternal(builtIn: false, transport: "Bluetooth", name: "Keyboard"),
              "External Bluetooth keyboards are eligible")
        check(!ExternalKeyboard.isExternal(builtIn: true, transport: "USB", name: "Keyboard"),
              "A built-in keyboard is excluded even on USB")
        check(!ExternalKeyboard.isExternal(builtIn: nil, transport: "FIFO", name: "Keyboard"),
              "An internal bus is excluded even without a Built-In property")
        check(!ExternalKeyboard.isExternal(builtIn: nil, transport: "USB", name: "Apple Internal Keyboard"),
              "Internal keyboard names fail closed")
        check(!ExternalKeyboard.isExternal(builtIn: nil, transport: nil, name: nil),
              "Unidentified services fail closed")
        check(ExternalKeyboard.isPrimaryUSBMouse(interfaceClass: 3, subclass: 1, protocolCode: 2),
              "Primary USB boot-mouse interface is recognized")
        check(!ExternalKeyboard.isPrimaryUSBMouse(interfaceClass: 3, subclass: 1, protocolCode: 1),
              "Primary USB keyboard interface remains selectable")
        check(!ExternalKeyboard.isPrimaryUSBMouse(interfaceClass: 3, subclass: 0, protocolCode: 2),
              "Protocol values on non-boot interfaces are not misinterpreted")
        check(!ExternalKeyboard.isPrimaryUSBMouse(interfaceClass: nil, subclass: nil, protocolCode: nil),
              "Unavailable USB metadata does not hide a legitimate keyboard")
        let unrelated = ModifierKeyMapping(source: 0x700000039, destination: 0x700000029)
        let customAlt = ModifierKeyMapping(source: 0x7000000E2, destination: 0x7000000E0)
        let original = [customAlt, unrelated]
        let applied = WindowsKeyboardMapping.applying(to: original)
        check(WindowsKeyboardMapping.swap.count == 4, "Both left and right modifier pairs")
        check(WindowsKeyboardMapping.isApplied(to: applied), "Swap contains all four expected directions")
        check(applied.contains(unrelated), "Unrelated Caps Lock mapping is preserved")
        check(!applied.contains(customAlt), "Explicit swap overrides a conflicting source while enabled")
        check(WindowsKeyboardMapping.restoring(original: original, current: applied) == original,
              "Untouched mapping is restored exactly, including original order")
        check(WindowsKeyboardMapping.applying(to: applied) == applied, "Repeated enable does not invert or duplicate")
        let laterUnrelated = ModifierKeyMapping(source: 0x700000004, destination: 0x700000005)
        check(WindowsKeyboardMapping.restoring(original: original, current: applied + [laterUnrelated]).contains(laterUnrelated),
              "A later unrelated edit is preserved when disabling")
        let laterAlt = ModifierKeyMapping(source: 0x7000000E2, destination: 0x7000000E1)
        let edited = applied.filter { $0.source != laterAlt.source } + [laterAlt]
        let restored = WindowsKeyboardMapping.restoring(original: original, current: edited)
        check(restored.contains(laterAlt) && !restored.contains(customAlt), "Later changes to owned sources are not clobbered")
        check(WindowsKeyboardMapping.restoring(original: original, current: []) == [], "An external reset is not undone on disable")

        let id = ExternalKeyboard.persistentID(vendorID: 1, productID: 2, transport: "USB", serialNumber: nil, locationID: 10)
        let differentPort = ExternalKeyboard.persistentID(vendorID: 1, productID: 2, transport: "USB", serialNumber: nil, locationID: 20)
        check(id != differentPort, "Identical serial-less keyboards at different ports are separate")
        let serial1 = ExternalKeyboard.persistentID(vendorID: 1, productID: 2, transport: "USB", serialNumber: "serial", locationID: 10)
        let serial2 = ExternalKeyboard.persistentID(vendorID: 1, productID: 2, transport: "USB", serialNumber: "serial", locationID: 20)
        check(serial1 == serial2, "A real serial number survives a port change")

        let keyboard = ExternalKeyboard(id: id, name: "Test Keyboard", vendorID: 1, productID: 2,
            locationID: 10, transport: "USB", hasPointerInterface: false, serviceIDs: [11, 12])
        let other = ExternalKeyboard(id: differentPort, name: "Other Keyboard", vendorID: 1, productID: 2,
            locationID: 20, transport: "USB", hasPointerInterface: false, serviceIDs: [21])
        let gamingKeyboard = ExternalKeyboard(id: "gaming", name: "Wireless Gaming Keyboard", vendorID: 1,
            productID: 3, locationID: 30, transport: "USB", hasPointerInterface: true, serviceIDs: [41])
        let gamingMouse = ExternalKeyboard(id: "mouse", name: "Razer Mouse", vendorID: 2,
            productID: 4, locationID: 40, transport: "USB", hasPointerInterface: true, serviceIDs: [51])
        check([gamingMouse, gamingKeyboard].sorted(by: ExternalKeyboard.preferredBefore).first?.id == "gaming",
              "Prefer a named keyboard even when both devices also expose pointer interfaces")
        let provider = FakeKeyboardHID()
        provider.connected = [keyboard, other]
        provider.values = [11: original, 12: [], 21: [unrelated]]
        let store = MemoryKeyboardStore()
        var engine = try KeyboardModifierEngine(provider: provider, store: store, bootSessionID: "boot-A")
        try engine.refresh()
        check(engine.keyboards.count == 2 && provider.writes.isEmpty, "Detect already-connected keyboards without changing them")
        check(engine.preferences.selectedKeyboardID == id, "First external keyboard is selected but not enabled")
        try engine.setEnabled(true, for: id)
        check(provider.values[11] == applied && provider.values[12] == WindowsKeyboardMapping.swap,
              "All interfaces of only the selected keyboard are mapped")
        check(provider.values[21] == [unrelated], "Unselected keyboard remains unchanged")
        check(store.value?.leases.count == 2, "Originals are journaled per service before write")
        check(engine.appliedKeyboardIDs == [id], "Report enabled only after all interfaces succeed")
        let writesBeforeRefresh = provider.writes.count
        try engine.refresh()
        check(provider.writes.count == writesBeforeRefresh, "Periodic verification does not repeatedly rewrite")
        engine = try KeyboardModifierEngine(provider: provider, store: store, bootSessionID: "boot-A")
        try engine.refresh()
        check(engine.preferences.leases["11"]?.original == original, "Crash/relaunch retains the original, not the already-swapped map")
        try engine.setEnabled(false, for: id)
        check(provider.values[11] == original && provider.values[12] == [], "Disable restores both original interfaces")
        check(engine.preferences.leases.isEmpty, "Completed restoration clears its journal")

        try engine.setEnabled(true, for: id)
        provider.connected = []
        try engine.refresh()
        check(engine.keyboards.isEmpty && engine.preferences.enabledKeyboardIDs.contains(id), "Disconnect hides controls, retaining the opt-in")
        check(!engine.preferences.leases.isEmpty, "Temporary incomplete enumeration does not discard recovery snapshots")
        var reconnected = keyboard
        reconnected.serviceIDs = [31, 32]
        provider.connected = [reconnected, other]
        provider.values[31] = [unrelated]
        provider.values[32] = []
        try engine.refresh()
        check(WindowsKeyboardMapping.isApplied(to: provider.values[31] ?? []), "KVM reconnect auto-applies to new service IDs")
        check(engine.preferences.leases["31"]?.original == [unrelated], "A replacement service gets its own baseline")
        provider.values[31] = []
        try engine.refresh()
        check(WindowsKeyboardMapping.isApplied(to: provider.values[31] ?? []), "KVM reset with the same service ID is repaired")
        provider.values[31] = (provider.values[31] ?? []).filter { $0.source != laterAlt.source } + [laterAlt]
        do { try engine.refresh(); preconditionFailure("Conflicting modifiers must be reported") }
        catch { checks += 1 }
        check(provider.values[31]?.contains(laterAlt) == true, "Background retry does not fight another remapper")
        check(!engine.preferences.enabledKeyboardIDs.contains(id), "A background conflict safely disables the swap")
        let beforeConflictRetry = provider.writes.count
        try engine.refresh()
        check(provider.writes.count == beforeConflictRetry, "Do not repeatedly fight another remapper after a conflict")
        try engine.setEnabled(false, for: id)
        check(provider.values[31]?.contains(laterAlt) == true, "Disable preserves later remapper's conflicting change")

        try engine.setEnabled(true, for: id)
        try engine.restoreBeforeQuit()
        check(engine.preferences.enabledKeyboardIDs.contains(id), "Quit keeps opt-in preference for the next app launch")
        check(!WindowsKeyboardMapping.isApplied(to: provider.values[31] ?? []), "Quit removes the live swap")
        engine = try KeyboardModifierEngine(provider: provider, store: store, bootSessionID: "boot-B")
        check(engine.preferences.leases.isEmpty, "Reboot invalidates all old registry-ID recovery leases")
        try engine.refresh()
        check(WindowsKeyboardMapping.isApplied(to: provider.values[31] ?? []), "Saved opt-in reapplies on a later boot")
        try engine.setEnabled(false, for: id)

        let failureStore = MemoryKeyboardStore()
        let failureEngine = try KeyboardModifierEngine(provider: provider, store: failureStore, bootSessionID: "boot-B")
        try failureEngine.refresh()
        provider.failNextWrite = 32
        let beforeFailure = provider.values
        do { try failureEngine.setEnabled(true, for: id); preconditionFailure("Partial failure must throw") }
        catch { checks += 1 }
        check(provider.values == beforeFailure, "A failed second interface rolls back the first")
        check(!failureEngine.preferences.enabledKeyboardIDs.contains(id), "Failed enable does not leave opt-in on")
        check(failureEngine.preferences.leases.isEmpty, "Successful rollback clears all recovery journals")
        failureStore.failSave = true
        let beforeSaveFailure = provider.writes.count
        do { try failureEngine.setEnabled(true, for: id); preconditionFailure("Unjournaled writes must be refused") }
        catch { checks += 1 }
        check(provider.writes.count == beforeSaveFailure, "No hardware write when preferences cannot be saved")
        check(!failureEngine.preferences.enabledKeyboardIDs.contains(id), "Failed save leaves in-memory preference unchanged")
        failureStore.failSave = false
        failureStore.failOnSave = failureStore.saveCount + 2
        let beforeJournalFailure = provider.writes.count
        do { try failureEngine.setEnabled(true, for: id); preconditionFailure("Snapshot save failure must throw") }
        catch { checks += 1 }
        check(provider.writes.count == beforeJournalFailure, "Refuse hardware writes when original-map journal cannot be saved")
        check(!failureEngine.preferences.enabledKeyboardIDs.contains(id), "Journal failure rolls back the opt-in")
        failureStore.failOnSave = nil
        let beforeReconnect = provider.values[31]
        try failureEngine.setEnabled(true, for: id)
        provider.values[31] = []
        provider.values[32] = []
        provider.failNextWrite = 32
        do { try failureEngine.refresh(); preconditionFailure("Partial reconnect failure must throw") }
        catch { checks += 1 }
        check(provider.values[31] == beforeReconnect && provider.values[32] == [],
              "Failed reconnect restores the first interface baseline without modifying the failed interface")
        check(!failureEngine.preferences.enabledKeyboardIDs.contains(id), "Failed reconnect leaves no partial swap enabled")

        var hiddenMouse = gamingMouse
        hiddenMouse.isSelectable = false
        let filteredProvider = FakeKeyboardHID()
        filteredProvider.connected = [hiddenMouse, gamingKeyboard]
        let filteredStore = MemoryKeyboardStore()
        let filteredEngine = try KeyboardModifierEngine(provider: filteredProvider, store: filteredStore,
            bootSessionID: "boot-B")
        try filteredEngine.refresh()
        check(filteredEngine.keyboards.map(\.id) == [gamingKeyboard.id], "Mouse helper interfaces are hidden from selection")
        check(filteredEngine.preferences.selectedKeyboardID == gamingKeyboard.id, "Select the actual keyboard, not the mouse")
        check(filteredProvider.writes.isEmpty, "Filtering an unused mouse does not modify it")
        do {
            try filteredEngine.setEnabled(true, for: hiddenMouse.id)
            preconditionFailure("A hidden mouse must not be remapped")
        } catch { checks += 1 }
        var previousPreferences = KeyboardModifierPreferences(bootSessionID: "boot-B")
        previousPreferences.selectedKeyboardID = hiddenMouse.id
        previousPreferences.enabledKeyboardIDs = [hiddenMouse.id]
        previousPreferences.leases["51"] = KeyboardMappingLease(keyboardID: hiddenMouse.id,
            serviceID: 51, original: [unrelated])
        filteredStore.value = previousPreferences
        filteredProvider.values[51] = WindowsKeyboardMapping.applying(to: [unrelated])
        let recoveryEngine = try KeyboardModifierEngine(provider: filteredProvider, store: filteredStore,
            bootSessionID: "boot-B")
        try recoveryEngine.refresh()
        check(filteredProvider.values[51] == [unrelated], "Restore a mouse that was remapped before filtering was added")
        check(!recoveryEngine.preferences.enabledKeyboardIDs.contains(hiddenMouse.id), "Remove the obsolete mouse opt-in")
        check(recoveryEngine.preferences.leases.isEmpty, "Clear the mouse recovery journal only after restoring it")
        check(recoveryEngine.keyboards.map(\.id) == [gamingKeyboard.id], "Keep a real keyboard with pointer interfaces available")

        let visibilityProvider = FakeKeyboardHID()
        let visibilityEngine = try KeyboardModifierEngine(provider: visibilityProvider,
            store: MemoryKeyboardStore(), bootSessionID: "boot-B")
        try visibilityEngine.refresh()
        check(visibilityEngine.keyboards.isEmpty, "No swap section when starting without an external keyboard")
        visibilityProvider.connected = [hiddenMouse]
        try visibilityEngine.refresh()
        check(visibilityEngine.keyboards.isEmpty, "Connecting only a mouse does not reveal the swap section")
        visibilityProvider.connected = [hiddenMouse, gamingKeyboard]
        try visibilityEngine.refresh()
        check(!visibilityEngine.keyboards.isEmpty, "Connecting an external keyboard reveals the swap section")
        visibilityProvider.connected = [hiddenMouse]
        try visibilityEngine.refresh()
        check(visibilityEngine.keyboards.isEmpty, "Disconnecting the last keyboard hides the section while the mouse remains")
        visibilityProvider.connected = [gamingKeyboard]
        try visibilityEngine.refresh()
        check(visibilityEngine.keyboards.map(\.id) == [gamingKeyboard.id], "Reconnecting a keyboard restores the section")
        check(visibilityProvider.writes.isEmpty, "Detection and visibility changes do not apply any unsolicited mappings")

        let invalidStore = MemoryKeyboardStore()
        invalidStore.failLoad = true
        do {
            _ = try KeyboardModifierEngine(provider: provider, store: invalidStore, bootSessionID: "boot-B")
            preconditionFailure("Unreadable recovery state must fail closed")
        } catch { checks += 1 }
        print("PASS: \(checks) external-keyboard modifier checks")
    }

    @MainActor private static func verifyLiveSwap(id: String) throws {
        let provider = KeyboardHIDService()
        let connected = try provider.keyboards()
        guard let target = connected.first(where: { $0.id == id }) else {
            throw KeyboardModifierError.deviceUnavailable
        }
        var originals: [UInt64: [ModifierKeyMapping]] = [:]
        for keyboard in connected {
            for service in keyboard.serviceIDs { originals[service] = try provider.mapping(for: service) }
        }
        let store = MemoryKeyboardStore()
        let engine = try KeyboardModifierEngine(provider: provider, store: store,
                                               bootSessionID: KeyboardHIDService.bootSessionID())
        try engine.refresh()
        // Always attempt rollback before exiting this explicitly requested live hardware check.
        defer { try? engine.restoreBeforeQuit() }
        try engine.setEnabled(true, for: target.id)
        for service in target.serviceIDs {
            let mapping = try provider.mapping(for: service)
            guard WindowsKeyboardMapping.isApplied(to: mapping) else { throw LiveCheckError.verificationFailed }
        }
        for keyboard in connected where keyboard.id != id {
            for service in keyboard.serviceIDs {
                let mapping = try provider.mapping(for: service)
                guard mapping == originals[service] else { throw LiveCheckError.verificationFailed }
            }
        }
        try engine.setEnabled(false, for: target.id)
        for (service, baseline) in originals {
            let mapping = try provider.mapping(for: service)
            guard mapping == baseline else { throw LiveCheckError.verificationFailed }
        }
        print("PASS: live swap and exact restoration on \(target.name), \(target.serviceIDs.count) interfaces; other external devices unchanged")
    }

    private enum LiveCheckError: Error { case verificationFailed }
}
