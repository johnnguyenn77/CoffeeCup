import SwiftUI

struct KeyboardModifierMenuItems: View {
    @ObservedObject var controller: KeyboardModifierController

    var body: some View {
        if controller.hasKeyboards {
            if controller.keyboards.count > 1 {
                Menu("Keyboard") {
                    Picker("Keyboard", selection: Binding(
                        get: { controller.selectedKeyboardID ?? "" },
                        set: { controller.selectKeyboard($0) }
                    )) {
                        ForEach(controller.keyboards) { keyboard in
                            Text(keyboard.name).tag(keyboard.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.inline)
                }
                .help("Select the external keyboard to remap. The built-in keyboard is never changed.")
            }

            Toggle("Swap Alt / Windows", isOn: Binding(
                get: { controller.swapsModifiers },
                set: { controller.setSwapEnabled($0) }
            ))
            .disabled(controller.selectedKeyboard == nil)
            .help("Keep the keyboard in Windows mode. Swap left and right Alt/Windows into Mac Command/Option positions on this keyboard only.")
        }
    }
}
