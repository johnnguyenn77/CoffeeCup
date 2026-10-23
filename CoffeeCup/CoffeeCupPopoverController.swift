import AppKit

/// Owns the popover and its child UI. Automatic AppKit dismissal is disabled so
/// a click has one owner, including when the status button is clicked again.
@MainActor
final class CoffeeCupPopoverController: NSObject, NSPopoverDelegate {
    let popover = NSPopover()
    private(set) var interaction = PopoverInteraction()
    private weak var button: NSStatusBarButton?
    private let willOpen: () -> Void
    private let startCatMode: () -> Bool
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var focusWork: DispatchWorkItem?
    private var deactivationWork: DispatchWorkItem?
    private var reanchorWork: [DispatchWorkItem] = []
    private var menu: NSMenu?
    private var confirmation: (alert: NSAlert, session: Int)?
    private var previousApplication: NSRunningApplication?
    private weak var previousWindow: NSWindow?
    private var openedAt: TimeInterval = 0
    #if COFFEECUP_INTERACTION_TESTS
    private var showCount = 0
    private var closeCount = 0
    private var testEvents: [[String: Any]] = []
    var statusButtonForTests: NSStatusBarButton? { button }
    var monitorCountForTests: Int { (localMonitor == nil ? 0 : 1) + (globalMonitor == nil ? 0 : 1) }
    #endif

    init(button: NSStatusBarButton, willOpen: @escaping () -> Void,
         startCatMode: @escaping () -> Bool) {
        self.button = button
        self.willOpen = willOpen
        self.startCatMode = startCatMode
        super.init()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self
        button.target = self
        button.action = #selector(iconClicked(_:))
        button.sendAction(on: .leftMouseDown)
    }

    var menuPresentation: CoffeeCupMenuPresentation {
        CoffeeCupMenuPresentation(currentSession: { [weak self] in
            self?.interaction.menuRequestSession
        }, show: { [weak self] menu, sender, session in
            self?.showMenu(menu, from: sender, session: session)
        })
    }

    @objc func iconClicked(_ sender: Any?) {
        #if COFFEECUP_INTERACTION_TESTS
        if let event = NSApp.currentEvent,
           [.leftMouseDown, .leftMouseUp].contains(event.type) {
            recordMouseForTests(event, source: "button")
        }
        #endif
        recordTestState("button action")
        send(.iconClicked)
    }
    func requestCatMode() { send(.requestConfirmation) }
    func showAbout() { send(.about) }

    func send(_ event: PopoverInteraction.Event) {
        let effects = interaction.handle(event)
        let session = interaction.session
        for effect in effects {
            // A synchronous AppKit callback can end a session during presentation.
            guard interaction.session == session else { break }
            perform(effect)
        }
        recordTestState(String(describing: event))
    }

    func popoverDidClose(_ notification: Notification) {
        #if COFFEECUP_INTERACTION_TESTS
        closeCount += 1
        #endif
        send(.windowClosed)
    }

    func popoverDidShow(_ notification: Notification) {
        #if COFFEECUP_INTERACTION_TESTS
        showCount += 1
        #endif
        // Showing/repositioning is not an instruction to activate the app.
        recordTestState("didShow")
    }

    private func perform(_ effect: PopoverInteraction.Effect) {
        switch effect {
        case .rememberFocus:
            let application = NSWorkspace.shared.frontmostApplication
            previousApplication = application?.processIdentifier == ProcessInfo.processInfo.processIdentifier
                ? nil : application
            previousWindow = NSApp.keyWindow
        case .installMonitors: installMonitors()
        case .show:
            guard let button, button.window != nil else { send(.windowClosed); return }
            willOpen()
            openedAt = ProcessInfo.processInfo.systemUptime
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            guard popover.isShown else { send(.windowClosed); return }
            button.state = .on
        case .activate:
            guard interaction.isVisible else { return }
            // This is only emitted for a deliberate icon click, never an app/device notification.
            if #available(macOS 14.0, *), NSApp.isActive {
                // Reopening while still active cancels the previous close's
                // pending activation yield before requesting focus again.
                NSApp.activate()
            }
            NSApp.activate(ignoringOtherApps: true)
        case .focus: focusWindow()
        case .deferFocus(let session):
            let work = DispatchWorkItem { [weak self] in self?.send(.activationCompleted(session)) }
            focusWork = work
            DispatchQueue.main.async(execute: work)
        case .removeMonitors: removeMonitors()
        case .cancelDeferredWork:
            focusWork?.cancel()
            focusWork = nil
            deactivationWork?.cancel()
            deactivationWork = nil
            reanchorWork.forEach { $0.cancel() }
            reanchorWork.removeAll()
        case .dismissMenu:
            let current = menu
            menu = nil
            current?.cancelTrackingWithoutAnimation()
        case .dismissConfirmation: dismissConfirmation()
        case .hide:
            button?.state = .off
            popover.close()
        case .restoreFocus: restoreFocus()
        case .forgetFocus:
            previousApplication = nil
            previousWindow = nil
        case .presentConfirmation(let session): presentConfirmation(session: session)
        case .startCatMode:
            if startCatMode() { send(.catModeChanged(true)) }
            else { focusWindow() }
        case .scheduleReanchor(let session):
            // Coalesce display bursts. Both callbacks are bound to this opening.
            reanchorWork.forEach { $0.cancel() }
            reanchorWork.removeAll()
            for delay in [0.15, 0.6] {
                let work = DispatchWorkItem { [weak self] in self?.send(.reanchorReady(session)) }
                reanchorWork.append(work)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            }
        case .reanchor:
            guard interaction.isVisible, popover.isShown else { return }
            guard let button, button.window?.screen != nil else { send(.windowClosed); return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        case .showAbout:
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
        case .terminate: NSApp.terminate(nil)
        }
    }

