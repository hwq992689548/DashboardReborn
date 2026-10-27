import Carbon.HIToolbox
import Foundation

/// 全局 F12 热键（Carbon RegisterEventHotKey，不需要辅助功能权限）。
final class GlobalHotKey {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: () -> Void
    private(set) var isRegistered = false

    init(keyCode: UInt32 = UInt32(kVK_F12), modifiers: UInt32 = 0, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let instance = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    instance.action()
                }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x4441_5348), id: 1) // "DASH"
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        isRegistered = installStatus == noErr && registerStatus == noErr
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
