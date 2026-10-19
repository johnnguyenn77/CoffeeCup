import SwiftUI
import AppKit

struct ContentView: View {
    var showAbout: () -> Void = { NSApp.orderFrontStandardAboutPanel(nil) }

    @EnvironmentObject private var caffeinate: CoffeeCupController
    @StateObject private var displayRotation = DisplayRotationController.shared
    @StateObject private var catMode = CatModeController.shared
    @StateObject private var keyboardModifiers = KeyboardModifierController.shared
    @State private var confirmCatModeActivation = false

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

            VStack(alignment: .leading, spacing: 12) {
                toggleRow("Keep display awake", isOn: Binding(
                    get: { caffeinate.isActive },
                    set: { caffeinate.setActive($0) }
                ))

                if let errorMessage = caffeinate.errorMessage {
                    errorLabel(errorMessage)
                }

                toggleRow("Cat Mode", isOn: Binding(
                    get: { catMode.isActive },
                    set: { enabled in
                        if enabled {
                            confirmCatModeActivation = true
                        } else {
                            catMode.setActive(false)
                        }
                    }
                ))
                .help("Blocks keyboard and pointer input. Press Control–Option–Command–Escape to exit.")

                if let errorMessage = catMode.errorMessage {
                    errorLabel(errorMessage)
                }

                if let errorMessage = keyboardModifiers.errorMessage {
                    errorLabel(errorMessage)
                }
            }

            if displayRotation.hasDisplays {
                Divider()
                DisplayRotationControls(controller: displayRotation)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 260, alignment: .topLeading)
        .onAppear {
            caffeinate.refreshLoginItemStatus()
            keyboardModifiers.refresh()
        }
        .alert("Turn On Cat Mode?", isPresented: $confirmCatModeActivation) {
            Button("Cancel", role: .cancel) { }
            Button("Turn On Cat Mode", role: .destructive) {
                catMode.setActive(true)
            }
        } message: {
            Text("Cat Mode blocks keyboard and pointer input, including the trackpad and external mouse. Exit with Control–Option–Command–Escape.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("CoffeeCup")
                .font(.title3.weight(.semibold))

            Spacer(minLength: 0)

            if let updateVersion = caffeinate.updateAvailableVersion {
                Button {
                    caffeinate.downloadUpdateDMG()
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Download CoffeeCup \(updateVersion). Open the DMG and replace CoffeeCup in Applications.")
                .accessibilityLabel("Download CoffeeCup update, version \(updateVersion)")
            }

            settingsMenu
        }
    }

    private var settingsMenu: some View {
        Menu {
            Toggle("Launch at login", isOn: Binding(
                get: { caffeinate.launchesAtLogin },
                set: { caffeinate.setLaunchAtLogin($0) }
            ))

            KeyboardModifierMenuItems(controller: keyboardModifiers)

            Divider()

            if caffeinate.updateAvailableVersion != nil {
                Button("Download Update…") {
                    caffeinate.downloadUpdateDMG()
                }
            }

            Button("About CoffeeCup", action: showAbout)

            Divider()

            Button("Quit CoffeeCup") {
                NSApp.terminate(nil)
            }
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

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.body)

            Spacer(minLength: 12)

            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .fixedSize()
        }
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    ContentView()
        .environmentObject(CoffeeCupController())
}
