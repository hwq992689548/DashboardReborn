import SwiftUI

/// 统一的“液态玻璃”容器：macOS 26 用原生 Liquid Glass，低版本退回材质。
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 24
    var preview: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if preview {
            content.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    }
            }
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    }
            }
        }
    }
}

struct CircleActionButton: View {
    let systemName: String
    var help: String = ""
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(Color.white.opacity(prominent ? 0.18 : 0.09))
                }
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
