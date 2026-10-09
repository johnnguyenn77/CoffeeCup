import AppKit
import Combine
import SwiftUI

@MainActor
final class CoffeeCupAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var activityObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        CatModeController.shared.restoreFunctionKeyModeAfterUnexpectedQuit()

        let controller = CoffeeCupController.shared
        controller.startWeeklyUpdateChecks()
        DisplayRotationController.shared.refreshDisplays()

        let hostingController = NSHostingController(
            rootView: ContentView().environmentObject(controller)
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        activityObserver = nil
        popover.close()
        CatModeController.shared.stop()
        CoffeeCupController.shared.stop()
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.state = .off
    }

    @objc private func togglePopover(_ sender: Any?) {
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
            popover.contentViewController?.view.window?.makeKey()
            button.state = .on
        }
    }

    @objc private func displayConfigurationDidChange() {
        DisplayRotationController.shared.refreshDisplays()
        guard popover.isShown else { return }
        schedulePopoverReanchor(after: 0.15)
        schedulePopoverReanchor(after: 0.6)
    }

    private func schedulePopoverReanchor(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.reanchorPopover()
        }
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

@main
struct CoffeeCupApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: CoffeeCupAppDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
