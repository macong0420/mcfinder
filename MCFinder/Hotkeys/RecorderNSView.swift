import AppKit
import SwiftUI

final class RecorderNSView: NSView {
    /// Called once with a *valid* shortcut (modifier + key) when the user
    /// finishes recording. Bare keys are silently ignored so the user can't
    /// accidentally bind Space (which would hijack the keyboard).
    var onShortcutRecorded: ((Int, NSEvent.ModifierFlags) -> Void)?
    var onActivate: (() -> Void)?
    var currentKeyCode: Int = -1
    var currentModifiers: NSEvent.ModifierFlags = []
    var placeholderText = "Press shortcut..."

    private static let modifierMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        onActivate?()
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let code = Int(event.keyCode)
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let usedModifiers = mods.intersection(Self.modifierMask)

        // Esc with no modifier exits recording mode without changing anything.
        if code == 53 && usedModifiers.isEmpty {
            window?.makeFirstResponder(nil)
            return
        }
        // Reject bare keys outright — they would become global keystrokes
        // (RegisterEventHotKey would steal Space/F/etc. system-wide). The UI
        // hint above the recorder tells the user to use a modifier.
        guard !usedModifiers.isEmpty else {
            NSSound.beep()
            return
        }

        currentKeyCode = code
        currentModifiers = usedModifiers
        onShortcutRecorded?(code, usedModifiers)
        needsDisplay = true
        // Drop focus so the same keystroke isn't accidentally re-recorded.
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let isFirstResponder = window?.firstResponder == self
        let isRecording = isFirstResponder
        let text = currentKeyCode >= 0 && !isRecording
            ? shortcutDisplayString
            : (isRecording ? "Type shortcut..." : placeholderText)

        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        } else {
            NSColor.controlBackgroundColor.setFill()
        }
        path.fill()

        if isRecording {
            NSColor.controlAccentColor.setStroke()
        } else {
            NSColor.separatorColor.setStroke()
        }
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    private var shortcutDisplayString: String {
        var parts: [String] = []
        let modString = currentModifiers.displayString
        if !modString.isEmpty { parts.append(modString) }
        parts.append(currentKeyCode.keyCodeDisplayString)
        return parts.joined()
    }
}

// MARK: - SwiftUI Wrapper

/// SwiftUI bridge that displays the currently-saved shortcut and invokes
/// `onCommit` exactly once per successful recording — atomically, with both
/// keyCode and modifiers in a single call. The previous design used two
/// separate `Binding`s, which fired the change handler twice (with an
/// intermediate state that could re-register a different combo).
struct HotkeyRecorderView: NSViewRepresentable {
    let keyCode: Int
    let modifiers: NSEvent.ModifierFlags
    var onCommit: (Int, NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.currentKeyCode = keyCode
        view.currentModifiers = modifiers
        view.onShortcutRecorded = { code, mods in onCommit(code, mods) }
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        // Refresh the closure each update so the latest `onCommit` capture is used.
        nsView.onShortcutRecorded = { code, mods in onCommit(code, mods) }
        if nsView.currentKeyCode != keyCode || nsView.currentModifiers != modifiers {
            nsView.currentKeyCode = keyCode
            nsView.currentModifiers = modifiers
            nsView.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        override init() {}
    }
}
