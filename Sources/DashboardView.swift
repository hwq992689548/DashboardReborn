import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    var preview: Bool = false
    let onClose: () -> Void

    @State private var tileFrames: [String: CGRect] = [:]
    @State private var dragPath: String?
    @State private var dragLocation: CGPoint = .zero
    @State private var dropTargetID: String?
    @State private var reorderIndex: Int?
    @State private var insertionLine: DropLine?

    var body: some View {
        ZStack {
            DashboardBackground(style: model.backgroundStyle, customImage: model.customBackgroundImage)

            VStack(spacing: 0) {
                topBar
                pager
                bottomDots
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let folder = model.openedFolder {
                FolderOverlay(model: model, folder: folder, preview: preview)
                    .zIndex(2)
            }

            if model.isShowingSettings {
                SettingsOverlay(model: model, preview: preview)
                    .zIndex(4)
            }

            if let toast = model.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .modifier(GlassSurface(cornerRadius: 16, preview: preview))
                        .padding(.bottom, 64)
                }
                .allowsHitTesting(false)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .coordinateSpace(name: "dashboard")
        .preferredColorScheme(.dark)
        .animation(.snappy(duration: 0.24), value: model.openedFolderID)
        .animation(.snappy(duration: 0.2), value: model.toast)
        .onPreferenceChange(TileFramePreferenceKey.self) { tileFrames = $0 }
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                if let line = insertionLine {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.white.opacity(0.96))
                        .frame(width: 3, height: line.height)
                        .offset(x: line.x - 1.5, y: line.y)
                        .shadow(color: Color.black.opacity(0.4), radius: 3)
                        .allowsHitTesting(false)
                }
                dragPreview
            }
        }
        .onExitCommand(perform: handleEscape)
    }

    // MARK: - 顶栏（参考旧版 Launchpad：只有居中搜索框）

    private var topBar: some View {
        ZStack {
            searchField
                .frame(width: 620)

            HStack(spacing: 8) {
                if model.isEditing {
                    Text("编辑模式 · 拖动排序 / 分组")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                        .overlay {
                            Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                        }
                }

                Spacer()

                HStack(spacing: 8) {
                    CircleActionButton(systemName: "gearshape", help: "设置") {
                        model.isShowingSettings = true
                    }
                    CircleActionButton(systemName: "arrow.clockwise", help: "重新读取 App 列表") {
                        model.refresh()
                    }
                    CircleActionButton(
                        systemName: model.isEditing ? "checkmark" : "slider.horizontal.3",
                        help: model.isEditing ? "完成编辑" : "编辑面板（长按图标也可以）",
                        prominent: model.isEditing
                    ) {
                        model.toggleEditing()
                    }
                    CircleActionButton(systemName: "xmark", help: "关闭 Dashboard（Esc）") {
                        onClose()
                    }
                }
                .opacity(0.9)
            }
        }
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: handleBackgroundTap)
        }
        .padding(.horizontal, 24)
        .padding(.top, topSafeInset)
        .padding(.bottom, 8)
    }

    /// 刘海屏 / 菜单栏的安全区高度；至少留 38pt，避免搜索框被压住。
    private var topSafeInset: CGFloat {
        let notch = NSScreen.main?.safeAreaInsets.top ?? 0
        return max(38, notch + 14)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))

            TextField("搜索", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .onSubmit { openFirstSearchResult() }

            if !model.searchText.isEmpty {
                Button {
                    model.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.58))
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
        .background {
            Capsule().fill(Color.white.opacity(0.12))
        }
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 5)
    }

    @ViewBuilder
    private var bottomDots: some View {
        if model.pageCount > 1 {
            HStack(spacing: 9) {
                ForEach(0..<model.pageCount, id: \.self) { index in
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            model.goToPage(index)
                        }
                    } label: {
                        Circle()
                            .fill(Color.white.opacity(index == model.currentPage ? 0.95 : 0.28))
                            .frame(
                                width: index == model.currentPage ? 9 : 6,
                                height: index == model.currentPage ? 9 : 6
                            )
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("第 \(index + 1) 页")
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 30)
        } else {
            Color.clear.frame(height: 14)
        }
    }

    // MARK: - 分页

    private var pager: some View {
        Group {
            if preview {
                previewPage
            } else {
                GeometryReader { geometry in
                    let capacity = autoPageCapacity(for: geometry.size)

                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(0..<model.pageCount, id: \.self) { page in
                                pageView(page, height: geometry.size.height)
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .id(page)
                            }
                        }
                        .scrollTargetLayout()
                        .background(ScrollIndicatorHider())
                    }
                    .scrollIndicators(.never)
                    .modifier(PageSnapBehavior())
                    .scrollPosition(id: pageBinding)
                    .onAppear { model.updatePageCapacity(capacity) }
                    .onChange(of: capacity) { _, newValue in
                        model.updatePageCapacity(newValue)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }

    private var gridTopPadding: CGFloat {
        24 + model.iconMetrics.side * 0.5
    }

    /// 根据页面可用高度和当前图标尺寸计算每页能放多少个。
    private func autoPageCapacity(for size: CGSize) -> Int {
        let metrics = model.iconMetrics
        let availableHeight = max(0, size.height - gridTopPadding - 8)
        let tileHeight = metrics.iconFrame + 36
        let spacing = metrics.rowSpacing
        let rows = max(1, Int(floor((availableHeight + spacing) / (tileHeight + spacing))))
        return max(metrics.columns, metrics.columns * rows)
    }

    private func pageView(_ page: Int, height: CGFloat) -> some View {
        let tiles = model.tiles(on: page)

        return ScrollView(.vertical) {
            ZStack(alignment: .top) {
                // 点击空白背景收起 Dashboard；编辑模式下先退出编辑。
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: handleBackgroundTap)

                VStack(spacing: 0) {
                    if tiles.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: model.iconMetrics.rowSpacing) {
                            ForEach(tiles) { tile in
                                tileView(tile)
                                    .id(tile.id)
                            }
                        }
                        .frame(maxWidth: model.iconMetrics.gridMaxWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, gridTopPadding)
                        .padding(.bottom, 8)
                    }
                }
                .frame(minHeight: height, alignment: .top)
            }
            .frame(minHeight: height)
            .background(ScrollIndicatorHider())
        }
        .scrollIndicators(.never)
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 18),
            count: max(1, model.iconMetrics.columns)
        )
    }

    private var pageBinding: Binding<Int?> {
        Binding(
            get: { model.currentPage },
            set: { newValue in
                guard let newValue else { return }
                let clamped = min(max(0, newValue), max(0, model.pageCount - 1))
                if clamped != model.currentPage {
                    model.currentPage = clamped
                    // 手动滑动翻页时取消旧页的选中状态，避免 Tab 跳回上一页。
                    DispatchQueue.main.async {
                        if model.currentPage == clamped {
                            model.selectedTileID = nil
                        }
                    }
                }
            }
        )
    }

    // MARK: - 预览（ImageRenderer 不支持懒加载和横向分页）

    private var previewPage: some View {
        let tiles = Array(model.tiles(on: 0))
        let perRow = max(1, model.iconMetrics.columns)
        var rows: [[Tile]] = []
        var index = 0
        while index < tiles.count {
            let end = min(index + perRow, tiles.count)
            rows.append(Array(tiles[index..<end]))
            index = end
        }

        return VStack(spacing: 18) {
            if tiles.isEmpty {
                emptyState
            } else {
                ForEach(rows.indices, id: \.self) { rowIndex in
                    HStack(spacing: 16) {
                        ForEach(rows[rowIndex]) { tile in
                            tileView(tile)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, gridTopPadding)
    }

    // MARK: - 图标格

    @ViewBuilder
    private func tileView(_ tile: Tile) -> some View {
        switch tile {
        case .app(let path):
            if let app = model.app(at: path) {
                let base = AppTileView(
                    app: app,
                    isEditing: model.isEditing,
                    jiggleSeed: jiggleSeed(for: tile.id),
                    isSelected: model.selectedTileID == tile.id,
                    metrics: model.iconMetrics,
                    onOpen: { model.launch(path) },
                    onEnterEdit: { model.toggleEditing() },
                    onRemove: { model.removeFromDashboard(path) },
                    onTrash: { model.moveToTrash(path) },
                    onReveal: { model.revealInFinder(path) }
                )

                base
                    .modifier(TileFrameReader(id: tile.id))
                    .overlay { dropHighlight(for: tile.id) }
                    .simultaneousGesture(dragGesture(for: tile, path: path))
            }

        case .folder(let folder):
            FolderTileView(
                folder: folder,
                apps: model.apps,
                isEditing: model.isEditing,
                jiggleSeed: jiggleSeed(for: tile.id),
                isSelected: model.selectedTileID == tile.id,
                metrics: model.iconMetrics,
                onOpen: {
                    withAnimation(.snappy(duration: 0.22)) {
                        model.openedFolderID = folder.id
                    }
                },
                onEnterEdit: { model.toggleEditing() },
                onDissolve: { model.dissolveFolder(id: folder.id) }
            )
            .modifier(TileFrameReader(id: tile.id))
            .overlay { dropHighlight(for: tile.id) }
        }
    }

    @ViewBuilder
    private func dropHighlight(for id: String) -> some View {
        if dropTargetID == id {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(red: 0.55, green: 0.76, blue: 1.0), lineWidth: 2.2)
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(red: 0.35, green: 0.55, blue: 1.0).opacity(0.14))
                }
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func dragGesture(for tile: Tile, path: String) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("dashboard"))
            .onChanged { value in
                guard model.isEditing else { return }
                if dragPath == nil {
                    withAnimation(.snappy(duration: 0.12)) {
                        dragPath = path
                    }
                }
                dragLocation = value.location
                updateDropTarget(at: value.location, source: tile)
            }
            .onEnded { value in
                guard model.isEditing else { return }
                updateDropTarget(at: value.location, source: tile)

                let source = dragPath
                let groupTarget = dropTargetID
                let index = reorderIndex

                withAnimation(.snappy(duration: 0.14)) {
                    dragPath = nil
                    dropTargetID = nil
                    reorderIndex = nil
                    insertionLine = nil
                }

                guard let source else { return }
                if let groupTarget {
                    model.drop(path: source, onto: groupTarget)
                } else if let index {
                    let globalIndex = model.currentPage * model.pageCapacity + index
                    withAnimation(.snappy(duration: 0.2)) {
                        model.moveApp(path: source, to: globalIndex)
                    }
                }
            }
    }

    private func updateDropTarget(at point: CGPoint, source: Tile) {
        let pageTiles = model.tiles(on: model.currentPage)
        guard !pageTiles.isEmpty else {
            clearDropTarget()
            return
        }

        var groupID: String?
        var index: Int?

        // 悬停在图标中心 = 分组；悬停在图标左右边缘 = 插入排序。
        for (tileIndex, pageTile) in pageTiles.enumerated() {
            guard pageTile.id != source.id,
                  let frame = tileFrames[pageTile.id],
                  frame.contains(point) else { continue }

            if pageTile.folder != nil {
                groupID = pageTile.id
            } else {
                let relativeX = (point.x - frame.minX) / max(frame.width, 1)
                if relativeX < 0.24 {
                    index = tileIndex
                } else if relativeX > 0.76 {
                    index = tileIndex + 1
                } else {
                    groupID = pageTile.id
                }
            }
            break
        }

        // 空白区域：插到最近的图标前/后；下方空白直接放到本页末尾。
        if groupID == nil && index == nil {
            if let last = pageTiles.last,
               let lastFrame = tileFrames[last.id],
               point.y > lastFrame.maxY {
                index = pageTiles.count
            } else if let first = pageTiles.first,
                      let firstFrame = tileFrames[first.id],
                      point.y < firstFrame.minY {
                index = 0
            } else {
                var nearest: (index: Int, frame: CGRect, distance: CGFloat)?
                for (tileIndex, pageTile) in pageTiles.enumerated() where pageTile.id != source.id {
                    guard let frame = tileFrames[pageTile.id] else { continue }
                    let distance = hypot(point.x - frame.midX, point.y - frame.midY)
                    if nearest == nil || distance < nearest!.distance {
                        nearest = (tileIndex, frame, distance)
                    }
                }
                if let nearest {
                    index = point.x < nearest.frame.midX ? nearest.index : nearest.index + 1
                }
            }
        }

        let line = index.flatMap { makeInsertionLine(at: $0, pageTiles: pageTiles) }

        if groupID != dropTargetID || index != reorderIndex || line != insertionLine {
            withAnimation(.snappy(duration: 0.1)) {
                dropTargetID = groupID
                reorderIndex = index
                insertionLine = line
            }
        }
    }

    private func makeInsertionLine(at index: Int, pageTiles: [Tile]) -> DropLine? {
        let clamped = min(max(index, 0), pageTiles.count)
        if clamped < pageTiles.count,
           let frame = tileFrames[pageTiles[clamped].id] {
            return DropLine(x: frame.minX - 8, y: frame.minY, height: frame.height)
        }
        if let last = pageTiles.last,
           let frame = tileFrames[last.id] {
            return DropLine(x: frame.maxX + 8, y: frame.minY, height: frame.height)
        }
        return nil
    }

    private func clearDropTarget() {
        if dropTargetID != nil || reorderIndex != nil || insertionLine != nil {
            withAnimation(.snappy(duration: 0.1)) {
                dropTargetID = nil
                reorderIndex = nil
                insertionLine = nil
            }
        }
    }

    @ViewBuilder
    private var dragPreview: some View {
        if let dragPath, let app = model.app(at: dragPath) {
            Image(nsImage: IconProvider.shared.icon(for: app.path))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 68, height: 68)
                .shadow(color: .black.opacity(0.5), radius: 10, y: 6)
                .offset(x: dragLocation.x - 34, y: dragLocation.y - 34)
                .allowsHitTesting(false)
                .transition(.scale(scale: 1.08).combined(with: .opacity))
        }
    }

    // MARK: - 空状态 / 底栏

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: model.isSearching ? "magnifyingglass" : "square.grid.2x2")
                .font(.system(size: 42, weight: .light))
            Text(model.isSearching ? "没有匹配的 App" : "还没有可显示的 App")
                .font(.system(size: 16, weight: .medium))
            Text(model.isSearching ? "换个关键词，或清除搜索" : "点击右上角刷新，或检查 /Applications 是否可读")
                .font(.system(size: 12))
            Button(model.isSearching ? "清除搜索" : "重新读取 App 列表") {
                if model.isSearching {
                    model.clearSearch()
                } else {
                    model.refresh()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.14)))
            .padding(.top, 4)
        }
        .foregroundStyle(.white.opacity(0.6))
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    private func jiggleSeed(for id: String) -> Double {
        Double(abs(id.hashValue % 6)) * 0.18
    }

    private func openFirstSearchResult() {
        guard let first = model.searchResults.first else { return }
        model.launch(first.path)
    }

    private func handleBackgroundTap() {
        if model.isShowingSettings {
            model.isShowingSettings = false
        } else if model.openedFolderID != nil {
            withAnimation(.snappy(duration: 0.2)) {
                model.openedFolderID = nil
            }
        } else if model.isEditing {
            model.endEditing()
        } else {
            onClose()
        }
    }

    private func handleEscape() {
        if model.isShowingSettings {
            model.isShowingSettings = false
            return
        }
        if !model.searchText.isEmpty {
            model.clearSearch()
            return
        }
        if model.openedFolderID != nil {
            withAnimation(.snappy(duration: 0.2)) {
                model.openedFolderID = nil
            }
        } else if model.isEditing {
            model.endEditing()
        } else {
            onClose()
        }
    }

    private struct ScrollIndicatorHider: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async { hideScrollbars(from: view) }
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            DispatchQueue.main.async { hideScrollbars(from: nsView) }
        }

        private func hideScrollbars(from view: NSView) {
            var current: NSView? = view
            while let candidate = current {
                if let scrollView = candidate as? NSScrollView {
                    scrollView.hasHorizontalScroller = false
                    scrollView.hasVerticalScroller = false
                }
                current = candidate.superview
            }
        }
    }

    private struct PageSnapBehavior: ViewModifier {
        func body(content: Content) -> some View {
            if #available(macOS 15.0, *) {
                // 系统分页吸附：一次手势最多一页，滑动手感跟手。
                content.scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            } else {
                content.scrollTargetBehavior(.paging)
            }
        }
    }

    private struct DropLine: Equatable {
        let x: CGFloat
        let y: CGFloat
        let height: CGFloat
    }

    private struct TileFramePreferenceKey: PreferenceKey {
        static var defaultValue: [String: CGRect] = [:]
        static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
    }

    private struct TileFrameReader: ViewModifier {
        let id: String

        func body(content: Content) -> some View {
            content.background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TileFramePreferenceKey.self,
                        value: [id: proxy.frame(in: .named("dashboard"))]
                    )
                }
            }
        }
    }
}
