import ActivityKit
import SwiftUI
import WidgetKit

/// A deliberately plain reading Live Activity: it proves the extension is wired up and shows the real timer and page.
/// The look (cover, blur, buttons, wording for each state) is designed later and replaces the views in this file.
struct ReadingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingActivityAttributes.self) { context in
            ReadingLockScreenView(attributes: context.attributes, content: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "book.closed")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ReadingTimerText(content: context.state)
                        .frame(width: 84, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(readingPageLine(attributes: context.attributes, content: context.state))
                }
            } compactLeading: {
                Image(systemName: "book.closed")
            } compactTrailing: {
                ReadingTimerText(content: context.state)
                    .frame(width: 56)
            } minimal: {
                Image(systemName: "book.closed")
            }
        }
    }
}

/// The Lock Screen and StandBy presentation.
private struct ReadingLockScreenView: View {
    let attributes: ReadingActivityAttributes
    let content: ReadingActivityContent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(attributes.title)
                .font(.headline)
                .lineLimit(1)
            Text(readingStateLine(content.state))
                .font(.subheadline)
            ReadingTimerText(content: content)
                .font(.title)
            Text(readingPageLine(attributes: attributes, content: content))
                .font(.footnote)
        }
        .padding()
    }
}

/// The system draws and advances these digits, so they stay live without any app updates. A paused session is frozen
/// at the moment it was paused.
private struct ReadingTimerText: View {
    let content: ReadingActivityContent

    var body: some View {
        Text(
            timerInterval: content.timerRange,
            pauseTime: content.pauseDate,
            countsDown: content.countsDown
        )
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

private func readingStateLine(_ state: ReadingActivityState) -> String {
    switch state {
    case .reading: return "Reading"
    case .paused: return "Paused"
    case .goalReached: return "Goal reached"
    case .finishing: return "Finishing up"
    }
}

private func readingPageLine(attributes: ReadingActivityAttributes, content: ReadingActivityContent) -> String {
    if attributes.totalPages > 0 {
        return "Page \(content.currentPage) of \(attributes.totalPages)"
    }
    return "Page \(content.currentPage)"
}
