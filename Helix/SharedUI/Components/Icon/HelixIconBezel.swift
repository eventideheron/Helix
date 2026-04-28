import SwiftUI

struct HelixIconBezel<Content: View>: View {
    let backgroundColor: Color
    let borderColor: Color
    let cornerRadiusRatio: CGFloat
    let contentPaddingRatio: CGFloat
    let showInnerHighlight: Bool
    let showOuterShadow: Bool
    @ViewBuilder let content: Content

    init(
        backgroundColor: Color = HelixColor.background,
        borderColor: Color = Color.white.opacity(0.04),
        cornerRadiusRatio: CGFloat = 0.223,
        contentPaddingRatio: CGFloat = 0.17,
        showInnerHighlight: Bool = true,
        showOuterShadow: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.cornerRadiusRatio = cornerRadiusRatio
        self.contentPaddingRatio = contentPaddingRatio
        self.showInnerHighlight = showInnerHighlight
        self.showOuterShadow = showOuterShadow
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let cornerRadius = size * cornerRadiusRatio
            let padding = size * contentPaddingRatio

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)

                if showInnerHighlight {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.03),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: max(1, size * 0.004)
                        )
                        .blendMode(.screen)
                }

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: max(1, size * 0.002))

                content
                    .padding(padding)
            }
            .frame(width: size, height: size)
            .shadow(
                color: showOuterShadow ? Color.black.opacity(0.12) : .clear,
                radius: showOuterShadow ? size * 0.035 : 0,
                x: 0,
                y: showOuterShadow ? size * 0.01 : 0
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
