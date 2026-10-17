import SwiftUI

/// A calm, centred empty screen (DESIGN.md §5): a "❦" ornament, the title in `masthead`, the
/// message in `body` `inkSecondary` (max 300 pt wide) and an optional button. 56 pt vertical padding.
struct EmptyState: View {
    let title: String
    let message: String
    var actionTitle: String?
    var prominent: Bool
    var action: (() -> Void)?

    /// - Parameter prominent: the action uses `PrimaryGlassButton` (only when nothing else on the
    ///   screen is prominent); otherwise a compact `SecondaryGlassButton`.
    init(title: String, message: String, actionTitle: String? = nil, prominent: Bool = false, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.prominent = prominent
        self.action = action
    }

    init(_ title: String, message: String, actionTitle: String? = nil, prominent: Bool = false, action: (() -> Void)? = nil) {
        self.init(title: title, message: message, actionTitle: actionTitle, prominent: prominent, action: action)
    }

    var body: some View {
        VStack(spacing: Space.l) {
            Text("❦")
                .leafStyle(.index)
                .accessibilityHidden(true)
            Text(title)
                .leafStyle(.masthead)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if !message.isEmpty {
                Text(message)
                    .leafStyle(.body, color: .inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            if let actionTitle, let action {
                Group {
                    if prominent {
                        PrimaryGlassButton(actionTitle, action: action)
                    } else {
                        SecondaryGlassButton(actionTitle, compact: true, action: action)
                    }
                }
                .frame(maxWidth: 300)
                .padding(.top, Space.s)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.section)
        .padding(.horizontal, Space.margin)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Empty states") {
    ScrollView {
        EmptyState(title: "An empty issue.", message: "Add a book and Leaf will plan the pages.", actionTitle: "Find a book", prominent: true) {}
        EmptyState(title: "The queue is clear.", message: "Add the books you mean to get to.")
    }
    .paperBackground()
}
