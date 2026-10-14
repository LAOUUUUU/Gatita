//
//  GlobalHotKey.swift
//  Gatita
//

#if os(macOS)
import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut that works while another app is in front, through Carbon's RegisterEventHotKey.
/// It needs no Accessibility permission, and works in the App Sandbox.
@MainActor
final class GlobalHotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false
    private static var nextID: UInt32 = 1
    private var reference: EventHotKeyRef?
    private let id: UInt32

    /// Registers the shortcut. Nil when the system refuses it, such as when another app already holds it.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        Self.installHandler()
        id = Self.nextID
        Self.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x4754_5441), id: id) // "GTTA"
        var created: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &created)
        guard status == noErr, let created else { return nil }
        reference = created
        Self.actions[id] = action
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        Self.actions[id] = nil
    }

    private static func fire(_ id: UInt32) {
        actions[id]?()
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let id = pressed.id
            Task { @MainActor in GlobalHotKey.fire(id) }
            return noErr
        }, 1, &type, nil, nil)
    }
}
#endif
