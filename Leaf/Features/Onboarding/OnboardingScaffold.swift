import SwiftUI

/// A step's body. It sits in the space between the navigation bar and the action bar, and
/// scrolls only when it has to (large Dynamic Type sizes, small phones).
///
/// `alignment` places the content: `.center` for the setup steps, `.topLeading` for the quiz.
struct OnboardingPage<Content: View>: View {
    var alignment: Alignment
    let content: Content

    init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: 560, alignment: alignment)
                    .frame(maxWidth: .infinity)
                    .leafMargins()
                    .padding(.vertical, Space.l)
                    .frame(minHeight: proxy.size.height, alignment: alignment)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }
}

/// A step's headline in `masthead` with an optional `body` line in `inkSecondary`.
struct OnboardingHeading: View {
    let title: String
    var message: String?
    var centered: Bool

    init(title: String, message: String? = nil, centered: Bool = true) {
        self.title = title
        self.message = message
        self.centered = centered
    }

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: Space.m) {
            Text(title)
                .leafStyle(.masthead)
                .multilineTextAlignment(centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .leafStyle(.body, color: .inkSecondary)
                    .multilineTextAlignment(centered ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320, alignment: centered ? .center : .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }
}

/// One button in the onboarding action bar.
struct OnboardingAction {
    let title: String
    var isEnabled: Bool
    var isLoading: Bool
    let perform: () -> Void

    init(_ title: String, isEnabled: Bool = true, isLoading: Bool = false, perform: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.perform = perform
    }
}

/// The bottom of every onboarding step: an optional caption, the step's one `PrimaryGlassButton`,
/// a quiet text action, and the roman folios. Every slot keeps its height, so the button stays
/// put while the steps crossfade above it. Scrolling content fades out beneath it.
struct OnboardingActionBar: View {
    var note: Text?
    var primary: OnboardingAction?
    var secondary: OnboardingAction?
    var secondaryColor: Color
    /// The active folio (0-based), or nil to hide the folios.
    var folio: Int?
    var folioCount: Int

    @ScaledMetric(relativeTo: .headline) private var buttonHeight: CGFloat = 54

    init(
        note: Text? = nil,
        primary: OnboardingAction? = nil,
        secondary: OnboardingAction? = nil,
        secondaryColor: Color = .accent,
        folio: Int? = nil,
        folioCount: Int = 0
    ) {
        self.note = note
        self.primary = primary
        self.secondary = secondary
        self.secondaryColor = secondaryColor
        self.folio = folio
        self.folioCount = folioCount
    }

    var body: some View {
        VStack(spacing: Space.s) {
            if let note {
                note
                    .leafStyle(.caption)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
            ZStack {
                if let primary {
                    PrimaryGlassButton(primary.title, isLoading: primary.isLoading, action: primary.perform)
                        .disabled(!primary.isEnabled)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: buttonHeight)
            ZStack {
                if let secondary {
                    TextButton(secondary.title, color: secondaryColor, action: secondary.perform)
                        .disabled(!secondary.isEnabled)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            if let folio, folioCount > 0 {
                OnboardingFolios(index: folio, count: folioCount)
                    .padding(.top, Space.xxs)
            }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .leafMargins()
        .padding(.top, Space.l)
        .padding(.bottom, Space.s)
        .background {
            LinearGradient(
                stops: [
                    .init(color: Color.paper.opacity(0), location: 0),
                    .init(color: Color.paper, location: 0.3),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

/// Roman folios, "i … viii", in `eyebrow` type: the active one in `ink`.
struct OnboardingFolios: View {
    let index: Int
    let count: Int

    private static let numerals = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii"]

    init(index: Int, count: Int) {
        self.index = index
        self.count = count
    }

    var body: some View {
        HStack(spacing: Space.m) {
            ForEach(0..<count, id: \.self) { position in
                Text(verbatim: Self.numeral(position + 1))
                    .font(LeafType.eyebrow)
                    .tracking(1.5)
                    .foregroundStyle(position == index ? Color.ink : Color.inkTertiary)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .leafAnimation(Motion.glass, value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }

    static func numeral(_ number: Int) -> String {
        numerals.indices.contains(number - 1) ? numerals[number - 1] : String(number)
    }
}

#Preview("Action bar") {
    VStack {
        Spacer()
        OnboardingHeading(title: "A little, often.", message: "Choose the minutes you can give most days.")
            .leafMargins()
        Spacer()
        OnboardingActionBar(
            note: Text("Your stack: 3 books · about 6 weeks."),
            primary: OnboardingAction("Make my plan") {},
            secondary: OnboardingAction("Skip for now") {},
            secondaryColor: .inkSecondary,
            folio: 7,
            folioCount: 8
        )
    }
    .paperBackground()
}
