import Carbon.HIToolbox
import CoreGraphics
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mouse Button Mappings")
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("+ Add button") {
                    _ = model.addButton()
                }
                .disabled(model.visibleButtons.count >= AppEnvironment.supportedButtonRange.count)
            }

            if model.isLearningButton {
                Text("Learning is active. Press the next mouse button to capture its number.")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            if let warningMessage = model.warningMessage {
                Text(warningMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if model.visibleButtons.isEmpty {
                        Text("No buttons detected or configured yet. Use Learn button from the menu bar or add one manually.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(model.visibleButtons, id: \.self) { buttonNumber in
                            ButtonMappingRow(
                                buttonNumber: buttonNumber,
                                action: actionBinding(for: buttonNumber),
                                isHighlighted: model.lastObservedButton == buttonNumber,
                                onDelete: { model.removeButton(buttonNumber) }
                            )
                        }
                    }
                }
            }

            Divider()

            Text("Built-in actions use public keyboard shortcuts: Control-Left/Right/Up/Down Arrow, F4, and F11. If you changed those shortcuts in macOS, switch that row to Custom and match your own key code and modifiers.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 360)
    }

    private var subtitle: String {
        if let lastObservedButton = model.lastObservedButton {
            return "Last observed button: \(lastObservedButton)"
        }
        return "Press a mouse button while this window is open to highlight or discover it live."
    }

    private func actionBinding(for buttonNumber: Int) -> Binding<ButtonAction> {
        Binding(
            get: { model.action(for: buttonNumber) },
            set: { model.setAction($0, for: buttonNumber) }
        )
    }
}

private struct ButtonMappingRow: View {
    let buttonNumber: Int
    @Binding var action: ButtonAction
    let isHighlighted: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Button \(buttonNumber)")
                    .font(.body.weight(.semibold))
                    .frame(width: 90, alignment: .leading)

                Picker("Action", selection: actionChoice) {
                    ForEach(ButtonActionChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .labelsHidden()
                .frame(width: 220)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            if case .custom = action {
                HStack(spacing: 12) {
                    Text("Key code")
                        .foregroundStyle(.secondary)
                    TextField("Key code", value: customKeyCode, format: .number)
                        .frame(width: 80)
                    Toggle("Control", isOn: modifierBinding(.maskControl))
                        .toggleStyle(.checkbox)
                    Toggle("Command", isOn: modifierBinding(.maskCommand))
                        .toggleStyle(.checkbox)
                    Toggle("Option", isOn: modifierBinding(.maskAlternate))
                        .toggleStyle(.checkbox)
                    Toggle("Shift", isOn: modifierBinding(.maskShift))
                        .toggleStyle(.checkbox)
                }
                .padding(.leading, 102)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHighlighted ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.06))
        )
    }

    private var actionChoice: Binding<ButtonActionChoice> {
        Binding(
            get: { ButtonActionChoice(action: action) },
            set: { action = $0.makeAction(preserving: action) }
        )
    }

    private var customKeyCode: Binding<Int> {
        Binding(
            get: { Int(customPayload.keyCode) },
            set: { newValue in
                let clampedValue = min(max(newValue, 0), Int(UInt16.max))
                action = .custom(keyCode: CGKeyCode(clampedValue), modifiers: customPayload.modifiers)
            }
        )
    }

    private var customPayload: (keyCode: CGKeyCode, modifiers: CGEventFlags) {
        if case let .custom(keyCode, modifiers) = action {
            return (keyCode, modifiers)
        }
        return (CGKeyCode(kVK_LeftArrow), .maskControl)
    }

    private func modifierBinding(_ flag: CGEventFlags) -> Binding<Bool> {
        Binding(
            get: { customPayload.modifiers.contains(flag) },
            set: { isEnabled in
                var modifiers = customPayload.modifiers
                if isEnabled {
                    modifiers.insert(flag)
                } else {
                    modifiers.remove(flag)
                }
                action = .custom(keyCode: customPayload.keyCode, modifiers: modifiers)
            }
        )
    }
}
