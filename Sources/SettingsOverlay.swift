import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsOverlay: View {
    @ObservedObject var model: DashboardModel
    var preview: Bool = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }

            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 42, height: 42)
                        .background {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("设置")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("调整图标和背景")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Spacer()

                    settingsCloseButton
                }

                settingRow(
                    title: "图标大小",
                    subtitle: "选一档"
                ) {
                    HStack(spacing: 10) {
                        ForEach(IconSizeChoice.allCases) { choice in
                            iconSizeOption(choice)
                        }
                    }
                }

                settingRow(
                    title: "背景",
                    subtitle: "内置或自选图片"
                ) {
                    HStack(spacing: 8) {
                        ForEach(BackgroundStyle.presets) { style in
                            presetSwatch(style)
                        }
                        customSwatch
                    }
                }

                HStack(spacing: 10) {
                    Text(model.hasCustomBackground ? "自定义图片已保存" : "支持 PNG / JPG / HEIC")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.42))

                    Spacer()

                    pillButton(title: "选择图片…", systemImage: "photo") {
                        chooseBackgroundImage()
                    }

                    if model.hasCustomBackground {
                        pillButton(title: "移除", systemImage: "trash", subtle: true) {
                            model.clearCustomBackground()
                        }
                    }
                }

                if !model.layout.hidden.isEmpty {
                    HStack(spacing: 10) {
                        Text("已从面板移除 \(model.layout.hidden.count) 个 App")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.50))
                        Spacer()
                        pillButton(title: "全部恢复", systemImage: "arrow.uturn.backward") {
                            model.restoreHiddenApps()
                        }
                    }
                }

                Spacer(minLength: 16)

                Divider()
                    .overlay(Color.white.opacity(0.08))

                HStack(alignment: .center, spacing: 10) {
                    Text("共 \(model.pageCount) 页 · 每页 \(model.pageCapacity) 个 · 随图标大小自动调整")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))

                    Spacer()

                    Text("点击空白处或右上角 × 关闭")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.32))
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 28)
            .frame(width: 740)
            .frame(height: cardHeight)
            .background {
                // 玻璃材质在部分离屏/旧环境里会显得透明，叠一层深色底保证可读性。
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(red: 0.055, green: 0.070, blue: 0.105).opacity(0.97))
            }
            .modifier(GlassSurface(cornerRadius: 28, preview: preview))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.55), radius: 40, y: 18)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    private var cardHeight: CGFloat {
        model.layout.hidden.isEmpty ? 520 : 590
    }

    private func iconSizeOption(_ choice: IconSizeChoice) -> some View {
        let selected = abs(model.iconSide - choice.side) < 0.5
        return Button {
            model.iconSide = choice.side
        } label: {
            Text(choice.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(selected ? 0.98 : 0.58))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(selected ? 0.20 : 0.07))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(selected ? 0.26 : 0.10),
                            lineWidth: selected ? 1.4 : 0.8
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(Int(choice.side))pt")
    }

    private var settingsCloseButton: some View {
        Button {
            close()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 36, height: 36)
                .background { Circle().fill(Color.white.opacity(0.10)) }
                .overlay { Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8) }
        }
        .buttonStyle(.plain)
        .help("关闭设置")
    }

    private func pillButton(
        title: String,
        systemImage: String,
        subtle: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(subtle ? 0.65 : 0.88))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background { Capsule().fill(Color.white.opacity(subtle ? 0.06 : 0.10)) }
            .overlay { Capsule().strokeBorder(Color.white.opacity(subtle ? 0.08 : 0.14), lineWidth: 0.8) }
        }
        .buttonStyle(.plain)
    }

    private func presetSwatch(_ style: BackgroundStyle) -> some View {
        Button {
            model.selectBackground(style)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    BackgroundSwatchFill(style: style, image: nil)
                        .frame(width: 84, height: 52)

                    if model.backgroundStyle == style {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white, lineWidth: 2)
                            .frame(width: 84, height: 52)
                    }
                }
                .frame(width: 84, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(style.title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(model.backgroundStyle == style ? 0.95 : 0.55))
            }
            .frame(width: 86)
        }
        .buttonStyle(.plain)
    }

    private var customSwatch: some View {
        Button {
            if model.backgroundStyle == .custom || !model.hasCustomBackground {
                chooseBackgroundImage()
            } else {
                model.selectBackground(.custom)
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if let image = model.customBackgroundImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 84, height: 52)
                    } else {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 84, height: 52)
                        Image(systemName: "photo")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.60))
                    }

                    if model.backgroundStyle == .custom {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white, lineWidth: 2)
                            .frame(width: 84, height: 52)
                    }
                }
                .frame(width: 84, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text("图片")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(model.backgroundStyle == .custom ? 0.95 : 0.55))
            }
            .frame(width: 86)
        }
        .buttonStyle(.plain)
        .help(model.hasCustomBackground ? "点击切换或更换图片" : "选择一张图片")
    }

    private func chooseBackgroundImage() {
        let host = NSApp.keyWindow ?? NSApp.windows.first {
            $0.isVisible && !($0 is NSOpenPanel)
        }
        BackgroundImagePicker.present(host: host) { url in
            guard let url else { return }
            model.setCustomBackground(from: url)
        }
    }

    private func settingRow<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            content()
        }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.18)) {
            model.isShowingSettings = false
        }
    }
}


private struct BackgroundSwatchFill: View {
    let style: BackgroundStyle
    let image: NSImage?

    var body: some View {
        switch style {
        case .aurora:
            LinearGradient(
                colors: [
                    Color(red: 0.45, green: 0.12, blue: 0.52),
                    Color(red: 0.18, green: 0.16, blue: 0.58),
                    Color(red: 0.55, green: 0.16, blue: 0.40)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .midnight:
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.07, blue: 0.14),
                        Color(red: 0.12, green: 0.16, blue: 0.28)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 2, height: 2)
                    .offset(x: -18, y: -10)
                Circle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 1.5, height: 1.5)
                    .offset(x: 14, y: 6)
            }
        case .ocean:
            Color(red: 0.055, green: 0.105, blue: 0.195)
        case .violet:
            Color(red: 0.160, green: 0.070, blue: 0.245)
        case .graphite:
            Color(red: 0.115, green: 0.120, blue: 0.140)
        case .rose:
            Color(red: 0.235, green: 0.080, blue: 0.145)
        case .custom:
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.08)
            }
        }
    }
}
