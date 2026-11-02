import AppKit
import SwiftUI

enum LocalShotTheme {
    static let accent = dynamicColor(light: 0x8A5CF6, dark: 0xA78BFA)
    static let base = dynamicColor(light: 0xFCFBFF, dark: 0x191823)
    static let glowRose = dynamicColor(light: 0xF8DCE0, dark: 0x3D2034)
    static let glowViolet = dynamicColor(light: 0xE3DAFD, dark: 0x2C2456)
    static let card = dynamicColor(light: 0xFFFFFF, dark: 0x252433)
    static let cardStroke = dynamicColor(light: 0xECE9F4, dark: 0x393750)
    static let tagBackground = dynamicColor(light: 0xF0EEF5, dark: 0x34324A)
    static let tagForeground = dynamicColor(light: 0x5C5C66, dark: 0xCAC8DC)

    static var accentNSColor: NSColor {
        dynamicNSColor(light: 0x8A5CF6, dark: 0xA78BFA)
    }

    static var overlayPanelNSColor: NSColor {
        dynamicNSColor(light: 0xFFFFFF, dark: 0x22212E, lightAlpha: 0.8, darkAlpha: 0.84)
    }

    static var overlayStrokeNSColor: NSColor {
        dynamicNSColor(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.14)
    }

    static var overlayInkNSColor: NSColor {
        dynamicNSColor(light: 0x2A2833, dark: 0xF2F0FA)
    }

    static var overlayLabelNSColor: NSColor {
        srgb(0x2A2638, alpha: 0.92)
    }

    static func resolved(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }

    private static func dynamicColor(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: dynamicNSColor(light: light, dark: dark))
    }

    private static func dynamicNSColor(
        light: UInt32,
        dark: UInt32,
        lightAlpha: CGFloat = 1,
        darkAlpha: CGFloat = 1
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? srgb(dark, alpha: darkAlpha)
                : srgb(light, alpha: lightAlpha)
        }
    }

    private static func srgb(_ hex: UInt32, alpha: CGFloat) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

struct LocalShotBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motion = GlowMotion()

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let diameter = max(size.width, size.height) * 0.9
            ZStack {
                LocalShotTheme.base
                glow(LocalShotTheme.glowRose, diameter: diameter)
                    .offset(
                        x: size.width * (motion.drifts ? -0.16 : -0.26),
                        y: size.height * (motion.drifts ? -0.14 : -0.26)
                    )
                glow(LocalShotTheme.glowViolet, diameter: diameter)
                    .offset(
                        x: size.width * (motion.drifts ? 0.24 : 0.36),
                        y: size.height * (motion.drifts ? 0.22 : 0.34)
                    )
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 9).repeatForever(autoreverses: true),
                value: motion.drifts
            )
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .onAppear {
            guard !reduceMotion else {
                return
            }
            DispatchQueue.main.async {
                motion.drifts = true
            }
        }
    }

    @MainActor
    private final class GlowMotion: ObservableObject {
        @Published var drifts = false
    }

    private func glow(_ color: Color, diameter: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color, color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
    }
}

struct LocalShotTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(LocalShotTheme.tagForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(LocalShotTheme.tagBackground, in: Capsule())
    }
}

struct LocalShotIconButtonStyle: ButtonStyle {
    var isSelected = false
    var isGrouped = false
    var horizontalPadding: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        IconButton(
            configuration: configuration,
            isSelected: isSelected,
            isGrouped: isGrouped,
            horizontalPadding: horizontalPadding
        )
    }

    private struct IconButton: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        let isGrouped: Bool
        let horizontalPadding: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
            configuration.label
                .padding(.horizontal, horizontalPadding)
                .frame(minWidth: 28, minHeight: 26)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(shape.fill(fill))
                .overlay(shape.stroke(stroke, lineWidth: 1))
                .contentShape(shape)
                .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.35)
        }

        private var fill: Color {
            if isSelected {
                return LocalShotTheme.accent
            }
            return isGrouped ? .clear : LocalShotTheme.card
        }

        private var stroke: Color {
            isSelected || isGrouped ? .clear : LocalShotTheme.cardStroke
        }
    }
}
