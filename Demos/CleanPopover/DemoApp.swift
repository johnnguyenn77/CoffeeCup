import AppKit
import Combine
import SwiftUI

@MainActor
final class CleanPopoverDemoDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let state = CleanPopoverDemoState()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var controlsWindow: NSWindow?
    private var catModeObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: "CoffeeCup layout demo")
        item.button?.image?.isTemplate = true
        item.button?.title = " Demo"
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.toolTip = "CoffeeCup — clean layout demo (simulated)"
        statusItem = item

        let hosting = NSHostingController(rootView: CleanPopoverDemoView(state: state,
            showControls: { [weak self] in self?.showControls() },
            showAbout: { [weak self] in self?.showAbout() }))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self

        catModeObserver = state.$catModeActive
            .removeDuplicates()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.state.catModeActive else { return }
                self.popover.performClose(nil)
                self.showControls()
            }

        showControls()
        DispatchQueue.main.async { [weak self] in self?.showPopover() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        catModeObserver = nil
        popover.close()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    func popoverDidClose(_ notification: Notification) { statusItem?.button?.state = .off }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem?.button, button.window != nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        button.state = .on
    }

    private func showControls() {
        if controlsWindow == nil {
            let hosting = NSHostingController(rootView: CleanPopoverDemoControls(state: state,
                showPopover: { [weak self] in self?.showPopover() }))
            hosting.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = "CoffeeCup — Layout Demo"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            controlsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        controlsWindow?.makeKeyAndOrderFront(nil)
    }

    private func showAbout() {
        popover.performClose(nil)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "CoffeeCup",
            .applicationVersion: "1.0.9",
            .version: "Layout demo · simulated controls"
        ])
    }
}

@main
enum CleanPopoverDemoApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = CleanPopoverDemoDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
