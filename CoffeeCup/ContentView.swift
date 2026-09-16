sed: --: No such file or directory
import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var caffeinate: CoffeeCupController
    @State private var isQuitHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                keepAwakeRow
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: caffeinate.isActive ? "sun.max.fill" : "moon.zzz.fill")
                .font(.title2)
                .foregroundStyle(caffeinate.isActive ? .orange : .secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text("CoffeeCup")
                    .font(.title3.weight(.semibold))

                Text(caffeinate.isActive ? "Your Mac is staying awake" : "Sleep is allowed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                in: RoundedRectangle(cornerRadius: 6)
            )
            .onHover { isHovered in
                withAnimation(.easeOut(duration: 0.12)) {
                    isQuitHovered = isHovered
                }
            }
        }
    }

    private var keepAwakeRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Keep Mac awake")
                    .font(.headline)

                Text(caffeinate.isActive
                     ? "Sleep prevented while enabled."
                     : "Sleep allowed normally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Toggle("Keep Mac awake", isOn: Binding(
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
            VStack(alignment: .leading, spacing: 3) {
                Text("Launch at login")
                    .font(.headline)

                Text(caffeinate.launchesAtLogin
                     ? "Starts when you sign in."
                     : "Start CoffeeCup when you sign in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

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
