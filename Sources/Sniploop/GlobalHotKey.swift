import AppKit
import Carbon.HIToolbox

/// A process-global hotkey via Carbon's RegisterEventHotKey. Global without the Accessibility
/// permission that NSEvent global monitors require, and with no third-party dependency.
final class GlobalHotKey {
    // Each hotkey gets a unique id so its handler only responds to its own key. Carbon delivers
    // hotkey-pressed events to every handler installed on the app target, so without this check a
    // single keypress would fire every registered hotkey's closure.
    private static var nextID: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let hotKeyID: EventHotKeyID
    var onFire: (() -> Void)?

    /// `keyCode` is a Carbon virtual key code (e.g. kVK_ANSI_G); `modifiers` combine
    /// cmdKey / controlKey / optionKey / shiftKey.
    init(keyCode: UInt32, modifiers: UInt32) {
        let id = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1
        hotKeyID = EventHotKeyID(signature: OSType(0x534E4C50), id: id) // 'SNLP'

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let userData, let eventRef else { return noErr }
            let me = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            var fired = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &fired)
            if fired.id == me.hotKeyID.id && fired.signature == me.hotKeyID.signature {
                me.onFire?()
                return noErr
            }
            // Not our hotkey: let Carbon keep dispatching to the other installed handlers.
            return OSStatus(eventNotHandledErr)
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
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
