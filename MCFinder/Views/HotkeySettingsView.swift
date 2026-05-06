import SwiftUI

struct HotkeySettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Keyboard Shortcuts")
                .font(.headline)

            shortcutSection(
                label: "Main Window",
                description: "Show or hide the main MCFinder window",
                keyCode: appState.hotkeyKeyCode,
                modifiers: appState.hotkeyModifiers,
                error: appState.hotkeyErrors[.main]
            ) { code, mods in
                appState.onHotkeyChanged(type: .main, keyCode: code, modifiers: mods)
            }

            shortcutSection(
                label: "Quick Search",
                description: "Show the quick search panel",
                keyCode: appState.quickSearchKeyCode,
                modifiers: appState.quickSearchModifiers,
                error: appState.hotkeyErrors[.quickSearch]
            ) { code, mods in
                appState.onHotkeyChanged(type: .quickSearch, keyCode: code, modifiers: mods)
            }

            Text("Shortcuts require at least one modifier (⌘ ⌥ ⌃ ⇧). Press Esc to cancel recording.")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("If a shortcut conflicts with macOS or another app, the recorder will show a warning — pick a different combination.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private func shortcutSection(
        label: String,
        description: String,
        keyCode: Int,
        modifiers: NSEvent.ModifierFlags,
        error: String?,
        onCommit: @escaping (Int, NSEvent.ModifierFlags) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)

            HotkeyRecorderView(keyCode: keyCode, modifiers: modifiers, onCommit: onCommit)
                .frame(width: 200, height: 30)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
