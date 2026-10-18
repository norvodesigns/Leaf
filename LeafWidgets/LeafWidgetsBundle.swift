import SwiftUI
import WidgetKit

/// The widget extension's entry point. It holds the reading Live Activity for now. Home Screen widgets and Control
/// Center controls are added to this bundle later, on the same target.
@main
struct LeafWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ReadingLiveActivity()
    }
}
