import AppKit
import UniformTypeIdentifiers

/// 统一管理背景图片选择面板。Dashboard 是 .statusBar 层级的无边框面板，
/// 文件选择框必须以 sheet 或更高的层级呈现，否则会被全屏面板挡住。
@MainActor
enum BackgroundImagePicker {
    private static var panel: NSOpenPanel?

    static var isPresented: Bool {
        panel?.isVisible == true
    }

    static func present(host: NSWindow?, completion: @escaping (URL?) -> Void) {
        if let existing = panel {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.image]
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        picker.prompt = "选择背景"
        picker.isReleasedWhenClosed = false
        picker.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel = picker

        NSApp.activate(ignoringOtherApps: true)

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            DispatchQueue.main.async {
                panel = nil
                completion(response == .OK ? picker.url : nil)
            }
        }

        if let host, host.isVisible {
            picker.beginSheetModal(for: host, completionHandler: finish)
        } else {
            picker.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            picker.begin(completionHandler: finish)
            picker.makeKeyAndOrderFront(nil)
        }
    }

    static func cancelForTesting() {
        guard let picker = panel else { return }
        picker.cancel(nil)
        picker.orderOut(nil)
        panel = nil
    }
}
