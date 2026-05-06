import AppKit
import SwiftUI

final class RecorderNSView: NSView {
    var onShortcutRecorded: ((Int, NSEvent.ModifierFlags) -> Void)?
    var onActivate: (() -> Void)?
    var currentKeyCode: Int = -1
    var currentModifiers: NSEvent.ModifierFlags = []
    var placeholderText = "Press shortcut..."

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
        currentKeyCode = code
        currentModifiers = mods
        onShortcutRecorded?(code, mods)
        needsDisplay = true
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

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifiers: NSEvent.ModifierFlags

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.onShortcutRecorded = { code, mods in
            keyCode = code
            modifiers = mods
        }
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.currentKeyCode = keyCode
        nsView.currentModifiers = modifiers
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        override init() {}
    }
}
