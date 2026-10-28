import AppKit
import Foundation
import SwiftUI

@MainActor
final class DashboardModel: ObservableObject {

    @Published private(set) var layout: DashboardLayout
    @Published private(set) var apps: [String: AppInfo] = [:]
    @Published var isEditing = false
    @Published var openedFolderID: UUID?
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var isScanning = false
    @Published private(set) var toast: String?
    @Published var selectedTileID: String?
    @Published var searchText: String = "" {
        didSet {
            if searchText != oldValue {
                selectedTileID = nil
                currentPage = 0
            }
        }
    }
    @Published var isShowingSettings = false
    @Published var currentPage = 0
    @Published var iconSide: Double {
        didSet {
            let clamped = min(max(iconSide, 64), 100)
            if clamped != iconSide {
                iconSide = clamped
                return
            }
            Self.settingsDefaults.set(clamped, forKey: Self.iconSideKey)
        }
    }
    /// 每页容量由图标尺寸和页面可用高度自动计算，不再写入设置。
    @Published private(set) var pageCapacity = 35
    @Published var backgroundStyle: BackgroundStyle {
        didSet {
            Self.settingsDefaults.set(backgroundStyle.rawValue, forKey: Self.backgroundStyleKey)
        }
    }
    @Published private(set) var customBackgroundImage: NSImage?
    @Published private(set) var customBackgroundPath: String?

    var iconMetrics: IconMetrics {
        IconMetrics(side: CGFloat(iconSide))
    }

    func updatePageCapacity(_ capacity: Int) {
        let clamped = max(1, capacity)
        guard clamped != pageCapacity else { return }
        pageCapacity = clamped
        currentPage = min(currentPage, max(0, pageCount - 1))
        selectedTileID = nil
    }

    private static func snapIconSide(_ value: Double) -> Double {
        IconSizeChoice.allCases
            .min(by: { abs($0.side - value) < abs($1.side - value) })?
            .side ?? 70
    }

    private static let iconSideKey = "dashboard.iconSide"
    private static let legacyIconSizeKey = "dashboard.iconSize"
    private static let backgroundStyleKey = "dashboard.backgroundStyle"
    private static let customBackgroundPathKey = "dashboard.customBackgroundPath"

    private static var settingsDefaults: UserDefaults {
        if let suite = ProcessInfo.processInfo.environment["DASHBOARD_SETTINGS_SUITE"],
           !suite.isEmpty,
           let defaults = UserDefaults(suiteName: suite) {
            return defaults
        }
        return .standard
    }

    var onClose: (() -> Void)?

    private let store = LayoutStore()
    private var toastWorkItem: DispatchWorkItem?

    init() {
        let defaults = Self.settingsDefaults
        let loadedSide: Double
        if let savedSide = defaults.object(forKey: Self.iconSideKey) as? Double {
            loadedSide = min(max(savedSide, 64), 100)
        } else if let legacy = defaults.string(forKey: Self.legacyIconSizeKey) {
            loadedSide = legacy == "small" ? 64 : (legacy == "large" ? 90 : 70)
        } else {
            loadedSide = 70
        }
        iconSide = Self.snapIconSide(loadedSide)
        var savedStyle = defaults.string(forKey: Self.backgroundStyleKey)
            .flatMap(BackgroundStyle.init(rawValue:)) ?? .aurora
        if let path = defaults.string(forKey: Self.customBackgroundPathKey),
           let image = NSImage(contentsOfFile: path) {
            customBackgroundImage = image
            customBackgroundPath = path
        } else {
            customBackgroundImage = nil
            customBackgroundPath = nil
            if savedStyle == .custom { savedStyle = .aurora }
        }
        backgroundStyle = savedStyle

        layout = store.layout
    }

    var hasCustomBackground: Bool {
        customBackgroundImage != nil
    }

    func selectBackground(_ style: BackgroundStyle) {
        guard style != .custom || customBackgroundImage != nil else { return }
        backgroundStyle = style
    }

    /// 把用户选择的图片复制到 Application Support，之后即使原文件移走也能继续使用。
    func setCustomBackground(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else {
            showToast("无法读取这张图片")
            return
        }

        let directory = Self.backgroundDirectory
        if let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) {
            for file in files where file.lastPathComponent.hasPrefix("custom-background.") {
                try? FileManager.default.removeItem(at: file)
            }
        }

