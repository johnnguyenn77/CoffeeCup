import AppKit
import SwiftUI

struct CoffeeCupToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 0) {
            Button { isOn.toggle() } label: {
                HStack {
                    Text(title).font(.body)
                    Spacer(minLength: 12)
                }
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            // Expose one accessible switch, not a duplicate label button.
            .accessibilityHidden(true)

            FirstClickSwitch(title: title, isOn: $isOn)
                .fixedSize()
        }
    }
}

private struct FirstClickSwitch: NSViewRepresentable {
    let title: String
    @Binding var isOn: Bool

    func makeCoordinator() -> Coordinator { Coordinator(isOn: $isOn) }

    func makeNSView(context: Context) -> ClickThroughSwitch {
        let control = ClickThroughSwitch()
        control.controlSize = .regular
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        control.setAccessibilityLabel(title)
        return control
    }

    func updateNSView(_ control: ClickThroughSwitch, context: Context) {
        context.coordinator.isOn = $isOn
        let state: NSControl.StateValue = isOn ? .on : .off
        if control.state != state { control.state = state }
    }

    final class Coordinator: NSObject {
        var isOn: Binding<Bool>
        init(isOn: Binding<Bool>) { self.isOn = isOn }
        @objc func changed(_ sender: NSSwitch) { isOn.wrappedValue = sender.state == .on }
    }
}

final class ClickThroughSwitch: NSSwitch {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
