import SwiftUI

extension View {
    func skillsManagerPanel(cornerRadius: CGFloat = 18) -> some View {
        modifier(SkillsManagerPanelModifier(cornerRadius: cornerRadius))
    }
}

private struct SkillsManagerPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

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
                        Color(nsColor: .separatorColor).opacity(0.45),
                        lineWidth: 0.5
                    )
                }
        }
    }
}
