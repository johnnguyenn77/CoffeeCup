import SwiftUI
import AppKit

struct ContentView: View {
    var showAbout: () -> Void = { NSApp.orderFrontStandardAboutPanel(nil) }
    var requestCatMode: () -> Void = {}
    var menuPresentation: CoffeeCupMenuPresentation = .standalone

    @EnvironmentObject private var caffeinate: CoffeeCupController
    @StateObject private var displayRotation = DisplayRotationController.shared
    @StateObject private var catMode = CatModeController.shared
    @StateObject private var keyboardModifiers = KeyboardModifierController.shared

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
                CoffeeCupToggleRow(title: "Keep display awake", isOn: Binding(
                    get: { caffeinate.isActive },
                    set: { caffeinate.setActive($0) }
                ))

                if let errorMessage = caffeinate.errorMessage {
                    errorLabel(errorMessage)
                }

                CoffeeCupToggleRow(title: "Cat Mode", isOn: Binding(
                    get: { catMode.isActive },
                    set: { enabled in
                        if enabled {
                            requestCatMode()
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
                .buttonStyle(.borderless)
                .help("Download CoffeeCup \(updateVersion). Open the DMG and replace CoffeeCup in Applications.")
                .accessibilityLabel("Download CoffeeCup update, version \(updateVersion)")
            }

            CoffeeCupSettingsButton(caffeinate: caffeinate, keyboards: keyboardModifiers,
                                    showAbout: showAbout, menuPresentation: menuPresentation)
                .frame(width: 28, height: 28)
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
