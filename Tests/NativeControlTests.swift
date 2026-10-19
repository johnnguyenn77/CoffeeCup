import AppKit

@MainActor
enum NativeControlTests {
    static func run() async throws -> Int {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        check(FirstClickSettingsButton().acceptsFirstMouse(for: nil), "The gear accepts the first inactive-window click")
        check(ClickThroughSwitch().acceptsFirstMouse(for: nil), "Switches accept the first inactive-window click")

        let provider = FakeKeyboardHID()
        let engine = try KeyboardModifierEngine(provider: provider, store: MemoryKeyboardStore(), bootSessionID: "test")
        let controller = KeyboardModifierController(engine: engine)
        controller.start()
        defer { controller.stop() }
        await controller.waitUntilIdle()
        let menu = CoffeeCupSettingsMenu(caffeinate: CoffeeCupController.shared, keyboards: controller, showAbout: {})
        let empty = menu.makeMenu()
        check(empty.item(withTitle: "Swap Alt / Windows") == nil, "No swap item without an external keyboard")
        check(empty.item(withTitle: "Keyboard") == nil, "No empty device submenu")
        check(empty.item(withTitle: "Launch at login") != nil, "Login remains reachable without peripherals")
        check(empty.item(withTitle: "About CoffeeCup") != nil && empty.item(withTitle: "Quit CoffeeCup") != nil,
              "About and Quit remain native menu actions")

        let keyboard = ExternalKeyboard(id: "one", name: "Keyboard One", vendorID: 1, productID: 1,
            locationID: 1, transport: "USB", hasPointerInterface: false, serviceIDs: [101])
        let second = ExternalKeyboard(id: "two", name: "Keyboard Two", vendorID: 1, productID: 2,
            locationID: 2, transport: "USB", hasPointerInterface: false, serviceIDs: [102])
        var mouse = ExternalKeyboard(id: "mouse", name: "Razer Basilisk V3 Pro", vendorID: 2, productID: 3,
            locationID: 3, transport: "USB", hasPointerInterface: true, serviceIDs: [103])
        mouse.isSelectable = false
        provider.connected = [mouse]
        controller.refresh()
        await controller.waitUntilIdle()
        check(menu.makeMenu().item(withTitle: "Swap Alt / Windows") == nil, "A mouse alone never creates keyboard settings")
        provider.connected = [keyboard, mouse]
        controller.refresh()
        await controller.waitUntilIdle()
        let single = menu.makeMenu()
        check(single.item(withTitle: "Keyboard") == nil, "One keyboard needs no redundant device picker")
        check(single.item(withTitle: "Swap Alt / Windows")?.isEnabled == true, "The single-keyboard swap action is enabled")
        controller.setSwapEnabled(true, for: keyboard.id)
        await controller.waitUntilIdle()
        check(menu.makeMenu().item(withTitle: "Swap Alt / Windows")?.state == .on, "The native checkmark reflects a verified swap")
        provider.connected = [keyboard, second, mouse]
        controller.refresh()
        await controller.waitUntilIdle()
        let multiple = menu.makeMenu()
        let choices = multiple.item(withTitle: "Keyboard")?.submenu
        check(choices?.items.map(\.title) == [keyboard.name, second.name], "The keyboard submenu never includes mouse helpers")
        check(choices?.item(withTitle: keyboard.name)?.state == .on, "The selected keyboard has a native checkmark")
        controller.selectKeyboard(second.id)
        await controller.waitUntilIdle()
        check(choices?.item(withTitle: keyboard.name)?.state == .on,
              "An already-open menu stays stable during controller updates")
        check(menu.makeMenu().item(withTitle: "Keyboard")?.submenu?.item(withTitle: second.name)?.state == .on,
              "The next menu opening reads the current device selection")
        check(provider.writes.allSatisfy { $0 == 101 }, "Menu construction and selection do not map the mouse or another keyboard")
        return checks
    }
}
