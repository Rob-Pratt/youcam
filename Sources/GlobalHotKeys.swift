import AppKit
import Carbon

@MainActor
final class GlobalHotKeys {
    private var handler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    var onRecord: (() -> Void)?
    var onPause: (() -> Void)?
    private(set) var available = true

    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                let owner = Unmanaged<GlobalHotKeys>.fromOpaque(context).takeUnretainedValue()
                if id.id == 1 { owner.onRecord?() }
                if id.id == 2 { owner.onPause?() }
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { available = false; return }
        for (key, id) in [(kVK_ANSI_R, UInt32(1)), (kVK_ANSI_P, UInt32(2))] {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey | cmdKey),
                EventHotKeyID(signature: 0x5943414D, id: id), GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { hotKeys.append(reference) }
            else { available = false }
        }
    }

    func shutdown() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
