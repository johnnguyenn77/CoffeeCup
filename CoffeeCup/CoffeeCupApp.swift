import AppKit
import Combine
import SwiftUI

@MainActor
final class CoffeeCupAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var activityObserver: AnyCancellable?
    private var catModeObserver: AnyCancellable?
    private var trackingMenus = Set<ObjectIdentifier>()
    private var reanchorWork: [DispatchWorkItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        CatModeController.shared.restoreFunctionKeyModeAfterUnexpectedQuit()

        let controller = CoffeeCupController.shared
        controller.startWeeklyUpdateChecks()
        DisplayRotationController.shared.refreshDisplays()
        KeyboardModifierController.shared.start()

        let hostingController = NSHostingController(
            rootView: ContentView(showAbout: { [weak self] in
                self?.showAbout()
            }).environmentObject(controller)
        )
        hostingController.sizingOptions = [.preferredContentSize]

        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        item.button?.toolTip = "CoffeeCup"
        statusItem = item
        updateStatusIcon(isActive: controller.isActive)

        activityObserver = controller.$isActive
            .sink { [weak self] isActive in
                self?.updateStatusIcon(isActive: isActive)
            }

        catModeObserver = CatModeController.shared.$isActive
            .removeDuplicates()
            .filter { $0 }
            // Let the confirmation alert dismiss before closing its containing popover.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard CatModeController.shared.isActive else { return }
                self?.popover.performClose(nil)
            }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(focusPopover),
            name: NSApplication.didBecomeActiveNotification, object: NSApp
        )
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(menuTrackingChanged(_:)), name: name, object: nil
            )
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self, name: NSApplication.didBecomeActiveNotification, object: NSApp
        )
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            NotificationCenter.default.removeObserver(self, name: name, object: nil)
        }
        trackingMenus.removeAll()
        cancelPopoverReanchors()
        activityObserver = nil
        catModeObserver = nil
        popover.close()
        CatModeController.shared.stop()
        KeyboardModifierController.shared.stop()
        CoffeeCupController.shared.stop()
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.state = .off
        cancelPopoverReanchors()
    }

    func popoverDidShow(_ notification: Notification) {
        focusPopover()
    }

    @objc private func focusPopover() {
        guard popover.isShown, NSApp.isActive, trackingMenus.isEmpty,
              let window = popover.contentViewController?.view.window,
              window.attachedSheet == nil, !window.isKeyWindow else { return }
        // Reasserting key status while a menu or confirmation is tracking can dismiss
        // that UI before its mouse-up/action arrives. Only focus when it is actually needed.
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func menuTrackingChanged(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        if notification.name == NSMenu.didBeginTrackingNotification {
            trackingMenus.insert(ObjectIdentifier(menu))
        } else {
            trackingMenus.remove(ObjectIdentifier(menu))
        }
    }

    private func showAbout() {
        popover.performClose(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            focusPopover()
            button.state = .on
        }
    }

    @objc private func displayConfigurationDidChange() {
        DisplayRotationController.shared.refreshDisplays()
        cancelPopoverReanchors()
        guard popover.isShown else { return }
        schedulePopoverReanchor(after: 0.15)
        schedulePopoverReanchor(after: 0.6)
    }

    private func schedulePopoverReanchor(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            self?.reanchorPopover()
        }
        reanchorWork.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPopoverReanchors() {
        reanchorWork.forEach { $0.cancel() }
        reanchorWork.removeAll()
    }

    private func reanchorPopover() {
        guard popover.isShown,
              let button = statusItem?.button,
              button.window != nil else { return }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func updateStatusIcon(isActive: Bool) {
        let symbolName = isActive ? "cup.and.saucer.fill" : "cup.and.saucer"
        guard let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "CoffeeCup"
        ) else { return }

        image.isTemplate = true
        statusItem?.button?.image = image
    }
}

#if !COFFEECUP_INTERACTION_TESTS
@main
struct CoffeeCupApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: CoffeeCupAppDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
#endif
