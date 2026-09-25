import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var caffeinate: CoffeeCupController
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

            VStack(alignment: .leading, spacing: 12) {
                keepDisplayAwakeRow
                launchAtLoginRow
            }

            if let errorMessage = caffeinate.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 290, alignment: .topLeading)
        .onAppear {
            caffeinate.refreshLoginItemStatus()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: caffeinate.isActive ? "sun.max.fill" : "moon.zzz.fill")
                .font(.title2)
                .foregroundStyle(caffeinate.isActive ? .orange : .secondary)
                .frame(width: 28, height: 28)

            Text("CoffeeCup")
                .font(.title3.weight(.semibold))

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

    private var keepDisplayAwakeRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Keep display awake")
                .font(.headline)

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
                .font(.headline)

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
