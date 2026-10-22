import SwiftUI

/// What's new: once after an update (`WhatsNewGate`), and from Settings any time. A calm sheet of paper: the version,
/// a serif headline, a small card for each change, and "Continue". No tour: the app explains itself.
struct WhatsNewView: View {
    let releases: [WhatsNewRelease]
    let build: AppBuild

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Eyebrow("What’s new in Leaf \(build.version)")
                    .padding(.top, Space.xxl)
                Text(releases.first?.title ?? "What’s new.")
                    .leafStyle(.display)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: Space.s) {
                    ForEach(releases) { release in
                        ForEach(release.items, id: \.title) { item in
                            card(item)
                        }
                    }
                }
                Text("Version \(build.label)")
                    .leafStyle(.caption, color: .inkTertiary)
                    .padding(.top, Space.s)
            }
            .leafMargins()
            .padding(.bottom, 150)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Space.s) {
                PrimaryGlassButton("Continue") {
                    dismiss()
                }
            }
            .leafMargins()
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
            .background {
                LinearGradient(colors: [Color.paper.opacity(0), Color.paper, Color.paper], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
        }
        .paperBackground()
        .presentationBackground(Color.paper)
        .presentationDragIndicator(.visible)
    }

    private func card(_ item: WhatsNewRelease.Item) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(item.title)
                .leafStyle(.headline)
            Text(item.line)
                .leafStyle(.body, color: .inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.paperRaised, in: .rect(cornerRadius: Radius.tile))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
