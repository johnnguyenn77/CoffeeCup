import SwiftUI

struct KeyboardModifierControls: View {
    @ObservedObject var controller: KeyboardModifierController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Label("Keyboard", systemImage: "keyboard")
                Spacer(minLength: 0)
                Menu {
                    ForEach(controller.keyboards) { keyboard in
                        Button { controller.selectKeyboard(keyboard.id) } label: {
                            if keyboard.id == controller.selectedKeyboardID {
                                Label(keyboard.name, systemImage: "checkmark")
                            } else { Text(keyboard.name) }
                        }
                    }
                } label: {
                    Text(controller.selectedKeyboard?.name ?? "Select")
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 120, alignment: .trailing)
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: false, vertical: true)
                .help("Select the external keyboard to remap. The built-in keyboard is never changed.")
                .accessibilityLabel("External keyboard")
                .accessibilityValue(controller.selectedKeyboard?.name ?? "None")
            }

            HStack(alignment: .center, spacing: 12) {
                Text("Swap Alt / Windows")
                Spacer(minLength: 12)
                Toggle("Swap Alt / Windows", isOn: Binding(
                    get: { controller.swapsModifiers }, set: { controller.setSwapEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .fixedSize()
                .disabled(controller.selectedKeyboard == nil)
                .help("Keep the keyboard in Windows mode. Swap left and right Alt/Windows into Mac Command/Option positions on this keyboard only.")
            }

            if let errorMessage = controller.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("External keyboard modifiers")
    }
}
