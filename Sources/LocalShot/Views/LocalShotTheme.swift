import AppKit
import SwiftUI

enum LocalShotTheme {
    static let accent = dynamicColor(light: 0x7357F6, dark: 0xA08EFF)
    static let backgroundTop = dynamicColor(light: 0xD3D8F0, dark: 0x24233A)
    static let backgroundBottom = dynamicColor(light: 0xDCD8F0, dark: 0x1B1A2B)
    static let card = dynamicColor(light: 0xFDFDFF, dark: 0x2D2C44)
    static let cardStroke = dynamicColor(light: 0xE2E0F0, dark: 0x3E3D5A)
    static let tagBackground = dynamicColor(light: 0xE5E5ED, dark: 0x3B3A52)
    static let tagForeground = dynamicColor(light: 0x5C5C66, dark: 0xCAC8DC)

    static var background: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
    }

    private static func dynamicColor(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
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
