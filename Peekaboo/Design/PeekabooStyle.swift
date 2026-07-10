import SwiftUI

enum PeekabooStyle {
    static let panelCornerRadius: CGFloat = 18
    static let horizontalPadding: CGFloat = 16
    static let rowHeight: CGFloat = 32
    static let taskSpacing: CGFloat = 4
}

struct PeekPanelSurface: ViewModifier {
    let translucent: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(translucent ? 1 : 0)
                    Rectangle()
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .opacity(translucent ? 0 : 1)
                }
                .animation(reduceMotion ? nil : PeekabooMotion.background, value: translucent)
            }
            .clipShape(RoundedRectangle(cornerRadius: PeekabooStyle.panelCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PeekabooStyle.panelCornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 0.7)
            }
    }
}

extension View {
    func peekPanelSurface(translucent: Bool) -> some View {
        modifier(PeekPanelSurface(translucent: translucent))
    }
}
