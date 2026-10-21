import ActivityKit
import SwiftUI
import WidgetKit

/// The reading Live Activity: Lock Screen and StandBy, and the Dynamic Island. The views are shared with the app
/// (`LiveActivityShared/ReadingActivityViews.swift`) so the design can be staged in screenshots; this file only
/// wires them to ActivityKit and loads the cover the app left in the App Group.
struct ReadingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingActivityAttributes.self) { context in
            ReadingActivityFamilyView(model: Self.model(context), coverFileName: context.attributes.coverFileName)
                .activityBackgroundTint(ReadingActivityPalette.night)
                .activitySystemActionForegroundColor(ReadingActivityPalette.ink)
        } dynamicIsland: { context in
            let model = Self.model(context)
            let images = ReadingActivityImages.load(baseName: context.attributes.coverFileName)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ReadingActivityExpandedLeading(images: images)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ReadingActivityExpandedTrailing(model: model)
                }
                DynamicIslandExpandedRegion(.center) {
                    ReadingActivityExpandedCenter(model: model)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ReadingActivityExpandedBottom(model: model)
                }
            } compactLeading: {
                ReadingActivityCompactLeading(model: model, images: images)
            } compactTrailing: {
                ReadingActivityCompactTrailing(model: model)
            } minimal: {
                ReadingActivityMinimal(model: model)
            }
            .keylineTint(ReadingActivityPalette.amber)
        }
        // The Apple Watch Smart Stack gets its own small card instead of a squeezed Lock Screen.
        .supplementalActivityFamilies([.small])
    }

    private static func model(_ context: ActivityViewContext<ReadingActivityAttributes>) -> ReadingActivityModel {
        ReadingActivityModel(
            title: context.attributes.title,
            author: context.attributes.author,
            totalPages: context.attributes.totalPages,
            content: context.state,
            isStale: context.isStale
        )
    }
}

/// The Lock Screen layout on the iPhone, and the small card when the system draws the activity on the Apple Watch.
private struct ReadingActivityFamilyView: View {
    let model: ReadingActivityModel
    let coverFileName: String?

    @Environment(\.activityFamily) private var family

    var body: some View {
        if family == .small {
            ReadingActivityWatchCard(model: model)
                .padding(.horizontal, 2)
        } else {
            ReadingActivityLockScreen(model: model, images: ReadingActivityImages.load(baseName: coverFileName))
        }
    }
}
