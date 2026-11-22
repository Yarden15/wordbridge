import Carbon
import Foundation

/// A system-wide keyboard shortcut, registered through Carbon's `RegisterEventHotKey`.
/// Works without Accessibility permission.
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false
    private static let signature: OSType = 0x5742_5244 // "WBRD"

    private var ref: EventHotKeyRef?
    private let id: UInt32

    /// - Parameters:
    ///   - keyCode: a virtual key code, e.g. `kVK_ANSI_T`.
    ///   - modifiers: Carbon modifier flags, e.g. `cmdKey | shiftKey`.
    init?(id: UInt32, keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        self.id = id
        HotKey.installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: HotKey.signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr else {
            NSLog("Wordbridge: failed to register hotkey \(id) (status \(status))")
            return nil
        }
        HotKey.handlers[id] = handler
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.handlers[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard hotKeyID.signature == HotKey.signature else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { HotKey.handlers[hotKeyID.id]?() }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}
