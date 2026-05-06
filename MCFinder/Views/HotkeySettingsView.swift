import SwiftUI

struct HotkeySettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Keyboard Shortcuts")
                .font(.headline)

            shortcutSection(
                label: "Main Window",
                keyCode: Binding(
                    get: { appState.hotkeyKeyCode },
                    set: { appState.onHotkeyChanged(type: .main, keyCode: $0, modifiers: appState.hotkeyModifiers) }
                ),
                modifiers: Binding(
                    get: { appState.hotkeyModifiers },
                    set: { appState.onHotkeyChanged(type: .main, keyCode: appState.hotkeyKeyCode, modifiers: $0) }
                ),
                description: "Show or hide the main MCFinder window"
            )

            shortcutSection(
                label: "Quick Search",
                keyCode: Binding(
                    get: { appState.quickSearchKeyCode },
                    set: { appState.onHotkeyChanged(type: .quickSearch, keyCode: $0, modifiers: appState.quickSearchModifiers) }
                ),
                modifiers: Binding(
                    get: { appState.quickSearchModifiers },
                    set: { appState.onHotkeyChanged(type: .quickSearch, keyCode: appState.quickSearchKeyCode, modifiers: $0) }
                ),
                description: "Show the quick search panel"
            )

            Text("Shortcuts require at least one modifier key (Cmd, Shift, Option, Control).")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("If a shortcut conflicts with a system shortcut, try a different combination.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private func shortcutSection(
        label: String,
        keyCode: Binding<Int>,
        modifiers: Binding<NSEvent.ModifierFlags>,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)

            HotkeyRecorderView(keyCode: keyCode, modifiers: modifiers)
                .frame(width: 200, height: 30)
        }
    }
}
