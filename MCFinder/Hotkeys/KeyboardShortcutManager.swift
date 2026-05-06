import Carbon
import AppKit

/// Outcome of a single `RegisterEventHotKey` attempt.
///
/// Surfaced to the UI so users can tell whether their chosen combination is
/// valid, conflicts with another app/system, or fails for some other reason.
enum HotkeyRegistrationResult: Equatable {
    case success
    case noModifier
    case alreadyTaken
    case failed(OSStatus)

    /// Human-readable hint suitable for display under the recorder. `nil` on success.
    var errorMessage: String? {
        switch self {
        case .success:
            return nil
        case .noModifier:
            return "Add a modifier (⌘ ⌥ ⌃ ⇧) — bare keys cannot be used as global shortcuts."
        case .alreadyTaken:
            return "This shortcut is already used by another app or macOS — try a different combination."
        case .failed(let status):
            return "Could not register shortcut (OSStatus \(status))."
        }
    }
}

final class KeyboardShortcutManager {
    private var mainHotKeyRef: EventHotKeyRef?
    private var quickSearchHotKeyRef: EventHotKeyRef?
    private var mainHandlerRef: EventHandlerRef?
    private var quickSearchHandlerRef: EventHandlerRef?

    var onMainHotkey: (() -> Void)?
    var onQuickSearchHotkey: (() -> Void)?

    private let mainHotKeyID = EventHotKeyID(signature: 0x4D434644, id: 1)
    private let quickSearchHotKeyID = EventHotKeyID(signature: 0x4D434644, id: 2)

    // Carbon's `eventHotKeyExistsErr` constant (defined in MacErrors.h). Returned
    // by `RegisterEventHotKey` when another app — or macOS itself — owns the
    // combo. Hard-coded because it is not surfaced as a Swift symbol.
    private let eventHotKeyExistsErr: OSStatus = -9878

    deinit { unregisterAll() }

    @discardableResult
    func registerMainHotkey(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> HotkeyRegistrationResult {
        unregisterMainHotkey()
        // Refuse to register a global hotkey that has no modifiers — that
        // would steal a bare key (e.g. Space, keyCode 49) system-wide.
        // This guards against corrupted UserDefaults and accidental UI states.
        let carbonMods = modifiers.carbonModifiers
        guard carbonMods != 0 else { return .noModifier }
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), carbonMods, mainHotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        if status == noErr, let ref = hotKeyRef {
            mainHotKeyRef = ref
            installMainHandler()
            return .success
        }
        if status == eventHotKeyExistsErr {
            return .alreadyTaken
        }
        return .failed(status)
    }

    @discardableResult
    func registerQuickSearchHotkey(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> HotkeyRegistrationResult {
        unregisterQuickSearchHotkey()
        // Same guard as the main hotkey: never register a bare key globally.
        let carbonMods = modifiers.carbonModifiers
        guard carbonMods != 0 else { return .noModifier }
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), carbonMods, quickSearchHotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        if status == noErr, let ref = hotKeyRef {
            quickSearchHotKeyRef = ref
            installQuickSearchHandler()
            return .success
        }
        if status == eventHotKeyExistsErr {
            return .alreadyTaken
        }
        return .failed(status)
    }

    func unregisterAll() {
        unregisterMainHotkey()
        unregisterQuickSearchHotkey()
    }

    private func unregisterMainHotkey() {
        if let ref = mainHotKeyRef {
            UnregisterEventHotKey(ref)
            mainHotKeyRef = nil
        }
        if let handler = mainHandlerRef {
            RemoveEventHandler(handler)
            mainHandlerRef = nil
        }
    }

    private func unregisterQuickSearchHotkey() {
        if let ref = quickSearchHotKeyRef {
            UnregisterEventHotKey(ref)
            quickSearchHotKeyRef = nil
        }
        if let handler = quickSearchHandlerRef {
            RemoveEventHandler(handler)
            quickSearchHandlerRef = nil
        }
    }

    private func installMainHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let result = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let data = userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(data).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                if err == noErr && hotKeyID.id == 1 {
                    DispatchQueue.main.async { manager.onMainHotkey?() }
                    return noErr
                }
                return OSStatus(eventNotHandledErr)
            },
            1, &eventType, selfPtr, &mainHandlerRef
        )
        if result != noErr {
            // Logger.hotkey.error("Failed to install main hotkey handler: \(result)")
        }
    }

    private func installQuickSearchHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let result = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let data = userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(data).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                if err == noErr && hotKeyID.id == 2 {
                    DispatchQueue.main.async { manager.onQuickSearchHotkey?() }
                    return noErr
                }
                return OSStatus(eventNotHandledErr)
            },
            1, &eventType, selfPtr, &quickSearchHandlerRef
        )
        if result != noErr {
            // Logger.hotkey.error("Failed to install quick search hotkey handler: \(result)")
        }
    }
}
