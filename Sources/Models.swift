import Foundation

/// 一个已安装的 App（只保存可持久化的元数据，图标按需加载）。
struct AppInfo: Identifiable, Hashable, Codable {
    var id: String { path }
    let path: String
    let name: String
    let bundleID: String?
}

/// 面板上的文件夹（对应旧版 Dashboard 的“分组”）。
struct Folder: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var appPaths: [String]

    init(id: UUID = UUID(), name: String = "新建文件夹", appPaths: [String] = []) {
        self.id = id
        self.name = name
        self.appPaths = appPaths
    }
}

/// 面板上的一格：要么是一个 App，要么是一个文件夹。
enum Tile: Identifiable, Hashable, Codable {
    case app(String)
    case folder(Folder)

    var id: String {
        switch self {
        case .app(let path):
            return "app:\(path)"
        case .folder(let folder):
            return "folder:\(folder.id.uuidString)"
        }
    }

    var appPaths: [String] {
        switch self {
        case .app(let path):
            return [path]
        case .folder(let folder):
            return folder.appPaths
        }
    }

    var folder: Folder? {
        if case .folder(let folder) = self {
            return folder
        }
        return nil
    }
}

/// 持久化的面板布局。`hidden` 记录用户主动从面板移除的 App，重新扫描时不会再加回来。
struct DashboardLayout: Codable {
    var tiles: [Tile] = []
    var hidden: Set<String> = []
}

/// 由滑杆连续控制的图标尺寸和网格度量。
struct IconMetrics {
    let side: CGFloat

    var iconFrame: CGFloat { side + 18 }
    var tileWidth: CGFloat { iconFrame + 24 }
    var labelWidth: CGFloat { tileWidth - 8 }
    var labelFont: CGFloat { min(13, max(11.5, side / 5.6)) }

    /// 图标较小时多放一列；其余保持 7 列，保证 35 个/页仍然放得下。
    var columns: Int { side < 68 ? 9 : 7 }

    var gridSpacing: CGFloat { 20 }

    var gridMaxWidth: CGFloat {
        CGFloat(columns) * tileWidth + CGFloat(columns - 1) * gridSpacing + 40
    }

    var folderMini: CGFloat { (side * 0.36).rounded() }
    var folderInner: CGFloat { folderMini * 2 + 4 }
    var folderInset: CGFloat { (side - folderInner) / 2 }
}

/// 背景样式：内置渐变 / 纯色，或用户选择的图片。
enum BackgroundStyle: String, CaseIterable, Identifiable, Codable {
    case aurora
    case midnight
    case ocean
    case violet
    case graphite
    case rose
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora: return "极光"
        case .midnight: return "午夜"
        case .ocean: return "深海"
        case .violet: return "紫罗兰"
        case .graphite: return "石墨"
        case .rose: return "玫瑰"
        case .custom: return "图片"
        }
    }

    /// 设置面板中展示的内置背景（不含自定义图片）。
    static let presets: [BackgroundStyle] = [
        .aurora, .midnight, .ocean, .violet, .graphite, .rose
    ]
}
