import AppKit
import SwiftUI

/// Presentation is owned by the popover; a delayed device scan cannot reopen old UI.
struct CoffeeCupMenuPresentation {
    let currentSession: () -> Int?
    let show: (NSMenu, NSButton, Int) -> Void

    static let standalone = CoffeeCupMenuPresentation(currentSession: { 0 }, show: { menu, sender, _ in
        menu.popUp(positioning: nil,
                   at: NSPoint(x: sender.bounds.maxX - menu.size.width, y: sender.bounds.minY - 4), in: sender)
    })
}

/// Use AppKit's menu tracking and target/action rather than rebuilding a SwiftUI Menu
/// while device discovery publishes changes. Each action keeps the device it was shown for.
struct CoffeeCupSettingsButton: NSViewRepresentable {
    let caffeinate: CoffeeCupController
    let keyboards: KeyboardModifierController
    let showAbout: () -> Void
    var menuPresentation: CoffeeCupMenuPresentation = .standalone

    func makeCoordinator() -> CoffeeCupSettingsMenu {
        CoffeeCupSettingsMenu(caffeinate: caffeinate, keyboards: keyboards, showAbout: showAbout,
                              presentation: menuPresentation)
    }

    func makeNSView(context: Context) -> FirstClickSettingsButton {
        let button = FirstClickSettingsButton()
        button.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "CoffeeCup settings")
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.setButtonType(.momentaryPushIn)
        button.target = context.coordinator
        button.action = #selector(CoffeeCupSettingsMenu.showMenu(_:))
        button.toolTip = "Settings and app actions"
        button.setAccessibilityLabel("CoffeeCup settings")
        return button
    }

    func updateNSView(_ button: FirstClickSettingsButton, context: Context) {
        context.coordinator.showAbout = showAbout
        context.coordinator.presentation = menuPresentation
    }
}

final class FirstClickSettingsButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class CoffeeCupSettingsMenu: NSObject {
    let caffeinate: CoffeeCupController
    let keyboards: KeyboardModifierController
    var showAbout: () -> Void
    var presentation: CoffeeCupMenuPresentation
    private var menuRequest = 0

    init(caffeinate: CoffeeCupController, keyboards: KeyboardModifierController,
         showAbout: @escaping () -> Void, presentation: CoffeeCupMenuPresentation = .standalone) {
        self.caffeinate = caffeinate
        self.keyboards = keyboards
        self.showAbout = showAbout
        self.presentation = presentation
    }

    @objc func showMenu(_ sender: NSButton) {
        guard let session = presentation.currentSession() else { return }
        menuRequest += 1
        let request = menuRequest
        // Refresh off-main before taking the menu snapshot. The asynchronous completion
        // also lets NSButton finish mouse-up before entering the nested tracking loop.
        keyboards.refresh(invalidateDiscovery: true) { [weak self, weak sender] in
            guard let self, let sender, sender.window?.isVisible == true,
                  self.menuRequest == request, self.presentation.currentSession() == session else { return }
            let menu = self.makeMenu()
            self.presentation.show(menu, sender, session)
        }
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let login = item("Launch at login", action: #selector(toggleLogin(_:)))
        login.state = caffeinate.launchesAtLogin ? .on : .off
        menu.addItem(login)

        if keyboards.hasKeyboards {
            if keyboards.keyboards.count > 1 {
                let deviceMenu = NSMenu(title: "Keyboard")
                deviceMenu.autoenablesItems = false
                for keyboard in keyboards.keyboards {
                    let device = item(keyboard.name, action: #selector(selectKeyboard(_:)))
                    device.representedObject = keyboard.id
                    device.state = keyboard.id == keyboards.selectedKeyboardID ? .on : .off
                    deviceMenu.addItem(device)
                }
                let devices = NSMenuItem(title: "Keyboard", action: nil, keyEquivalent: "")
                devices.submenu = deviceMenu
                menu.addItem(devices)
            }
            let swap = item("Swap Alt / Windows", action: #selector(toggleSwap(_:)))
            swap.state = keyboards.swapsModifiers ? .on : .off
            swap.isEnabled = keyboards.selectedKeyboard != nil
            if let id = keyboards.selectedKeyboardID {
                swap.representedObject = SwapRequest(keyboardID: id, enabled: !keyboards.swapsModifiers)
            }
            swap.toolTip = "For the selected external keyboard in Windows mode only. The built-in keyboard is unchanged."
            menu.addItem(swap)
        }

        menu.addItem(.separator())
        if caffeinate.updateAvailableVersion != nil {
            menu.addItem(item("Download Update…", action: #selector(downloadUpdate(_:))))
        }
        menu.addItem(item("About CoffeeCup", action: #selector(about(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit CoffeeCup", action: #selector(quit(_:))))
        return menu
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        caffeinate.setLaunchAtLogin(sender.state != .on)
    }

    @objc private func selectKeyboard(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        keyboards.selectKeyboard(id)
    }

    @objc private func toggleSwap(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? SwapRequest else { return }
        keyboards.setSwapEnabled(request.enabled, for: request.keyboardID)
    }

    @objc private func downloadUpdate(_ sender: NSMenuItem) { caffeinate.downloadUpdateDMG() }
    @objc private func about(_ sender: NSMenuItem) { showAbout() }
    @objc private func quit(_ sender: NSMenuItem) { NSApp.terminate(nil) }

    private final class SwapRequest: NSObject {
        let keyboardID: String
        let enabled: Bool
        init(keyboardID: String, enabled: Bool) {
            self.keyboardID = keyboardID
            self.enabled = enabled
        }
    }
}
