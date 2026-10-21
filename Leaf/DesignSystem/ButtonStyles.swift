import SwiftUI

/// A plain button that dims while pressed. For rows, covers and text links on paper.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// `.buttonStyle(.pressable)`
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// A text link ("Change", "Retake", "See all"). `accent` `ui` by default, with a 44 pt tall hit area
/// that doesn't change the layout.
struct TextButton: View {
    let title: String
    var style: LeafTextStyle
    var color: Color
    let action: () -> Void

    init(_ title: String, style: LeafTextStyle = .ui, color: Color = .accent, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .leafStyle(style, color: color)
                // A taller and wider hit area than the words, without moving them: short labels ("Edit") still get
                // close to 44 pt.
                .padding(.vertical, Space.m)
                .padding(.horizontal, Space.s)
                .contentShape(.rect)
                .padding(.vertical, -Space.m)
                .padding(.horizontal, -Space.s)
        }
        .buttonStyle(.pressable)
    }
}

#Preview("Text buttons") {
    VStack(spacing: Space.l) {
        TextButton("Change") {}
        TextButton("Retake", style: .headline, color: .ink) {}
        Button {} label: {
            Text("A pressable row").leafStyle(.headline)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.pressable)
    }
    .leafMargins()
    .frame(maxHeight: .infinity)
    .paperBackground()
}
