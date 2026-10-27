import AppKit
import Foundation

/// 按路径缓存 App 图标，避免每次 body 求值都去问 Launch Services。
final class IconProvider {

    static let shared = IconProvider()

    private var cache: [String: NSImage] = [:]
    private let size = NSSize(width: 128, height: 128)

    private init() {}

    func icon(for path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = size
        cache[path] = image
        return image
    }
}
