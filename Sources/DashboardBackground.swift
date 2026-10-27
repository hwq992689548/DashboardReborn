import AppKit
import SwiftUI

/// 背景：内置极光 / 午夜星空 / 纯色，或用户选择的图片。
struct DashboardBackground: View {
    let style: BackgroundStyle
    let customImage: NSImage?

    var body: some View {
        ZStack {
            switch style {
            case .aurora:
                AuroraBackground()
            case .midnight:
                MidnightBackground()
            case .ocean:
                Color(red: 0.055, green: 0.105, blue: 0.195)
            case .violet:
                Color(red: 0.160, green: 0.070, blue: 0.245)
            case .graphite:
                Color(red: 0.115, green: 0.120, blue: 0.140)
            case .rose:
                Color(red: 0.235, green: 0.080, blue: 0.145)
            case .custom:
                if let customImage {
                    CustomImageBackground(image: customImage)
                } else {
                    AuroraBackground()
                }
            }

            // 自定义图片和纯色背景需要一层压暗，保证白色文字可读。
            if style == .custom {
                Color.black.opacity(0.34)
            } else if style != .aurora && style != .midnight {
                Color.black.opacity(0.16)
            }

            LinearGradient(
                colors: [Color.black.opacity(0.10), .clear, Color.black.opacity(0.24)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct AuroraBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.145, green: 0.055, blue: 0.225),
                    Color(red: 0.235, green: 0.075, blue: 0.330),
                    Color(red: 0.045, green: 0.065, blue: 0.180)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color(red: 0.72, green: 0.17, blue: 0.55).opacity(0.50), .clear],
                center: UnitPoint(x: 0.10, y: 0.06),
                startRadius: 0,
                endRadius: 900
            )

            RadialGradient(
                colors: [Color(red: 0.36, green: 0.22, blue: 0.88).opacity(0.38), .clear],
                center: UnitPoint(x: 0.55, y: 0.45),
                startRadius: 0,
                endRadius: 980
            )

            RadialGradient(
                colors: [Color(red: 0.95, green: 0.33, blue: 0.62).opacity(0.26), .clear],
                center: UnitPoint(x: 0.94, y: 0.96),
                startRadius: 0,
                endRadius: 820
            )
        }
    }
}

/// 原来的深色星空背景。
private struct MidnightBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.045, blue: 0.075),
                    Color(red: 0.070, green: 0.085, blue: 0.140),
                    Color(red: 0.025, green: 0.030, blue: 0.055)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color(red: 0.20, green: 0.38, blue: 0.85).opacity(0.40), .clear],
                center: UnitPoint(x: 0.16, y: 0.04),
                startRadius: 0,
                endRadius: 820
            )

            RadialGradient(
                colors: [Color(red: 0.48, green: 0.20, blue: 0.62).opacity(0.30), .clear],
                center: UnitPoint(x: 0.88, y: 0.92),
                startRadius: 0,
                endRadius: 760
            )

            Starfield()
        }
    }
}

private struct CustomImageBackground: View {
    let image: NSImage

    var body: some View {
        GeometryReader { geometry in
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
    }
}

private struct Starfield: View {
    var body: some View {
        Canvas { context, size in
            var generator = SeededGenerator(seed: 0x0D45_B0A2)
            for _ in 0..<170 {
                let x = Double.random(in: 0...max(size.width, 1), using: &generator)
                let y = Double.random(in: 0...max(size.height, 1), using: &generator)
                let radius = Double.random(in: 0.4...1.5, using: &generator)
                let alpha = Double.random(in: 0.05...0.32, using: &generator)
                let rect = CGRect(x: x, y: y, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
