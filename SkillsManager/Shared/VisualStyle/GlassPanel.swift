import SwiftUI

extension View {
    func skillsManagerPanel(cornerRadius: CGFloat = SkillsManagerRadius.floating) -> some View {
        modifier(SkillsManagerPanelModifier(cornerRadius: cornerRadius))
    }
}

private struct SkillsManagerPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                    .stroke(
                        separatorColor,
                        lineWidth: colorSchemeContrast == .increased ? 1 : 0.5
                    )
                }
        }
    }

    private var separatorColor: Color {
        let color = Color(nsColor: .separatorColor)
        return colorSchemeContrast == .increased ? color : color.opacity(0.45)
    }
}
