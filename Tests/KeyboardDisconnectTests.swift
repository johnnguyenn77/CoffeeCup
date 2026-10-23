import Foundation

/// Drives the production recovery sequence without waiting on wall-clock timers
/// or touching the real HID registry.
@MainActor
private final class ManualKeyboardRefreshScheduler {
    private var pending: [DispatchWorkItem] = []
    private(set) var delays: [TimeInterval] = []

    var pendingCount: Int { pending.filter { !$0.isCancelled }.count }

    func schedule(after delay: TimeInterval, work: DispatchWorkItem) {
        delays.append(delay)
        pending.append(work)
    }

    @discardableResult func runNext() -> Bool {
        while !pending.isEmpty {
            let work = pending.removeFirst()
            if !work.isCancelled {
                work.perform()
                return true
            }
        }
        return false
    }
}

@MainActor
enum KeyboardDisconnectTests {
    static func run() async throws -> Int {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }

        let keyboard = ExternalKeyboard(id: "kvm", name: "KVM Keyboard", vendorID: 1, productID: 2,
            locationID: 3, transport: "USB", hasPointerInterface: false, serviceIDs: [101, 102])
        let provider = FakeKeyboardHID()
        let store = MemoryKeyboardStore()
        let scheduler = ManualKeyboardRefreshScheduler()
        provider.connected = [keyboard]
        let engine = try KeyboardModifierEngine(provider: provider, store: store, bootSessionID: "test")
        let controller = KeyboardModifierController(engine: engine, scheduleRefreshWork: scheduler.schedule)
        controller.start()
        defer { controller.stop() }
        await controller.waitUntilIdle()
        controller.setSwapEnabled(true, for: keyboard.id)
        await controller.waitUntilIdle()

        // A service disappears after discovery and after the first interface was remapped.
        provider.values[101] = []
        provider.values[102] = []
        provider.disconnectOnRead = 102
        controller.refresh()
        await controller.waitUntilIdle()
        check(controller.errorMessage == nil, "An unplug halfway through a mapping check is silent")
        check(!controller.hasKeyboards && !controller.swapsModifiers,
              "A vanished keyboard immediately loses its controls and active checkmark")
        check(!controller.needsPeriodicVerification, "Disconnect stops connected-device verification")
        check(engine.preferences.enabledKeyboardIDs.contains(keyboard.id) && !engine.preferences.leases.isEmpty,
              "An unplug preserves the opt-in and the original-map recovery journal")
        check(scheduler.pendingCount == 1, "Recovery is scheduled even without a connected-device timer")

        check(scheduler.runNext(), "The first settling scan is scheduled")
        await controller.waitUntilIdle()
        check(!controller.hasKeyboards && controller.errorMessage == nil,
              "A clean scan with no keyboards clears any disconnect warning")
        check(scheduler.pendingCount == 1, "An early empty enumeration still gets a bounded follow-up")

        var reconnected = keyboard
        reconnected.serviceIDs = [201, 202]
        provider.connected = [reconnected]
        check(scheduler.runNext(), "Recovery retries a slowly enumerating KVM")
        await controller.waitUntilIdle()
        check(controller.swapsModifiers && controller.errorMessage == nil,
              "A delayed reconnect reapplies the preference without restarting the app")
        check(WindowsKeyboardMapping.isApplied(to: provider.values[201] ?? [])
              && WindowsKeyboardMapping.isApplied(to: provider.values[202] ?? []),
              "The reconnected keyboard's new interfaces are both mapped")
        let writes = provider.writes.count
        check(scheduler.runNext(), "The final settling scan is scheduled")
        await controller.waitUntilIdle()
        check(provider.writes.count == writes, "Settling scans do not rewrite a working mapping")
        check(scheduler.pendingCount == 0 && !scheduler.runNext(), "Recovery stops after three scans")
        check(scheduler.delays == [0.35, 1, 2], "Recovery is a short settling sequence, not permanent polling")

        // A failed enumeration must not leave stale controls, or require a future hot-plug.
        let invalidations = provider.cacheInvalidations
        provider.scanError = .deviceUnavailable
        controller.refresh()
        await controller.waitUntilIdle()
        check(!controller.hasKeyboards && !controller.swapsModifiers && !controller.needsPeriodicVerification,
              "Unavailable discovery discards only the stale connected-device snapshot")
        check(controller.errorMessage == nil, "Unavailable discovery does not leave a missing-keyboard reminder")
        for _ in 0..<3 {
            check(scheduler.runNext(), "A failed discovery gets a recovery attempt")
            await controller.waitUntilIdle()
        }
        check(provider.cacheInvalidations == invalidations + 3, "Every recovery attempt requests fresh HID discovery")
        check(scheduler.pendingCount == 0, "Persistent unavailability cannot recursively schedule more retries")
        controller.refresh()
        await controller.waitUntilIdle()
        check(scheduler.pendingCount == 0, "The same failure episode does not restart the retry budget")
        provider.scanError = nil
        controller.refresh(invalidateDiscovery: true)
        await controller.waitUntilIdle()
        check(controller.swapsModifiers && controller.errorMessage == nil,
              "A later manual/open-popover refresh recovers without restarting CoffeeCup")