        let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension.lowercased()
        let destination = directory.appendingPathComponent("custom-background.\(ext)")
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            showToast("保存背景失败：\(error.localizedDescription)")
            return
        }

        customBackgroundImage = image
        customBackgroundPath = destination.path
        Self.settingsDefaults.set(destination.path, forKey: Self.customBackgroundPathKey)
        backgroundStyle = .custom
        showToast("背景已更新")
    }

    func clearCustomBackground() {
        if let customBackgroundPath {
            try? FileManager.default.removeItem(atPath: customBackgroundPath)
        }
        customBackgroundImage = nil
        customBackgroundPath = nil
        Self.settingsDefaults.removeObject(forKey: Self.customBackgroundPathKey)
        if backgroundStyle == .custom {
            backgroundStyle = .aurora
        }
    }

    private static var backgroundDirectory: URL {
        let manager = FileManager.default
        let directory: URL
        if let override = ProcessInfo.processInfo.environment["DASHBOARD_BACKGROUND_DIR"],
           !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory())
            directory = support
                .appendingPathComponent("DashboardReborn", isDirectory: true)
                .appendingPathComponent("Backgrounds", isDirectory: true)
        }
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - 读取 App 列表

    func clearSearch() {
        searchText = ""
        currentPage = 0
    }

    func clearSelection() {
        selectedTileID = nil
    }

    /// 每次打开面板 / 点刷新都会重新读取本机 App 列表，并合并进已有布局。
    func refresh() {
        isScanning = true
        let scanned = AppScanner.scan()
        var map: [String: AppInfo] = [:]
        for app in scanned { map[app.path] = app }
        apps = map

        var merged = layout
        merged = Self.merge(layout: merged, scanned: scanned)
        apply(merged)

        lastScanDate = Date()
        isScanning = false

        if let id = openedFolderID, folder(id: id) == nil {
            openedFolderID = nil
        }
        if let selected = selectedTileID,
           !visibleTiles.contains(where: { $0.id == selected }) {
            selectedTileID = nil
        }
        clampPage()
    }

    private static func merge(layout: DashboardLayout, scanned: [AppInfo]) -> DashboardLayout {
        let validPaths = Set(scanned.map(\.path))
        var result = layout

        var tiles: [Tile] = []
        var present = Set<String>()

        for tile in layout.tiles {
            switch tile {
            case .app(let path):
                guard validPaths.contains(path) else { continue }
                tiles.append(tile)
                present.insert(path)
            case .folder(var folder):
                folder.appPaths = folder.appPaths.filter { validPaths.contains($0) }
                guard !folder.appPaths.isEmpty else { continue }
                tiles.append(.folder(folder))
                present.formUnion(folder.appPaths)
            }
        }

        let newcomers = scanned.filter {
            !present.contains($0.path) && !layout.hidden.contains($0.path)
        }
        tiles.append(contentsOf: newcomers.map { .app($0.path) })
        result.tiles = tiles

        // 清理已经不存在的“已隐藏”记录。
        result.hidden = layout.hidden.intersection(validPaths)
        return result
    }

    // MARK: - 打开 App

    func launch(_ path: String) {
        guard !isEditing else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            showToast("App 已不存在，请刷新")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.showToast("打开失败：\(error.localizedDescription)")
                } else {
                    self.onClose?()
                }
            }
        }
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: - 编辑 / 分组

    func toggleEditing() {
        if !isEditing {
            searchText = ""
        }
        if isEditing {
            endEditing()
        } else {
            withAnimation(.snappy(duration: 0.25)) {
                isEditing = true
            }
        }
    }

    func endEditing() {
        withAnimation(.snappy(duration: 0.25)) {
            isEditing = false
            openedFolderID = nil
        }
    }

    /// 把一个 App 拖到另一个格子上：目标是 App 则合成文件夹，目标是文件夹则加入。
    func drop(path draggedPath: String, onto targetID: String) {
        guard let from = layout.tiles.firstIndex(where: { $0.id == "app:\(draggedPath)" }),
              let to = layout.tiles.firstIndex(where: { $0.id == targetID }),
              from != to else { return }

        var tiles = layout.tiles
        switch tiles[to] {
        case .app(let targetPath):
            let folder = Folder(name: "新建文件夹", appPaths: [targetPath, draggedPath])
            tiles[to] = .folder(folder)
            tiles.remove(at: from)
            showToast("已归入「新建文件夹」")
        case .folder(var folder):
            guard !folder.appPaths.contains(draggedPath) else { return }
            folder.appPaths.append(draggedPath)
            tiles[to] = .folder(folder)
            tiles.remove(at: from)
            showToast("已加入「\(folder.name)」")
        }

        var newLayout = layout
        newLayout.tiles = tiles
        apply(newLayout)
    }

    /// 拖动排序：insertionIndex 是在原数组中的插入位置（0...count）。
    func moveApp(path: String, to insertionIndex: Int) {
        guard let from = layout.tiles.firstIndex(of: .app(path)) else { return }

        var target = insertionIndex
        if from < target { target -= 1 }
        target = min(max(target, 0), layout.tiles.count - 1)
        guard target != from else { return }

        var tiles = layout.tiles
        let tile = tiles.remove(at: from)
        tiles.insert(tile, at: min(target, tiles.count))

        var newLayout = layout
        newLayout.tiles = tiles
        apply(newLayout)
    }

    func addToFolder(path: String, folderID: UUID) {
        guard let index = layout.tiles.firstIndex(where: { $0.folder?.id == folderID }),
              var folder = layout.tiles[index].folder,
              !folder.appPaths.contains(path) else { return }
        folder.appPaths.append(path)

        var tiles = layout.tiles
        tiles[index] = .folder(folder)
        if let appIndex = tiles.firstIndex(of: .app(path)) {
            tiles.remove(at: appIndex)
        }

        var newLayout = layout
        newLayout.tiles = tiles
        apply(newLayout)
        showToast("已加入「\(folder.name)」")
    }

    func removeFromFolder(folderID: UUID, path: String) {
        guard let index = layout.tiles.firstIndex(where: { $0.folder?.id == folderID }),
              var folder = layout.tiles[index].folder else { return }
        folder.appPaths.removeAll { $0 == path }

        var tiles = layout.tiles
        if folder.appPaths.isEmpty {
            tiles.remove(at: index)
        } else {
            tiles[index] = .folder(folder)
        }
        if !tiles.contains(.app(path)) {
            tiles.append(.app(path))
        }

        var newLayout = layout
        newLayout.tiles = tiles
        apply(newLayout)
    }

    func dissolveFolder(id: UUID) {
        guard let index = layout.tiles.firstIndex(where: { $0.folder?.id == id }),
              let folder = layout.tiles[index].folder else { return }

        var tiles = layout.tiles
        tiles.remove(at: index)
        tiles.insert(contentsOf: folder.appPaths.map { .app($0) }, at: index)

        var newLayout = layout
        newLayout.tiles = tiles
        apply(newLayout)

        if openedFolderID == id { openedFolderID = nil }
        showToast("已解散文件夹")
    }

    func renameFolder(id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = layout.tiles.firstIndex(where: { $0.folder?.id == id }),
              var folder = layout.tiles[index].folder else { return }
        folder.name = trimmed

        var tiles = layout.tiles
        tiles[index] = .folder(folder)
        var newLayout = layout
        newLayout.tiles = tiles
        apply(newLayout)
    }

    // MARK: - 删除

    /// 旧版 Dashboard 的删除是“从面板移除”，不会卸载 App。
    func removeFromDashboard(_ path: String) {
        var hidden = layout.hidden
        hidden.insert(path)

        var tiles: [Tile] = []
        for tile in layout.tiles {
            switch tile {
            case .app(let appPath):
                if appPath != path { tiles.append(tile) }
            case .folder(var folder):
                folder.appPaths.removeAll { $0 == path }
                if !folder.appPaths.isEmpty {
                    tiles.append(.folder(folder))
                } else if openedFolderID == folder.id {
                    openedFolderID = nil
                }
            }
        }

        var newLayout = layout
        newLayout.tiles = tiles
        newLayout.hidden = hidden
        apply(newLayout)
        showToast("已从 Dashboard 移除「\(displayName(path))」，不会卸载 App")
    }

    /// 真正把 App 移到废纸篓（会触发系统授权提示）。
    func moveToTrash(_ path: String) {
        guard !path.hasPrefix("/System/") else {
            showToast("系统 App 不能移到废纸篓")
            return
        }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.recycle([url]) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.showToast("移到废纸篓失败：\(error.localizedDescription)")
                } else {
                    self.removeFromDashboard(path)
                    self.showToast("已移到废纸篓「\(self.displayName(path))」")
                    self.refresh()
                }
            }
        }
    }

    // MARK: - 维护

    func restoreHiddenApps() {
        var newLayout = layout
        newLayout.hidden.removeAll()
        apply(newLayout)
        refresh()
        showToast("已恢复被移除的 App")
    }

    func resetLayout() {
        var newLayout = DashboardLayout()
        newLayout.hidden = []
        apply(newLayout)
        refresh()
        endEditing()
        showToast("已重置为默认布局")
    }

    // MARK: - 查询

    func folder(id: UUID) -> Folder? {
        layout.tiles.compactMap(\.folder).first { $0.id == id }
    }

    var openedFolder: Folder? {
        guard let id = openedFolderID else { return nil }
        return folder(id: id)
    }

    func app(at path: String) -> AppInfo? {
        apps[path]
    }

    func displayName(_ path: String) -> String {
        apps[path]?.name ?? (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var pageCount: Int {
        let count = visibleTiles.count
        guard count > 0 else { return 1 }
        return (count + pageCapacity - 1) / pageCapacity
    }

    func tiles(on page: Int) -> [Tile] {
        let all = visibleTiles
        let start = page * pageCapacity
        guard start >= 0, start < all.count else { return [] }
        let end = min(start + pageCapacity, all.count)
        return Array(all[start..<end])
    }

    func goToPage(_ page: Int) {
        currentPage = min(max(0, page), max(0, pageCount - 1))
        selectedTileID = nil
    }

    func nextPage() {
        goToPage(currentPage + 1)
    }

    func previousPage() {
        goToPage(currentPage - 1)
    }

    func clampPage() {
        currentPage = min(max(0, currentPage), max(0, pageCount - 1))
    }

    /// 当前 Tab 键遍历的范围：搜索时是搜索结果，否则是整个面板。
    var visibleTiles: [Tile] {
        if isSearching {
            return searchResults.map { .app($0.path) }
        }
        return layout.tiles
    }

    /// Tab / Shift+Tab：循环选择，最后一个之后回到第一个。
    func selectNext(forward: Bool) {
        let tiles = visibleTiles
        guard !tiles.isEmpty else {
            selectedTileID = nil
            return
        }
        let ids = tiles.map(\.id)
        guard let current = selectedTileID, let index = ids.firstIndex(of: current) else {
            selectedTileID = forward ? ids.first : ids.last
            return
        }
        let next = forward
            ? (index + 1) % ids.count
            : (index - 1 + ids.count) % ids.count
        selectedTileID = ids[next]
        currentPage = next / pageCapacity
    }

    /// Enter：打开当前选中的 App，或进入当前选中的文件夹。
    @discardableResult
    func activateSelection() -> Bool {
        guard !isEditing, openedFolderID == nil, let id = selectedTileID else { return false }
        guard let tile = visibleTiles.first(where: { $0.id == id }) else { return false }
        switch tile {
        case .app(let path):
            launch(path)
            return true
        case .folder(let folder):
            withAnimation(.snappy(duration: 0.22)) {
                openedFolderID = folder.id
            }
            return true
        }
    }

    /// 搜索时把所有（未隐藏的）App 平铺展示，忽略文件夹分组，便于快速定位。
    var searchResults: [AppInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return apps.values
            .filter { app in
                !layout.hidden.contains(app.path) && Self.matches(app, query: query)
            }
            .sorted { lhs, rhs in
                // 名称命中优先于 bundle id 命中，避免搜 "Google" 时中文名 App 排在前面。
                let lhsNameMatch = lhs.name.localizedCaseInsensitiveContains(query)
                let rhsNameMatch = rhs.name.localizedCaseInsensitiveContains(query)
                if lhsNameMatch != rhsNameMatch {
                    return lhsNameMatch
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private static func matches(_ app: AppInfo, query: String) -> Bool {
        if app.name.localizedCaseInsensitiveContains(query) { return true }
        if let bundleID = app.bundleID, bundleID.localizedCaseInsensitiveContains(query) { return true }
        return false
    }

    var visibleAppCount: Int {
        layout.tiles.reduce(into: 0) { partial, tile in
            partial += tile.appPaths.count
        }
    }

    // MARK: - 私有

    private func apply(_ newLayout: DashboardLayout) {
        layout = newLayout
        store.save(newLayout)
    }

    private func showToast(_ message: String) {
        toast = message
        toastWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.toast = nil
        }
        toastWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: item)
    }
}
