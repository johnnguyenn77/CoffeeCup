import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var caffeinate: CoffeeCupController
    @StateObject private var displayRotation = DisplayRotationController()
    @State private var isQuitHovered = false

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
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            keepDisplayAwakeRow
            if displayRotation.hasDisplays {
                DisplayRotationControls(controller: displayRotation)
            }

            if let errorMessage = caffeinate.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            launchAtLoginRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 320, alignment: .topLeading)
        .onAppear {
            caffeinate.refreshLoginItemStatus()
            displayRotation.refreshDisplays()

            // Retry after AppKit has finished publishing its initial screen list.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                displayRotation.refreshDisplays()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )) { _ in
            displayRotation.refreshDisplays()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: caffeinate.isActive ? "sun.max.fill" : "moon.zzz.fill")
                .font(.title2)
                .foregroundStyle(caffeinate.isActive ? .orange : .secondary)
                .frame(width: 28, height: 28)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("CoffeeCup")
                    .font(.title3.weight(.semibold))

                Text(appVersion)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

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

            Spacer(minLength: 0)

            Button("Quit") {
                caffeinate.stop()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isQuitHovered ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isQuitHovered ? Color.primary.opacity(0.12) : .clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .onHover { isHovered in
                withAnimation(.easeOut(duration: 0.12)) {
                    isQuitHovered = isHovered
                }
            }
        }
    }

    private var appVersion: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return ""
        }
        return "v\(version)"
    }

    private var keepDisplayAwakeRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Keep display awake")
                .font(.body)

            Spacer(minLength: 12)

            Toggle("Keep display awake", isOn: Binding(
                get: { caffeinate.isActive },
                set: { caffeinate.setActive($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .fixedSize()
        }
    }

    private var launchAtLoginRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Launch at login")
                .font(.body)

            Spacer(minLength: 12)

            Toggle("Launch at login", isOn: Binding(
                get: { caffeinate.launchesAtLogin },
                set: { caffeinate.setLaunchAtLogin($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .fixedSize()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(CoffeeCupController())
}
