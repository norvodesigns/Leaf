import SwiftUI

/// A section eyebrow with an optional trailing action and a rule below (DESIGN.md §5).
/// 40 pt above (`topSpacing`), 12 below. Pass the eyebrow in sentence case ("This week"); it is
/// uppercased on screen and VoiceOver reads it naturally. `.double` uses the double rule.
struct SectionHeader: View {
    enum Style: Hashable, Sendable {
        case single, double
    }

    let eyebrow: String
    var style: Style
    var topSpacing: CGFloat
    var actionTitle: String?
    var action: (() -> Void)?

    init(_ eyebrow: String, style: Style = .single, topSpacing: CGFloat = Space.xxxl, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.eyebrow = eyebrow
        self.style = style
        self.topSpacing = topSpacing
        self.actionTitle = actionTitle
        self.action = action
    }

    init(eyebrow: String, style: Style = .single, topSpacing: CGFloat = Space.xxxl, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.init(eyebrow, style: style, topSpacing: topSpacing, actionTitle: actionTitle, action: action)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Text(eyebrow)
                    .leafStyle(.eyebrow)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                            .leafStyle(.caption)
                            .padding(.vertical, Space.m)
                            .contentShape(.rect)
                            .padding(.vertical, -Space.m)
                    }
                    .buttonStyle(.pressable)
                }
            }
            switch style {
            case .single: Hairline()
            case .double: DoubleRule()
            }
        }
        .padding(.top, topSpacing)
        .padding(.bottom, Space.m)
    }
}

#Preview("Section headers") {
    VStack(alignment: .leading, spacing: 0) {
        SectionHeader("This week", topSpacing: 0)
        Text("Week strip goes here").leafStyle(.caption)
        SectionHeader("Under four hours at your pace", actionTitle: "See all") {}
        Text("Carousel goes here").leafStyle(.caption)
        SectionHeader("Thursday 16 October", style: .double)
    }
    .leafMargins()
    .frame(maxHeight: .infinity, alignment: .top)
    .paperBackground()
}
