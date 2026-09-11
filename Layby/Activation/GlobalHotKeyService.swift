import AppKit
import Carbon
import os

@MainActor
final class GlobalHotKeyService {
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var isPressed = false
    private(set) var registeredShortcut: HotKeyShortcut?
    var onPress: (() -> Void)?

    func register(_ shortcut: HotKeyShortcut?) -> OSStatus {
        guard let shortcut else { stop(); return noErr }
        if shortcut == registeredShortcut { return noErr }
        if handler == nil {
            var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                         EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
                guard let pointer, let event else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                               nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr, identifier.signature == 0x4C415942 else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated {
                    let service = Unmanaged<GlobalHotKeyService>.fromOpaque(pointer).takeUnretainedValue()
                    if GetEventKind(event) == UInt32(kEventHotKeyReleased) { service.isPressed = false }
                    else if !service.isPressed { service.isPressed = true; service.onPress?() }
                }
                return noErr
            }, 2, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return status }
        }
        // Register first: a failed replacement leaves the old shortcut usable.
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: 0x4C415942, id: 1), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &replacement)
        guard status == noErr else {
            Logger.activation.error("Hotkey registration failed: \(status)")
            return status
        }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        registeredShortcut = shortcut
        return noErr
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        registeredShortcut = nil
        isPressed = false
    }
}
