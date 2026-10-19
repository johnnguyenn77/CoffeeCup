import AppKit
import SwiftUI

/// An accessory-app harness using the production delegate/popover. The controls in
/// the test window use simulated mappings/rotation; the real popover is explicitly labeled.
@MainActor
final class InteractionHarnessDelegate: NSObject, NSApplicationDelegate {
    private let productionDelegate = CoffeeCupAppDelegate()
    private var window: NSWindow?
    private let provider = FakeKeyboardHID()
    private var keyboards: KeyboardModifierController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        productionDelegate.applicationDidFinishLaunching(notification)
        let engine = try! KeyboardModifierEngine(provider: provider,
            store: MemoryKeyboardStore(), bootSessionID: "interaction-tests")
        let keyboards = KeyboardModifierController(engine: engine)
        self.keyboards = keyboards
        keyboards.start()
        let content = InteractionControls(keyboards: keyboards,
            showPopover: { [weak self] in self?.productionDelegate.togglePopover(nil) },
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
