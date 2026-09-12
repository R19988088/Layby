import SwiftUI

/// A persistent reflection layer above native glass and below the file content.
/// Its lighting is independent of key-window state; AppKit still owns the blur.
struct ShelfGlassChrome: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var isDark: Bool { colorScheme == .dark }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ShelfLayout.cornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            if !reduceTransparency {
                // Light catches the upper lip and fades before reaching the file
                // contents. A softer lower reflection gives the glass thickness.
                shape.fill(LinearGradient(stops: [
                    .init(color: .white.opacity(isDark ? 0.18 : 0.38), location: 0),
                    .init(color: .white.opacity(isDark ? 0.045 : 0.10), location: 0.16),
                    .init(color: .clear, location: 0.42),
                    .init(color: .clear, location: 0.76),
                    .init(color: .white.opacity(isDark ? 0.055 : 0.14), location: 1)
                ], startPoint: .top, endPoint: .bottom))

                // Uneven edge illumination reads as a curved glass surface rather
                // than a flat border. strokeBorder stays inside the window radius.
                shape.strokeBorder(LinearGradient(stops: [
                    .init(color: .white.opacity(isDark ? 0.80 : 0.95), location: 0),
                    .init(color: .white.opacity(0.28), location: 0.23),
                    .init(color: .white.opacity(0.06), location: 0.49),
                    .init(color: .white.opacity(isDark ? 0.14 : 0.24), location: 0.70),
                    .init(color: .white.opacity(isDark ? 0.46 : 0.75), location: 1)
                ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.25)

                shape.inset(by: 1.5).strokeBorder(LinearGradient(
                    colors: [.white.opacity(isDark ? 0.20 : 0.30), .clear, .white.opacity(0.06)],
                    startPoint: .top, endPoint: .bottom), lineWidth: 0.65)
            }

            if reduceTransparency || contrast == .increased {
                shape.strokeBorder((isDark ? Color.white : Color.black).opacity(0.28), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
