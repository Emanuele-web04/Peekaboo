import Carbon.HIToolbox

@MainActor
final class GlobalHotKey {
    private static let signature: OSType = 0x504B424F // "PKBO"

    private let keyCode: UInt32
    private let modifiers: UInt32
    private let action: @MainActor () -> Void
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    convenience init(action: @escaping @MainActor () -> Void) {
        self.init(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(controlKey | optionKey),
            action: action
        )
    }

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action
    }

    func register() {
        guard hotKeyReference == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return noErr }

                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr, identifier.signature == GlobalHotKey.signature else {
                    return noErr
                }

                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandlerReference
        )
        guard installStatus == noErr else { return }

        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        if registerStatus != noErr {
            if let eventHandlerReference { RemoveEventHandler(eventHandlerReference) }
            eventHandlerReference = nil
        }
    }

    func unregister() {
        if let hotKeyReference { UnregisterEventHotKey(hotKeyReference) }
        if let eventHandlerReference { RemoveEventHandler(eventHandlerReference) }
        hotKeyReference = nil
        eventHandlerReference = nil
    }
}