        // Disconnect bursts replace prior settling work, including a scan already in flight.
        controller.devicesDidChange()
        check(scheduler.runNext(), "A topology change begins fresh settling work")
        for _ in 0..<12 { controller.devicesDidChange() }
        await controller.waitUntilIdle()
        check(scheduler.pendingCount == 1, "An obsolete scan cannot restart an older recovery sequence")
        provider.connected = []
        for _ in 0..<3 {
            check(scheduler.runNext(), "The latest topology change keeps its settling attempts")
            await controller.waitUntilIdle()
        }
        check(scheduler.pendingCount == 0 && !controller.hasKeyboards && controller.errorMessage == nil,
              "An ordinary unplug finishes quietly and leaves no recovery work running")

        // A verify failure on a keyboard that remains present is a real, visible failure.
        provider.connected = [reconnected]
        provider.mappingErrors[201] = .mappingNotApplied
        controller.refresh()
        await controller.waitUntilIdle()
        check(controller.errorMessage == KeyboardModifierError.mappingNotApplied.localizedDescription,
              "A real mapping verification failure stays visible")
        for _ in 0..<3 {
            check(scheduler.runNext(), "A transient mapping failure receives a bounded retry")
            await controller.waitUntilIdle()
        }
        controller.refresh()
        await controller.waitUntilIdle()
        check(controller.errorMessage != nil && scheduler.pendingCount == 0,
              "Persistent mapping failures remain visible without creating an endless retry chain")
        provider.mappingErrors = [:]
        controller.refresh()
        await controller.waitUntilIdle()
        check(controller.swapsModifiers && controller.errorMessage == nil, "Success clears a previous verification error")
        controller.devicesDidChange()
        let scansBeforeStop = provider.scanCount
        controller.stop()
        check(scheduler.pendingCount == 0 && !scheduler.runNext(), "Quit cancels all delayed recovery work")
        check(provider.scanCount == scansBeforeStop + 1, "Quit performs only its final restoration scan")

        let enablingProvider = FakeKeyboardHID()
        enablingProvider.connected = [keyboard]
        let enablingStore = MemoryKeyboardStore()
        let enablingScheduler = ManualKeyboardRefreshScheduler()
        let enablingEngine = try KeyboardModifierEngine(provider: enablingProvider, store: enablingStore,
            bootSessionID: "test")
        let enabling = KeyboardModifierController(engine: enablingEngine,
            scheduleRefreshWork: enablingScheduler.schedule)
        enabling.start()
        defer { enabling.stop() }
        await enabling.waitUntilIdle()
        enablingProvider.disconnectOnRead = 101
        enabling.setSwapEnabled(true, for: keyboard.id)
        await enabling.waitUntilIdle()
        check(enablingEngine.preferences.enabledKeyboardIDs.contains(keyboard.id),
              "Unplugging during the initial enable preserves the requested preference")
        check(enabling.errorMessage == nil && !enabling.hasKeyboards,
              "An initial-enable unplug is silent and hides the vanished keyboard")
        enablingProvider.connected = [reconnected]
        check(enablingScheduler.runNext(), "An initial-enable unplug also schedules recovery")
        await enabling.waitUntilIdle()
        check(enabling.swapsModifiers, "Initial-enable recovery applies to the reconnected keyboard")
        enabling.setSwapEnabled(false, for: keyboard.id)
        await enabling.waitUntilIdle()
        enablingStore.failSave = true
        enabling.setSwapEnabled(true, for: keyboard.id)
        await enabling.waitUntilIdle()
        check(enabling.errorMessage == KeyboardModifierError.cannotSave.localizedDescription,
              "A real settings-save failure is never suppressed as a disconnect")
        enablingStore.failSave = false

        let mixedProvider = FakeKeyboardHID()
        let secondKeyboard = ExternalKeyboard(id: "other", name: "Other Keyboard", vendorID: 1, productID: 4,
            locationID: 5, transport: "USB", hasPointerInterface: false, serviceIDs: [301])
        mixedProvider.connected = [keyboard, secondKeyboard]
        mixedProvider.mappingErrors[101] = .deviceUnavailable
        mixedProvider.mappingErrors[301] = .unsupportedMapping
        let mixedStore = MemoryKeyboardStore()
        var preferences = KeyboardModifierPreferences(bootSessionID: "test")
        preferences.selectedKeyboardID = keyboard.id
        preferences.enabledKeyboardIDs = [keyboard.id, secondKeyboard.id]
        mixedStore.value = preferences
        let mixedEngine = try KeyboardModifierEngine(provider: mixedProvider, store: mixedStore, bootSessionID: "test")
        do {
            try mixedEngine.refresh()
            preconditionFailure("The unsupported mapping must be reported")
        } catch {
            check(error.localizedDescription == KeyboardModifierError.unsupportedMapping.localizedDescription,
                  "One keyboard unplugging never hides a real error from another keyboard")
        }
        return checks
    }
}
