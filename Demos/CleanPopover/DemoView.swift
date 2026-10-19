import AppKit
import SwiftUI

struct CleanPopoverDemoView: View {
    @ObservedObject var state: CleanPopoverDemoState
    let showControls: () -> Void
    let showAbout: () -> Void
    @State private var confirmCatMode = false
    @State private var showUpdatePreview = false

    var body: some View {
        if #available(macOS 15.0, *) {
            popupContent
                .containerBackground(for: .window) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                }
        } else {
            popupContent
        }
    }

    private var popupContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            VStack(spacing: 12) {
                toggleRow("Keep display awake", isOn: $state.keepsDisplayAwake)
                toggleRow("Cat Mode", isOn: Binding(
                    get: { state.catModeActive },
                    set: { enabled in
                        if enabled { confirmCatMode = true }
                        else { state.setCatMode(false) }
                    }
                ))
                .help("The demo simulates Cat Mode without blocking any input.")
            }

            if !state.displays.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Display")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        if state.displays.count > 1 {
                            Picker("Display", selection: Binding(
                                get: { state.selectedDisplayID }, set: { state.selectDisplay($0) }
                            )) {
                                ForEach(state.displays) { display in Text(display.name).tag(display.id) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .frame(maxWidth: 146, alignment: .trailing)
                            .accessibilityLabel("Select display")
                        }
                    }

                    // Only this rendering component is shared with the real app.
                    // Its callback updates demo state, never the actual monitor.
                    DisplayRotationSelector(currentRotation: state.currentRotation,
                        onSelect: state.setRotation)
                        .id(state.selectedDisplayID)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 260, alignment: .topLeading)
        .alert("Turn On Cat Mode?", isPresented: $confirmCatMode) {
            Button("Cancel", role: .cancel) {}
            Button("Turn On Cat Mode") { state.setCatMode(true) }
        } message: {
            Text("This preview closes the popover, but does not block your keyboard or trackpad. Use End Cat Mode in the demo controls to reset it.")
        }
        .alert("Update Preview", isPresented: $showUpdatePreview) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The real app would download the update DMG. This demo does not download or install anything.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("CoffeeCup")
                .font(.title3.weight(.semibold))

            Spacer(minLength: 0)

            if state.updateAvailable {
                Button { showUpdatePreview = true } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Preview an available update")
                .accessibilityLabel("Download update preview")
            }

            Menu {
                Toggle("Launch at login", isOn: $state.launchesAtLogin)

                if !state.keyboards.isEmpty {
                    if state.keyboards.count > 1 {
                        Menu("Keyboard") {
                            Picker("Keyboard", selection: Binding(
                                get: { state.selectedKeyboardID }, set: { state.selectKeyboard($0) }
                            )) {
                                ForEach(state.keyboards) { keyboard in
                                    Text(keyboard.name).tag(keyboard.id)
                                }
                            }
                            .pickerStyle(.inline)
                        }
                    }
                    Toggle("Swap Alt / Windows", isOn: Binding(
                        get: { state.swapsModifiers }, set: { state.setSwapEnabled($0) }
                    ))
                }

                Divider()
                if state.updateAvailable {
                    Button("Download Update…") { showUpdatePreview = true }
                }
                Button("About CoffeeCup", action: showAbout)
                Button("Demo Controls…", action: showControls)
                Divider()
                Button("Quit Demo") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Settings and app actions")
            .accessibilityLabel("CoffeeCup settings")
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .fixedSize()
        }
    }
}

struct CleanPopoverDemoControls: View {
    @ObservedObject var state: CleanPopoverDemoState
    let showPopover: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cleaner CoffeeCup")
                    .font(.title2.weight(.semibold))
                Text("A native layout preview. All actions are simulated; your Mac and installed CoffeeCup stay unchanged.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                hardwarePicker("Displays", count: Binding(
                    get: { state.displayCount }, set: { state.setDisplayCount($0) }
                ))
                hardwarePicker("Keyboards", count: Binding(
                    get: { state.keyboardCount }, set: { state.setKeyboardCount($0) }
                ))
                Toggle("Show available update", isOn: $state.updateAvailable)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if state.catModeActive {
                HStack {
                    Label("Cat Mode on (simulated)", systemImage: "lock.fill")
                        .font(.callout)
                    Spacer()
                    Button("End Cat Mode") { state.setCatMode(false) }
                        .keyboardShortcut(.escape, modifiers: [.control, .option, .command])
                }
            }

            HStack {
                Button("Show Popover", action: showPopover)
                    .keyboardShortcut(.defaultAction)
                Spacer()
                Button("Reset") { state.reset() }
                Button("Quit Demo") { NSApp.terminate(nil) }
            }
        }
        .padding(22)
        .frame(width: 380)
    }

    private func hardwarePicker(_ title: String, count: Binding<Int>) -> some View {
        HStack {
            Text(title)
                .frame(width: 80, alignment: .leading)
            Picker(title, selection: count) {
                Text("None").tag(0)
                Text("One").tag(1)
                Text("Two").tag(2)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityLabel(title)
        }
    }
}
