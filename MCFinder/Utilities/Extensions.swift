import AppKit
import Carbon
import UniformTypeIdentifiers

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

extension NSEvent.ModifierFlags {
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if contains(.command) { result |= UInt32(cmdKey) }
        if contains(.shift) { result |= UInt32(shiftKey) }
        if contains(.option) { result |= UInt32(optionKey) }
        if contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    var displayString: String {
        var parts: [String] = []
        if contains(.control) { parts.append("⌃") }
        if contains(.option) { parts.append("⌥") }
        if contains(.shift) { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        return parts.joined()
    }

    init(rawValue: UInt) {
        self = []
        if rawValue & UInt(cmdKey) != 0 { insert(.command) }
        if rawValue & UInt(shiftKey) != 0 { insert(.shift) }
        if rawValue & UInt(optionKey) != 0 { insert(.option) }
        if rawValue & UInt(controlKey) != 0 { insert(.control) }
    }
}

extension Int {
    var keyCodeDisplayString: String {
        let specialKeys: [Int: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete",
            53: "Esc", 116: "Page Up", 121: "Page Down",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        if let special = specialKeys[self] { return special }
        if let source = CGEventSource(stateID: .hidSystemState),
           let keyEvent = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(self), keyDown: true),
           let nsEvent = NSEvent(cgEvent: keyEvent),
           nsEvent.charactersIgnoringModifiers?.isEmpty == false {
            return nsEvent.charactersIgnoringModifiers?.uppercased() ?? "Key\(self)"
        }
        return "Key\(self)"
    }
}

extension FileManager {
    func fileExists(at url: URL) -> Bool {
        fileExists(atPath: url.path)
    }
}
