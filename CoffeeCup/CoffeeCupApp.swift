import AppKit
import Combine
import SwiftUI

@MainActor
final class CoffeeCupAppDelegate: NSObject, NSApplicationDelegate {
    private var presenter: CoffeeCupPopoverController?
    private var statusItem: NSStatusItem?
    private var activityObserver: AnyCancellable?
    private var catModeObserver: AnyCancellable?
    private let startCatMode: () -> Bool

    override init() {
        startCatMode = {
            CatModeController.shared.setActive(true)
            return CatModeController.shared.isActive
        }
        super.init()
    }

    #if COFFEECUP_INTERACTION_TESTS
    init(startCatMode: @escaping () -> Bool) {
        self.startCatMode = startCatMode
        super.init()
    }
    var presenterForTests: CoffeeCupPopoverController? { presenter }
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        CatModeController.shared.restoreFunctionKeyModeAfterUnexpectedQuit()
        let controller = CoffeeCupController.shared
        controller.startWeeklyUpdateChecks()
        DisplayRotationController.shared.refreshDisplays()
        KeyboardModifierController.shared.start()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        guard let button = item.button else { return }
        #if COFFEECUP_INTERACTION_TESTS
        button.toolTip = "CoffeeCup Input Tests"
        #else
        button.toolTip = "CoffeeCup"
        #endif
        let presenter = CoffeeCupPopoverController(button: button, willOpen: {
            KeyboardModifierController.shared.refresh(invalidateDiscovery: true)
            controller.refreshLoginItemStatus()
        }, startCatMode: startCatMode)
        self.presenter = presenter
        let hostingController = NSHostingController(rootView: ContentView(
            showAbout: { [weak presenter] in presenter?.showAbout() },
            requestCatMode: { [weak presenter] in presenter?.requestCatMode() },
            menuPresentation: presenter.menuPresentation
        ).environmentObject(controller))
        hostingController.sizingOptions = [.preferredContentSize]
        presenter.popover.contentViewController = hostingController
        updateStatusIcon(isActive: controller.isActive)

        activityObserver = controller.$isActive.sink { [weak self] in self?.updateStatusIcon(isActive: $0) }
        catModeObserver = CatModeController.shared.$isActive
            .removeDuplicates()
            .sink { [weak presenter] in presenter?.send(.catModeChanged($0)) }
        NotificationCenter.default.addObserver(
            self, selector: #selector(displayConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        presenter?.send(.shutdown)
        activityObserver = nil
        catModeObserver = nil
        CatModeController.shared.stop()
        KeyboardModifierController.shared.stop()
        CoffeeCupController.shared.stop()
    }

    @objc func togglePopover(_ sender: Any?) { presenter?.iconClicked(sender) }

    @objc private func displayConfigurationDidChange() {
        DisplayRotationController.shared.refreshDisplays()
        presenter?.send(.displayChanged)
    }

    private func updateStatusIcon(isActive: Bool) {
        #if COFFEECUP_INTERACTION_TESTS
        let symbol = "t.square"
        #else
        let symbol = isActive ? "cup.and.saucer.fill" : "cup.and.saucer"
        #endif
        guard let image = NSImage(systemSymbolName: symbol,
                                  accessibilityDescription: "CoffeeCup") else { return }
        image.isTemplate = true
        statusItem?.button?.image = image
    }
}

#if !COFFEECUP_INTERACTION_TESTS
@main
struct CoffeeCupApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: CoffeeCupAppDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
#endif
