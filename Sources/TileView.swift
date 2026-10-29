import SwiftUI

struct AppTileView: View {
    let app: AppInfo
    let isEditing: Bool
    let jiggleSeed: Double
    var isSelected: Bool = false
    var metrics: IconMetrics = IconMetrics(side: 70)
    let onOpen: () -> Void
    let onEnterEdit: () -> Void
    let onRemove: () -> Void
    let onTrash: () -> Void
    let onReveal: () -> Void

    @State private var showTrashConfirm = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                Image(nsImage: IconProvider.shared.icon(for: app.path))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: metrics.side, height: metrics.side)
                    .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 7)

                if isEditing {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 21, height: 21)
                            .background(Circle().fill(Color.black.opacity(0.72)))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .offset(x: -9, y: -9)
                    .help("从面板移除（不会卸载）")
                }
            }
            .frame(width: metrics.iconFrame, height: metrics.iconFrame)

            Text(app.name)
                .font(.system(size: metrics.labelFont, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: metrics.labelWidth)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
        .frame(width: metrics.tileWidth)
        .padding(.vertical, 6)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(red: 0.50, green: 0.75, blue: 1.0), lineWidth: 2.4)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(red: 0.35, green: 0.55, blue: 1.0).opacity(0.10))
                    }
                    .shadow(color: Color(red: 0.30, green: 0.55, blue: 1.0).opacity(0.45), radius: 8)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing { onOpen() }
        }
        .onLongPressGesture(minimumDuration: 1.0) {
            if !isEditing { onEnterEdit() }
        }
        .modifier(JiggleModifier(active: isEditing, seed: jiggleSeed))
        .contextMenu {
            Button("打开") { onOpen() }
            Button("在访达中显示") { onReveal() }
            Divider()
            if isEditing {
                Button("从面板移除") { onRemove() }
            } else {
                Button("编辑面板") { onEnterEdit() }
            }
            if !app.path.hasPrefix("/System/") {
                Button("移到废纸篓…", role: .destructive) { showTrashConfirm = true }
            }
        }
        .confirmationDialog(
            "把「\(app.name)」移到废纸篓？",
            isPresented: $showTrashConfirm,
            titleVisibility: .visible
        ) {
            Button("移到废纸篓", role: .destructive) { onTrash() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会真正移除 App（之后可从废纸篓恢复）。")
        }
    }
}

struct FolderTileView: View {
    let folder: Folder
    let apps: [String: AppInfo]
    let isEditing: Bool
    let jiggleSeed: Double
    var isSelected: Bool = false
    var metrics: IconMetrics = IconMetrics(side: 70)
    let onOpen: () -> Void
    let onEnterEdit: () -> Void
    let onDissolve: () -> Void

    private var previewPaths: [String] {
        Array(folder.appPaths.prefix(9))
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    }
                    .frame(width: metrics.side, height: metrics.side)

                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(metrics.folderMini), spacing: 3),
                        count: 3
                    ),
                    spacing: 3
                ) {
                    ForEach(previewPaths, id: \.self) { path in
                        Image(nsImage: IconProvider.shared.icon(for: path))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: metrics.folderMini, height: metrics.folderMini)
                    }
                }
                .frame(width: metrics.folderInner, height: metrics.folderInner)
                .offset(x: metrics.folderInset, y: metrics.folderInset)

                if isEditing {
                    Button(action: onDissolve) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 21, height: 21)
                            .background(Circle().fill(Color.black.opacity(0.72)))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .offset(x: -9, y: -9)
                    .help("解散文件夹")
                }
            }
            .frame(width: metrics.iconFrame, height: metrics.iconFrame)

            Text(folder.name)
                .font(.system(size: metrics.labelFont, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: metrics.labelWidth)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
        .frame(width: metrics.tileWidth)
        .padding(.vertical, 6)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(red: 0.50, green: 0.75, blue: 1.0), lineWidth: 2.4)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(red: 0.35, green: 0.55, blue: 1.0).opacity(0.10))
                    }
                    .shadow(color: Color(red: 0.30, green: 0.55, blue: 1.0).opacity(0.45), radius: 8)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
        .onLongPressGesture(minimumDuration: 1.0) {
            if !isEditing { onEnterEdit() }
        }
        .modifier(JiggleModifier(active: isEditing, seed: jiggleSeed))
        .contextMenu {
            Button("打开") { onOpen() }
            Divider()
            Button("解散文件夹", role: .destructive) { onDissolve() }
        }
    }
}

/// 编辑模式下图标轻微抖动，接近旧版 Dashboard / Launchpad 的观感。
struct JiggleModifier: ViewModifier {
    let active: Bool
    let seed: Double

    func body(content: Content) -> some View {
        if active {
            content.phaseAnimator([-1.0, 1.0]) { view, phase in
                view
                    .rotationEffect(.degrees(phase * 0.7))
                    .offset(y: phase * 0.8)
            } animation: { _ in
                .easeInOut(duration: 0.13 + seed * 0.035)
            }
        } else {
            content
        }
    }
}
