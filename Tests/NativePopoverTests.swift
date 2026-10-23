import AppKit

/// Runs inside the accessory-app harness with real AppKit windows and a fake Cat Mode starter.
/// Events are routed only within this test process; no system input or permissions are used.
@MainActor
enum NativePopoverTests {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func run(_ presenter: CoffeeCupPopoverController, testWindow: NSWindow) async throws -> Int {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw Failure(description: message) }
            checks += 1
        }
        func settle() async throws { try await Task.sleep(for: .milliseconds(100)) }
        func open() async throws {
            presenter.send(.catModeChanged(false))
            if presenter.interaction.isVisible { presenter.send(.outsideInteraction) }
            testWindow.makeKeyAndOrderFront(nil)
            presenter.iconClicked(nil)
            try await settle()
            try check(presenter.popover.isShown && presenter.interaction.phase == .popover, "Opening shows the native popover")
        }
        func mouse(in window: NSWindow?, type: NSEvent.EventType = .leftMouseDown,
                   location: NSPoint = NSPoint(x: 10, y: 10), timestamp: TimeInterval = 0) -> NSEvent {
            let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: timestamp,
                windowNumber: window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            // macOS may represent a remote status item using a virtual window ID
            // that cannot be resolved by a synthesized event. Model its real
            // windowless delivery with screen coordinates instead.
            if let window, event.window == nil {
                return NSEvent.mouseEvent(with: type, location: window.convertPoint(toScreen: location),
                    modifierFlags: [], timestamp: timestamp, windowNumber: 0, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            return event
        }
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53)!
        defer {
            presenter.send(.catModeChanged(false))
            presenter.send(.outsideInteraction)
            testWindow.makeKeyAndOrderFront(nil)
        }

        try await open()
        let popup = presenter.popover.contentViewController!.view.window!
        try check(NSApp.isActive && NSRunningApplication.current.isActive && popup.isKeyWindow,
                  "Opening actually activates the process and makes the popover key")
        try check(presenter.monitorCountForTests == 2, "Mouse/local-key monitoring exists only while open")
        let inside = mouse(in: popup)
        try check(presenter.handleLocalEvent(inside) === inside && presenter.popover.isShown, "Inside clicks pass through and keep the popover open")
        try check(presenter.handleLocalEvent(escape) == nil && !presenter.popover.isShown, "Escape is consumed and closes the native popover")
        try check(presenter.monitorCountForTests == 0, "Closing removes both event monitors")
        try check(testWindow.isKeyWindow, "Explicit dismissal restores the prior same-app window")
        try check(presenter.handleLocalEvent(escape) === escape, "Hidden popover does not consume Escape")

        // No yielding between presses: settled open/close tests miss the native
        // event/activation work queued by a real burst of menu-bar clicks.
        for _ in 0..<11 { presenter.statusButtonForTests!.performClick(nil) }
        try await settle()
        try check(presenter.popover.isShown, "A rapid odd-numbered click burst leaves the popover open")
        let padding = NSPoint(x: popup.contentView!.bounds.midX, y: 5)
        let background = mouse(in: popup, location: popup.contentView!.convert(padding, to: nil))
        presenter.handleGlobalEvent(background, for: presenter.interaction.session)
        try check(presenter.popover.isShown, "A globally delivered blank-area press remains inside after rapid reopening")
        let backgroundScreen = background.window?.convertPoint(toScreen: background.locationInWindow) ?? background.locationInWindow
        let windowlessBackground = mouse(in: nil, location: backgroundScreen)
        try check(presenter.handleLocalEvent(windowlessBackground) === windowlessBackground && presenter.popover.isShown,
                  "A windowless blank-area press passes through without dismissing")
        presenter.send(.escape)

        for clicks in [3, 5, 17] {
            let queuedOutside = mouse(in: testWindow, timestamp: ProcessInfo.processInfo.systemUptime)
            for _ in 0..<clicks { presenter.statusButtonForTests!.performClick(nil) }
            try await settle()
            try check(presenter.popover.isShown && popup.isKeyWindow && NSRunningApplication.current.isActive,
                      "Rapid reopen settles with actual keyboard focus after \(clicks) presses")
            let opening = presenter.interaction.session
            presenter.handleGlobalEvent(queuedOutside, for: opening)
            try check(presenter.popover.isShown, "A queued pre-opening global press cannot close the new popover")
            try check(presenter.handleLocalEvent(queuedOutside) === queuedOutside && presenter.popover.isShown,
                      "A queued local press passes through without affecting the new opening")
            let bounds = popup.contentView!.bounds
            for point in [NSPoint(x: bounds.midX, y: bounds.minY + 5),
                          NSPoint(x: bounds.midX, y: bounds.maxY - 5),
                          NSPoint(x: bounds.minX + 5, y: bounds.midY),
                          NSPoint(x: bounds.maxX - 5, y: bounds.midY)] {
                let blank = mouse(in: popup, location: popup.contentView!.convert(point, to: nil))
                let screenPoint = popup.convertPoint(toScreen: blank.locationInWindow)
                let noWindow = mouse(in: nil, location: screenPoint)
                try check(presenter.handleLocalEvent(blank) === blank && presenter.popover.isShown,
                          "Every padding edge remains inside on local delivery")
                presenter.handleGlobalEvent(noWindow, for: opening)
                try check(presenter.popover.isShown, "Windowless global delivery cannot dismiss padding clicks")
                try check(presenter.handleLocalEvent(noWindow) === noWindow && presenter.popover.isShown,
                          "Windowless local delivery cannot dismiss padding clicks")
            }
            // A recent outside press must still work; this is not a timed debounce.
            presenter.handleGlobalEvent(mouse(in: testWindow, timestamp: ProcessInfo.processInfo.systemUptime), for: opening)
            try check(!presenter.popover.isShown && presenter.monitorCountForTests == 0,
                      "A fresh outside click dismisses immediately after a rapid burst")
        }

        try await open()
        let button = presenter.statusButtonForTests!
        let icon = mouse(in: button.window, location: button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil))
        let iconOpening = presenter.interaction.session
        try check(presenter.handleLocalEvent(icon) === icon && presenter.popover.isShown && presenter.interaction.session == iconOpening,
                  "The local monitor leaves the popover unchanged and forwards the icon press to its sole native owner")
        button.performClick(nil)
        try check(!presenter.popover.isShown && presenter.interaction.phase == .hidden, "Icon closes independently of key-window state")
        try await settle()
        try check(!presenter.popover.isShown, "No deferred focus/show reopens after icon dismissal")

        // Reproduce the observed macOS sequence: global mouse-down first, then
        // the forwarded NSStatusBarButton action. Neither callback can be omitted.
        try await open()
        let opening = presenter.interaction.session
        presenter.handleGlobalEvent(icon, for: opening)
        try check(presenter.popover.isShown && presenter.interaction.session == opening,
                  "A global icon press is not an outside dismissal")
        button.performClick(nil)
        try await settle()
        try check(!presenter.popover.isShown && presenter.interaction.session == opening + 1,
                  "Global press plus native button action closes once without reopening")

        // The remotely hosted status item has clickable padding around its button
        // (38x33 host vs. 22x27 button on macOS 27). The global press retains the
        // physical position, while the forwarded button event is centered. Test
        // both deliveries so narrowing hit-testing to button.bounds cannot regress.
        for edge in 0..<4 {
            try await open()
            let frame = button.window!.frame
            let points = [NSPoint(x: frame.minX + 1, y: frame.midY),
                          NSPoint(x: frame.maxX - 1, y: frame.midY),
                          NSPoint(x: frame.midX, y: frame.minY + 1),
                          NSPoint(x: frame.midX, y: frame.maxY - 1)]
            let session = presenter.interaction.session
            presenter.handleGlobalEvent(mouse(in: nil, location: points[edge]), for: session)
            try check(presenter.popover.isShown && presenter.interaction.session == session,
                      "The full status-item host, including capsule padding, is not an outside click")
            try check(presenter.handleLocalEvent(icon) === icon && presenter.interaction.session == session,
                      "Forwarded delivery after a capsule-edge press remains owned by the native button")
            button.performClick(nil)
            try check(!presenter.popover.isShown && presenter.interaction.session == session + 1,
                      "A capsule-edge press followed by its native action closes once without reopening")
        }

        for side in [-1.0, 1.0] {
            try await open()
            let frame = button.window!.frame
            let point = NSPoint(x: side < 0 ? frame.minX - 1 : frame.maxX + 1, y: frame.midY)
            presenter.handleGlobalEvent(mouse(in: nil, location: point), for: presenter.interaction.session)
            try check(!presenter.popover.isShown && presenter.monitorCountForTests == 0,
                      "Clicks immediately beside the status-item host still dismiss, without a menu-bar-wide exclusion")
        }

        try await open()
        let proxy = NSWindow(contentRect: button.window!.frame, styleMask: .borderless, backing: .buffered, defer: false)
        let screenPoint = button.window!.convertPoint(toScreen: button.convert(
            NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil))
        let forwarded = mouse(in: proxy, location: proxy.convertPoint(fromScreen: screenPoint))
        presenter.handleGlobalEvent(forwarded, for: presenter.interaction.session)
        try check(presenter.popover.isShown, "Icon hit-testing uses screen coordinates, not originating-window identity")
        button.performClick(nil)
        try check(!presenter.popover.isShown, "A forwarded icon press still has only one toggle owner")
        proxy.close()

        try await open()
        presenter.handleGlobalEvent(mouse(in: testWindow), for: presenter.interaction.session)
        try check(!presenter.popover.isShown, "A genuine global outside click still dismisses immediately")

        for type in [NSEvent.EventType.rightMouseDown, .otherMouseDown] {
            try await open()
            let press = mouse(in: button.window, type: type,
                location: button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil))
            presenter.handleGlobalEvent(press, for: presenter.interaction.session)
            try check(!presenter.popover.isShown, "Only the native left-click action bypasses outside dismissal")
        }

        for type in [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown] {
            try await open()
            let outside = mouse(in: testWindow, type: type)
            try check(presenter.handleLocalEvent(outside) === outside && !presenter.popover.isShown,
                      "First outside \(type) reaches the original target unchanged")
        }

        try await open()
        let old = presenter.interaction.session
        presenter.send(.displayChanged)
        presenter.send(.outsideInteraction)
        try await open()
        presenter.send(.outsideInteraction, for: old)
        presenter.send(.applicationResigned, for: old)
        presenter.send(.reanchorReady(old))
        try await Task.sleep(for: .milliseconds(650))
        try check(presenter.popover.isShown, "Old outside/focus/reanchor callbacks cannot close or reopen a later session")
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        try await settle()
        try check(presenter.popover.isShown && NSRunningApplication.current.isActive,
                  "A stale focus-loss notification cannot close an active reopening")
        NSApp.hide(nil)
        try await settle()
        try check(!presenter.popover.isShown && presenter.monitorCountForTests == 0,
                  "Actual app deactivation closes and removes monitors without reopening")

        // Run the real nested NSMenu tracking loop, not just state-machine events.
        for ending in [PopoverInteraction.Event.escape, .iconClicked, .outsideInteraction] {
            try await open()
            let sender = NSButton(frame: NSRect(x: 10, y: 10, width: 28, height: 28))
            presenter.popover.contentViewController!.view.addSubview(sender)
            let menu = NSMenu()
            menu.addItem(withTitle: "Test action", action: nil, keyEquivalent: "")
            var tracked = false
            let timer = Timer(timeInterval: 0.05, repeats: false) { _ in MainActor.assumeIsolated {
                tracked = presenter.interaction.phase == .settings
                presenter.send(ending)
            } }
            RunLoop.main.add(timer, forMode: .eventTracking)
            RunLoop.main.add(timer, forMode: .default)
            presenter.menuPresentation.show(menu, sender, presenter.interaction.session)
            timer.invalidate()
            sender.removeFromSuperview()
            try check(tracked, "The settings menu participates in the presentation state")
            try check(presenter.popover.isShown == (ending == .escape), "Native menu dismissal follows the one-level/close-all contract")
            try await settle()
            try check(presenter.interaction.phase == (ending == .escape ? .popover : .hidden),
                      "Returning from a cancelled menu cannot reopen or refocus a closed popover")
        }

        // A device refresh finishing after close/reopen must not show an old gear menu.
        let engine = try KeyboardModifierEngine(provider: FakeKeyboardHID(), store: MemoryKeyboardStore(), bootSessionID: "popover-tests")
        let keyboards = KeyboardModifierController(engine: engine)
        keyboards.start()
        defer { keyboards.stop() }
        await keyboards.waitUntilIdle()
        try await open()
        let sender = NSButton(frame: NSRect(x: 10, y: 10, width: 28, height: 28))
        presenter.popover.contentViewController!.view.addSubview(sender)
        var lateMenus = 0
        let coordinator = CoffeeCupSettingsMenu(caffeinate: CoffeeCupController.shared, keyboards: keyboards, showAbout: {},
            presentation: CoffeeCupMenuPresentation(currentSession: presenter.menuPresentation.currentSession,
                show: { _, _, _ in lateMenus += 1 }))
        coordinator.showMenu(sender)
        presenter.iconClicked(nil)
        presenter.iconClicked(nil)
        await keyboards.waitUntilIdle()
        try check(lateMenus == 0, "An old keyboard scan cannot open a settings menu after close/reopen")
        coordinator.showMenu(sender)
        coordinator.showMenu(sender)
        await keyboards.waitUntilIdle()
        try check(lateMenus == 1, "Repeated gear requests collapse to one current menu")
        sender.removeFromSuperview()

        // Exercise actual sheet teardown and completion callbacks, including a late confirm.
        try await open()
        presenter.requestCatMode()
        try await settle()
        let cancelled = popup.attachedSheet!
        try check(presenter.interaction.phase == .confirmation, "Cat Mode uses a native child confirmation")
        try check(presenter.handleLocalEvent(escape) == nil && presenter.popover.isShown, "First Escape cancels only the sheet")
        try await settle()
        try check(popup.attachedSheet == nil && presenter.interaction.phase == .popover && popup.isKeyWindow,
                  "Cancelled sheet releases and returns keyboard focus to the popover")
        popup.endSheet(cancelled, returnCode: .alertSecondButtonReturn)
        try await settle()
        try check(!presenter.interaction.catModeActive, "A late confirmation cannot start Cat Mode after cancellation")

        presenter.requestCatMode()
        try await settle()
        presenter.iconClicked(nil)
        try await settle()
        try check(!presenter.popover.isShown && popup.attachedSheet == nil && !presenter.interaction.catModeActive,
                  "Icon cancels the sheet and closes everything without enabling Cat Mode")

        try await open()
        presenter.requestCatMode()
        try await settle()
        _ = presenter.handleLocalEvent(mouse(in: testWindow))
        try await settle()
        try check(!presenter.popover.isShown && !presenter.interaction.catModeActive && popup.attachedSheet == nil,
                  "Outside click cancels Cat Mode confirmation and closes everything")

        try await open()
        presenter.requestCatMode()
        try await settle()
        popup.endSheet(popup.attachedSheet!, returnCode: .alertSecondButtonReturn)
        try await settle()
        try check(presenter.interaction.catModeActive && !presenter.popover.isShown, "Successful simulated Cat Mode immediately hides the popover")
        presenter.iconClicked(nil)
        try check(!presenter.popover.isShown, "Active Cat Mode does not open on icon action")
        presenter.send(.catModeChanged(false))
        try check(!presenter.popover.isShown, "Unlocking remains closed")

        for _ in 0..<10 {
            try await open()
            presenter.iconClicked(nil)
            try check(!presenter.popover.isShown && presenter.monitorCountForTests == 0, "Repeated opening/closing cannot leave a stuck window or monitor")
        }
        return checks
    }
}