    private func focusWindow() {
        guard interaction.phase == .popover, popover.isShown, NSApp.isActive,
              let window = popover.contentViewController?.view.window,
              window.attachedSheet == nil else { return }
        if let panel = window as? NSPanel { panel.becomesKeyOnlyIfNeeded = false }
        if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
        if window.isKeyWindow { send(.focusAcquired(interaction.session)) }
    }

    private func restoreFocus() {
        let application = previousApplication
        let window = previousWindow
        previousApplication = nil
        previousWindow = nil
        if let application, !application.isTerminated {
            if #available(macOS 14.0, *) { NSApp.yieldActivation(to: application) }
            application.activate(options: [])
        } else if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func showMenu(_ menu: NSMenu, from sender: NSButton, session: Int) {
        guard interaction.menuRequestSession == session, popover.isShown,
              sender.window === popover.contentViewController?.view.window else { return }
        self.menu = menu
        send(.menuOpened(session))
        defer {
            if self.menu === menu { self.menu = nil }
            send(.menuClosed(session))
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: sender.bounds.maxX - menu.size.width, y: sender.bounds.minY - 4), in: sender)
    }

    private func presentConfirmation(session: Int) {
        guard let window = popover.contentViewController?.view.window, popover.isShown else {
            send(.windowClosed)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Turn On Cat Mode?"
        alert.informativeText = "Cat Mode blocks keyboard and pointer input, including the trackpad and external mouse. Exit with Control–Option–Command–Escape."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        let confirm = alert.addButton(withTitle: "Turn On Cat Mode")
        confirm.hasDestructiveAction = true
        confirm.keyEquivalent = "\r"
        confirmation = (alert, session)
        alert.beginSheetModal(for: window) { [weak self, weak alert] response in
            guard let self, let alert, self.confirmation?.alert === alert else { return }
            self.confirmation = nil
            self.send(.confirmationCompleted(session, response == .alertSecondButtonReturn))
        }
    }

    private func dismissConfirmation() {
        guard let current = confirmation else { return }
        confirmation = nil // Ignore the completion of a cancelled/obsolete sheet.
        current.alert.window.sheetParent?.endSheet(current.alert.window, returnCode: .cancel)
        current.alert.window.orderOut(nil)
    }

    /// The native status button owns icon presses; monitors only dismiss outside UI.
    /// Keeping target/action as the sole toggle owner also handles forwarded presses.
    func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        #if COFFEECUP_INTERACTION_TESTS
        if event.type != .keyDown { recordMouseForTests(event, source: "local") }
        #endif
        guard interaction.isVisible else { return event }
        if event.type == .keyDown {
            guard event.keyCode == 53 else { return event }
            send(.escape)
            return nil
        }
        guard !predatesOpening(event) else { return event }
        if isPresentationEvent(event) { return event }
        if isStatusButtonEvent(event) {
            if event.type == .leftMouseDown {
                return event // Let the native button toggle exactly once.
            }
            send(.outsideInteraction)
            return event
        }
        let window = event.window
        // NSMenu owns its tracking events. Other app-local windows still dismiss the popover.
        if interaction.phase == .settings, window == nil || window?.level == .popUpMenu { return event }
        send(.outsideInteraction)
        return event
    }

    private func isStatusButtonEvent(_ event: NSEvent) -> Bool {
        guard let window = button?.window else { return false }
        // The status-item host includes interactive capsule padding outside the
        // button's bounds. Remote menu bars report the physical press globally,
        // then forward a centered button event with a different window/timestamp.
        // Excluding that padding closes here and reopens on the native action.
        return window.frame.contains(screenLocation(of: event))
    }

    private func screenLocation(of event: NSEvent) -> NSPoint {
        // With no associated NSWindow, AppKit reports mouse locations in screen
        // coordinates. Use this event's location, not the pointer's later position.
        event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    }

    private func isPresentationEvent(_ event: NSEvent) -> Bool {
        let windows = [popover.contentViewController?.view.window, confirmation?.alert.window].compactMap { $0 }
        if let target = event.window {
            // A sheet or another child window may receive the click for its parent.
            var ancestor: NSWindow? = target
            while let current = ancestor {
                if windows.contains(where: { $0 === current }) { return true }
                ancestor = current.parent ?? current.sheetParent
            }
            return false // A different known window remains a genuine outside click.
        }
        let location = screenLocation(of: event)
        return windows.contains { $0.isVisible && $0.frame.contains(location) }
    }

