import Carbon
import AppKit

final class KeyboardShortcutManager {
    private var mainHotKeyRef: EventHotKeyRef?
    private var quickSearchHotKeyRef: EventHotKeyRef?
    private var mainHandlerRef: EventHandlerRef?
    private var quickSearchHandlerRef: EventHandlerRef?

    var onMainHotkey: (() -> Void)?
    var onQuickSearchHotkey: (() -> Void)?

    private let mainHotKeyID = EventHotKeyID(signature: 0x4D434644, id: 1)
    private let quickSearchHotKeyID = EventHotKeyID(signature: 0x4D434644, id: 2)

    deinit { unregisterAll() }

    func registerMainHotkey(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
        unregisterMainHotkey()
        let carbonMods = modifiers.carbonModifiers
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), carbonMods, mainHotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard status == noErr, let ref = hotKeyRef else {
            // Logger.hotkey.warning("[HotkeyManager] Main hotkey status=register_failed (keyCode: \(keyCode))")
            return false
        }
        mainHotKeyRef = ref
        installMainHandler()
        // Logger.hotkey.info("[HotkeyManager] Main hotkey status=registered (keyCode: \(keyCode))")
        return true
    }

    func registerQuickSearchHotkey(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
        unregisterQuickSearchHotkey()
        let carbonMods = modifiers.carbonModifiers
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), carbonMods, quickSearchHotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard status == noErr, let ref = hotKeyRef else {
            // Logger.hotkey.warning("[HotkeyManager] Quick search hotkey status=register_failed (keyCode: \(keyCode))")
            return false
        }
        quickSearchHotKeyRef = ref
        installQuickSearchHandler()
        // Logger.hotkey.info("[HotkeyManager] Quick search hotkey status=registered (keyCode: \(keyCode))")
        return true
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
