import Foundation

/// 把布局存到 ~/Library/Application Support/DashboardReborn/layout.json。
/// 如果目录不可写（例如被沙盒限制），退回用户主目录下的隐藏文件。
final class LayoutStore {

    private(set) var fileURL: URL
    private(set) var layout: DashboardLayout

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let directory = support.appendingPathComponent("DashboardReborn", isDirectory: true)

        var file = directory.appendingPathComponent("layout.json")
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let probe = directory.appendingPathComponent(".write-test")
            try Data("ok".utf8).write(to: probe)
            try? fm.removeItem(at: probe)
        } catch {
            file = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".dashboard-reborn-layout.json")
        }

        fileURL = file
        if let override = ProcessInfo.processInfo.environment["DASHBOARD_LAYOUT_PATH"],
           !override.isEmpty {
            fileURL = URL(fileURLWithPath: override)
            try? fm.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(DashboardLayout.self, from: data) {
            layout = decoded
        } else {
            layout = DashboardLayout()
        }
    }

    func save(_ layout: DashboardLayout) {
        self.layout = layout
        guard let data = try? JSONEncoder().encode(layout) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