    private func predatesOpening(_ event: NSEvent) -> Bool {
        // A newly installed monitor can receive input already queued before it
        // existed. Such a press belongs to the old UI, not this opening. Zero
        // timestamps (some synthesized/accessibility events) carry no age data.
        event.timestamp > 0 && event.timestamp < openedAt
    }

    func handleGlobalEvent(_ event: NSEvent, for session: Int) {
        guard interaction.session == session, interaction.isVisible else { return }
        #if COFFEECUP_INTERACTION_TESTS
        recordMouseForTests(event, source: "global")
        #endif
        guard !predatesOpening(event), !isPresentationEvent(event) else { return }
        // macOS can deliver the menu-bar press globally before forwarding the
        // button action. Closing here would make that action reopen the popover.
        if event.type == .leftMouseDown, isStatusButtonEvent(event) { return }
        send(.outsideInteraction, for: session)
    }

    private func installMonitors() {
        guard localMonitor == nil else { return }
        let session = interaction.session
        let mouse: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mouse.union(.keyDown)) { [weak self] event in
            var result: NSEvent? = event
            MainActor.assumeIsolated {
                guard let self, self.interaction.session == session else { return }
                result = self.handleLocalEvent(event)
            }
            return result
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouse) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleGlobalEvent(event, for: session)
            }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated {
            guard let self else { return }
            self.send(.activationCompleted(session), for: session)
        } })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.checkDeactivation(for: session) } })
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in MainActor.assumeIsolated {
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.checkDeactivation(for: session)
        } })
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.send(.spaceChanged, for: session) } })
    }

    private func checkDeactivation(for session: Int) {
        guard interaction.session == session, interaction.isVisible else { return }
        deactivationWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.interaction.session == session, self.interaction.isVisible else { return }
            self.deactivationWork = nil
            // Rapid status-item tracking can deliver a previous transition's
            // notification after reopening. Check settled native activation,
            // rather than dismissing solely because a notification arrived.
            guard !NSRunningApplication.current.isActive,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                self.recordTestState("ignored stale deactivation")
                return
            }
            self.send(.applicationResigned, for: session)
        }
        deactivationWork = work
        DispatchQueue.main.async(execute: work)
    }

    private func removeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
    }

    func send(_ event: PopoverInteraction.Event, for session: Int) {
        guard interaction.session == session else { return }
        send(event)
    }

    private func recordTestState(_ event: String) {
        #if COFFEECUP_INTERACTION_TESTS
        let window = popover.contentViewController?.view.window
        let state: [String: Any] = [
            "event": event, "phase": String(describing: interaction.phase), "session": interaction.session,
            "time": ProcessInfo.processInfo.systemUptime,
            "currentEvent": NSApp.currentEvent.map { String(describing: $0.type) } ?? "none",
            "currentEventNumber": NSApp.currentEvent.flatMap {
                [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown].contains($0.type) ? $0.eventNumber : nil
            } ?? -1,
            "shown": popover.isShown, "active": NSApp.isActive, "key": window?.isKeyWindow == true,
            "runningApplicationActive": NSRunningApplication.current.isActive,
            "frontmost": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none",
            "showCount": showCount, "closeCount": closeCount, "catModeActive": interaction.catModeActive,
            "monitorCount": (localMonitor == nil ? 0 : 1) + (globalMonitor == nil ? 0 : 1)
        ]
        testEvents.append(state)
        testEvents = Array(testEvents.suffix(160))
        UserDefaults.standard.set(state, forKey: "CoffeeCup.popoverTestState")
        UserDefaults.standard.set(testEvents, forKey: "CoffeeCup.popoverTestEvents")
        UserDefaults.standard.synchronize()
        #endif
    }

    #if COFFEECUP_INTERACTION_TESTS
    private func recordMouseForTests(_ event: NSEvent, source: String) {
        let buttonFrame = button.flatMap { button in
            button.window?.convertToScreen(button.convert(button.bounds, to: nil))
        } ?? .zero
        let popupFrame = popover.contentViewController?.view.window?.frame ?? .zero
        let screens = NSScreen.screens.map { NSStringFromRect($0.frame) }.joined(separator: "; ")
        recordTestState("\(source) \(event.type) event=\(event.eventNumber) timestamp=\(event.timestamp) window=\(event.windowNumber) knownWindow=\(event.window != nil) buttonWindow=\(button?.window?.windowNumber ?? -1) hitsIcon=\(isStatusButtonEvent(event)) inside=\(isPresentationEvent(event)) old=\(predatesOpening(event)) location=\(NSStringFromPoint(event.locationInWindow)) screenLocation=\(NSStringFromPoint(screenLocation(of: event))) pointer=\(NSStringFromPoint(NSEvent.mouseLocation)) buttonFrame=\(NSStringFromRect(buttonFrame)) buttonWindowFrame=\(NSStringFromRect(button?.window?.frame ?? .zero)) popupFrame=\(NSStringFromRect(popupFrame)) screens=\(screens)")
    }
    #endif
}
