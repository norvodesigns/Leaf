import SwiftUI
import WidgetKit

/// The widget extension's entry point: the reading Live Activity, the Today widget (Home Screen, StandBy, Lock
/// Screen), and the Control Center controls.
@main
struct LeafWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ReadingLiveActivity()
        LeafTodayWidget()
        LeafStartReadingControl()
        LeafSteepControl()
        LeafLogPagesControl()
    }
}
