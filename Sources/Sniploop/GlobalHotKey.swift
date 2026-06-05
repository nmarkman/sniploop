import AppKit
import Carbon.HIToolbox

/// A process-global hotkey via Carbon's RegisterEventHotKey. Global without the Accessibility
/// permission that NSEvent global monitors require, and with no third-party dependency.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onFire: (() -> Void)?

    /// `keyCode` is a Carbon virtual key code (e.g. kVK_ANSI_G); `modifiers` combine
    /// cmdKey / controlKey / optionKey / shiftKey.
    init(keyCode: UInt32, modifiers: UInt32) {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().onFire?()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        let id = EventHotKeyID(signature: OSType(0x534E4C50), id: 1) // 'SNLP'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    /// The default Sniploop trigger: Hyper (Cmd-Ctrl-Opt-Shift) + G. A Caps-Lock-as-Hyper
    /// setup (via Raycast/Karabiner) sends this same chord.
    static func defaultCapture(onFire: @escaping () -> Void) -> GlobalHotKey {
        let hk = GlobalHotKey(keyCode: UInt32(kVK_ANSI_G),
                              modifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey))
        hk.onFire = onFire
        return hk
    }

    /// Plain Return, with no modifiers. Used transiently while recording (stop).
    static func returnKey(onFire: @escaping () -> Void) -> GlobalHotKey {
        let hk = GlobalHotKey(keyCode: UInt32(kVK_Return), modifiers: 0)
        hk.onFire = onFire
        return hk
    }

    /// Plain Escape, with no modifiers. Used transiently while recording (cancel).
    static func escapeKey(onFire: @escaping () -> Void) -> GlobalHotKey {
        let hk = GlobalHotKey(keyCode: UInt32(kVK_Escape), modifiers: 0)
        hk.onFire = onFire
        return hk
    }
}
