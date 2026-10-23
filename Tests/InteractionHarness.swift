import AppKit
import SwiftUI

/// An accessory-app harness using the production delegate/popover. The controls in
/// the test window use simulated mappings/rotation; the real popover is explicitly labeled.
@MainActor
final class InteractionHarnessDelegate: NSObject, NSApplicationDelegate {
    // Exercise confirmation/closing without ever installing the real input blocker.
    private let productionDelegate = CoffeeCupAppDelegate(startCatMode: { true })
    private var window: NSWindow?
    private let provider = FakeKeyboardHID()
    private var keyboards: KeyboardModifierController?
    private var runningPopoverTests = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        productionDelegate.applicationDidFinishLaunching(notification)
        #if COFFEECUP_SWIFTUI_INTERACTION_TESTS
        // Keep this fixture AppKit-only: the production popover is the SwiftUI view
        // under test, not another self-sizing NSHostingController window.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 110),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "CoffeeCup Menu Bar Tests"
        let label = NSTextField(labelWithString: "Click the T icon in the menu bar to test CoffeeCup.")
        label.frame = NSRect(x: 16, y: 70, width: 330, height: 22)
        window.contentView?.addSubview(label)
        let quit = NSButton(title: "Quit Test App", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.frame = NSRect(x: 16, y: 20, width: 130, height: 30)
        window.contentView?.addSubview(quit)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        #else
        let engine = try! KeyboardModifierEngine(provider: provider,
            store: MemoryKeyboardStore(), bootSessionID: "interaction-tests")
        let keyboards = KeyboardModifierController(engine: engine)
        self.keyboards = keyboards
        keyboards.start()
        let content = InteractionControls(keyboards: keyboards,
            showPopover: { [weak self] in self?.productionDelegate.togglePopover(nil) },
            showPopoverLater: { [weak self] in
                NSApp.hide(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self?.productionDelegate.togglePopover(nil)
                }
            },
            rapidReopen: { [weak self] in
                NSApp.hide(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    guard let button = self?.productionDelegate.presenterForTests?.statusButtonForTests else { return }
                    for _ in 0..<11 { button.performClick(nil) }
                }
            },
            runPopoverTests: { [weak self] in self?.runPopoverTests() },
            resetCatMode: { [weak self] in self?.productionDelegate.presenterForTests?.send(.catModeChanged(false)) },
            setKeyboardCount: { [weak self] in self?.setKeyboardCount($0) })
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "CoffeeCup Input Tests"
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        #endif
    }

    private func runPopoverTests() {
        guard !runningPopoverTests, let presenter = productionDelegate.presenterForTests, let window else { return }
        runningPopoverTests = true
        UserDefaults.standard.set("Scheduled native popover checks", forKey: "CoffeeCup.nativePopoverTests")
        Task {
            defer { runningPopoverTests = false }
            // Let the launching click and UI automation finish their own focus
            // handoff before the suite measures native activation transitions.
            try? await Task.sleep(for: .seconds(1))
            UserDefaults.standard.set("Running native popover checks", forKey: "CoffeeCup.nativePopoverTests")
            let result: String
            do { result = "PASS: \(try await NativePopoverTests.run(presenter, testWindow: window)) native popover checks" }
            catch { result = "FAIL: \(error)" }
            UserDefaults.standard.set(result, forKey: "CoffeeCup.nativePopoverTests")
            print(result)
        }
    }

    private func setKeyboardCount(_ count: Int) {
        provider.connected = (0..<count).map { index in
            ExternalKeyboard(id: "test-\(index)", name: "Test Keyboard \(index + 1)",
                vendorID: 1, productID: UInt32(index + 1), locationID: UInt64(index + 1),
                transport: "USB", hasPointerInterface: false, serviceIDs: [UInt64(index + 101)])
        }
        keyboards?.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboards?.stop()
        productionDelegate.applicationWillTerminate(notification)
    }
}

private struct InteractionControls: View {
    @ObservedObject var keyboards: KeyboardModifierController
    let showPopover: () -> Void
    let showPopoverLater: () -> Void
    let rapidReopen: () -> Void
    let runPopoverTests: () -> Void
    let resetCatMode: () -> Void
    let setKeyboardCount: (Int) -> Void
    @State private var toggle = false
    @State private var toggleChanges = 0
    @State private var rotation = 0
    @State private var rotationChanges = 0
    @State private var aboutActions = 0
    @State private var modifierEvents: [String] = []
    @State private var modifierMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CoffeeCup Input Tests").font(.headline)
            Button("Open real CoffeeCup popover", action: showPopover)
            Button("Hide test app, reopen popover after 3 seconds", action: showPopoverLater)
            Button("Rapid reopen from background", action: rapidReopen)
            Button("Run popover edge-case tests", action: runPopoverTests)
            Button("Reset simulated Cat Mode", action: resetCatMode)
            Text("The row and rotation below are simulated; they never block input or rotate your monitor.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            CoffeeCupToggleRow(title: "Click target test", isOn: $toggle)
                .onChange(of: toggle) { _ in toggleChanges += 1 }
            Text("Toggle changes: \(toggleChanges)")
            DisplayRotationSelector(currentRotation: rotation) {
                rotation = $0
                rotationChanges += 1
            }
            Text("Rotation: \(rotation) • Changes: \(rotationChanges)")
            HStack {
                Text("Test keyboards")
                ForEach(0...2, id: \.self) { count in
                    Button("\(count)") { setKeyboardCount(count) }
                }
                Spacer()
                CoffeeCupSettingsButton(caffeinate: CoffeeCupController.shared, keyboards: keyboards,
                    showAbout: { aboutActions += 1 }).frame(width: 28, height: 28)
            }
            Text("Mock swap: \(keyboards.swapsModifiers ? "on" : "off") • About: \(aboutActions)")
                .font(.caption)
            Text("Physical modifiers: \(modifierEvents.isEmpty ? "not tested" : modifierEvents.joined(separator: ", "))")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            Button("Quit Input Tests") { NSApp.terminate(nil) }
        }
        .padding(18)
        .frame(width: 300)
        .onAppear {
            // Local to this test app only. Record modifier names, never typed characters,
            // and require neither Accessibility nor Input Monitoring permissions.
            modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                let flags = event.modifierFlags
                let names: [String] = [
                    flags.contains(.command) ? "Command" : nil,
                    flags.contains(.option) ? "Option" : nil,
                    flags.contains(.control) ? "Control" : nil,
                    flags.contains(.shift) ? "Shift" : nil
                ].compactMap { $0 }
                if !names.isEmpty {
                    modifierEvents = Array((modifierEvents + [names.joined(separator: "+")]).suffix(4))
                }
                return event
            }
        }
        .onDisappear {
            if let modifierMonitor { NSEvent.removeMonitor(modifierMonitor) }
            modifierMonitor = nil
        }
    }
}

#if COFFEECUP_SWIFTUI_INTERACTION_TESTS
@main
struct InteractionHarness: App {
    @NSApplicationDelegateAdaptor private var delegate: InteractionHarnessDelegate
    var body: some Scene { Settings { EmptyView() } }
}
#else
@main
enum InteractionHarness {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = InteractionHarnessDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
#endif
