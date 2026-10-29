import SwiftUI

struct FolderOverlay: View {
    @ObservedObject var model: DashboardModel
    let folder: Folder
    var preview: Bool = false

    @State private var draftName: String = ""
    @State private var cardFrame: CGRect = .zero
    @State private var draggedPath: String?
    @State private var dragLocation: CGPoint = .zero
    @State private var isOutside = false

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 116), spacing: 14)]

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }

            VStack(spacing: 0) {
                header
                Divider().overlay(Color.white.opacity(0.10))
                content
                footer
            }
            .frame(width: 760, height: 540)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: FolderFramePreferenceKey.self,
                        value: proxy.frame(in: .named("folderOverlay"))
                    )
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color(red: 0.055, green: 0.070, blue: 0.105).opacity(0.96))
            }
            .modifier(GlassSurface(cornerRadius: 30, preview: preview))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.55), radius: 40, y: 18)
            .transition(.scale(scale: 0.96).combined(with: .opacity))

            if let draggedPath, let app = model.app(at: draggedPath) {
                ZStack {
                    Image(nsImage: IconProvider.shared.icon(for: app.path))
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 66, height: 66)
                        .shadow(color: .black.opacity(0.55), radius: 12, y: 7)
                        .scaleEffect(isOutside ? 1.06 : 1.0)

                    if isOutside {
                        Text("松手移出")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.72)))
                            .offset(y: 48)
                    }
                }
                .position(dragLocation)
                .allowsHitTesting(false)
                .zIndex(20)
            }
        }
        .coordinateSpace(name: "folderOverlay")
        .onPreferenceChange(FolderFramePreferenceKey.self) { cardFrame = $0 }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "folder.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 44, height: 44)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                }

            VStack(alignment: .leading, spacing: 3) {
                TextField("文件夹名称", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 420, alignment: .leading)
                    .onSubmit { commitRename() }
                    .onAppear { draftName = folder.name }
                    .onChange(of: folder.name) { _, newValue in draftName = newValue }
                    .onDisappear { commitRename() }

                Text("\(folder.appPaths.count) 个 App · 点击名称可重命名")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.52))
            }

            Spacer()

            CircleActionButton(
                systemName: model.isEditing ? "checkmark" : "pencil",
                help: model.isEditing ? "完成编辑" : "编辑文件夹"
            ) {
                model.toggleEditing()
            }

            CircleActionButton(systemName: "xmark", help: "关闭文件夹") {
                close()
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var content: some View {
        if folder.appPaths.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 36, weight: .light))
                Text("文件夹是空的")
                    .font(.system(size: 13))
            }
            .foregroundStyle(.white.opacity(0.45))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(folder.appPaths, id: \.self) { path in
                        if let app = model.app(at: path) {
                            FolderAppTile(
                                app: app,
                                isEditing: model.isEditing,
                                onOpen: { model.launch(path) },
                                onRemoveFromFolder: {
                                    model.removeFromFolder(folderID: folder.id, path: path)
                                },
                                onReveal: { model.revealInFinder(path) },
                                onRemoveFromDashboard: { model.removeFromDashboard(path) }
                            )
                            .modifier(JiggleModifier(
                                active: model.isEditing,
                                seed: Double(abs(path.hashValue % 6)) * 0.18
                            ))
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 1.0).onEnded { _ in
                                    NSHapticFeedbackManager.defaultPerformer.perform(
                                        .alignment,
                                        performanceTime: .now
                                    )
                                    model.isEditing = true
                                }
                            )
                            .simultaneousGesture(folderDragGesture(path))
                        }
                    }
                }
                .padding(24)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isEditing ? "hand.draw" : "cursorarrow.click")
            Text(model.isEditing
                 ? "点 × 或拖到面板外移出；右键可“从面板移除”"
                 : "点击打开 App · 拖到面板外可移出")
            Spacer()
            if model.isEditing {
                Text("编辑中")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.55))
        .padding(.horizontal, 24)
        .padding(.vertical, 13)
    }

    private func folderDragGesture(_ path: String) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("folderOverlay"))
            .onChanged { value in
                if draggedPath == nil {
                    withAnimation(.snappy(duration: 0.1)) {
                        draggedPath = path
                    }
                }
                dragLocation = value.location
                isOutside = isOutsideCard(value.location)
            }
            .onEnded { value in
                let outside = isOutsideCard(value.location)
                withAnimation(.snappy(duration: 0.14)) {
                    draggedPath = nil
                    isOutside = false
                }
                if outside {
                    model.removeFromFolder(folderID: folder.id, path: path)
                }
            }
    }

    private func isOutsideCard(_ point: CGPoint) -> Bool {
        cardFrame != .zero && !cardFrame.contains(point)
    }

    private func commitRename() {
        model.renameFolder(id: folder.id, name: draftName)
    }

    private func close() {
        withAnimation(.snappy(duration: 0.2)) {
            model.openedFolderID = nil
        }
    }
}

private struct FolderAppTile: View {
    let app: AppInfo
    let isEditing: Bool
    let onOpen: () -> Void
    let onRemoveFromFolder: () -> Void
    let onReveal: () -> Void
    let onRemoveFromDashboard: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .topLeading) {
                Image(nsImage: IconProvider.shared.icon(for: app.path))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.4), radius: 7, y: 4)

                if isEditing {
                    Button(action: onRemoveFromFolder) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 19, height: 19)
                            .background(Circle().fill(Color.black.opacity(0.72)))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .offset(x: -8, y: -8)
                    .help("移出文件夹")
                }
            }
            .frame(width: 78, height: 78)

            Text(app.name)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 96)
        }
        .frame(width: 104)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing { onOpen() }
        }
        .contextMenu {
            Button("打开") { onOpen() }
            Button("移出文件夹") { onRemoveFromFolder() }
            Button("在访达中显示") { onReveal() }
            Divider()
            Button("从面板移除", role: .destructive) { onRemoveFromDashboard() }
        }
    }
}


private struct FolderFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
