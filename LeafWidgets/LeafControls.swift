import AppIntents
import SwiftUI
import WidgetKit

// Control Center, the Lock Screen's controls and the Action button: Start reading, Steep a pot, and Log pages. Each
// runs one of the intents in `LiveActivityShared/ReadingIntents.swift`, which the app performs: the first two open
// Leaf, Log pages moves the bookmark without opening it. The subtitle comes from the snapshot the app writes, and the
// app reloads the controls whenever it changes.

/// The book and the state a control's subtitle shows.
struct LeafControlValue: Sendable {
    var subtitle: String
    var isReading: Bool

    static func current(pages: Int? = nil) -> LeafControlValue {
        let snapshot = (LeafWidgetStore.read() ?? .empty).at(Date())
        let phase = snapshot.phase(at: Date())
        let book = snapshot.current
        let isReading = phase == .reading || phase == .paused || phase == .goalReached
        let subtitle: String
        if let book {
            subtitle = pages == nil ? book.title : "\(book.title) · p. \(book.currentPage)"
        } else {
            subtitle = "Choose a book in Leaf"
        }
        return LeafControlValue(subtitle: subtitle, isReading: isReading)
    }

    static let preview = LeafControlValue(subtitle: "The Hobbit", isReading: false)
}

struct LeafControlProvider: ControlValueProvider {
    var previewValue: LeafControlValue { .preview }

    func currentValue() async throws -> LeafControlValue {
        .current()
    }
}

/// Opens Leaf and starts today's reading, or goes back to the session running.
struct LeafStartReadingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: LeafWidgetStore.readControlKind, provider: LeafControlProvider()) { value in
            ControlWidgetButton(action: StartReadingIntent()) {
                Label {
                    Text(value.isReading ? "Back to reading" : "Start reading")
                    Text(value.subtitle)
                } icon: {
                    Image(systemName: value.isReading ? "book.fill" : "book")
                }
            }
        }
        .displayName("Start reading")
        .description("Opens Leaf and starts today’s reading.")
    }
}

/// Opens Leaf with a pot steeping for the next book.
struct LeafSteepControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: LeafWidgetStore.steepControlKind, provider: LeafControlProvider()) { value in
            ControlWidgetButton(action: StartSteepIntent()) {
                Label {
                    Text("Steep a pot")
                    Text(value.subtitle)
                } icon: {
                    Image(systemName: "cup.and.heat.waves.fill")
                }
            }
        }
        .displayName("Steep a pot")
        .description("Opens Leaf with tea steeping for your next book.")
    }
}

/// How many pages one press of Log pages moves the bookmark. The reader picks it when adding the control.
struct LogPagesControlConfiguration: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Log pages"
    static var description: IntentDescription? = IntentDescription("How many pages each press moves your bookmark.")

    @Parameter(title: "Pages", default: 5)
    var pages: Int

    init() {}

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct LeafLogPagesValue: Sendable {
    var pages: Int
    var subtitle: String
}

struct LeafLogPagesProvider: AppIntentControlValueProvider {
    func previewValue(configuration: LogPagesControlConfiguration) -> LeafLogPagesValue {
        LeafLogPagesValue(pages: configuration.pages, subtitle: "The Hobbit · p. 143")
    }

    func currentValue(configuration: LogPagesControlConfiguration) async throws -> LeafLogPagesValue {
        LeafLogPagesValue(pages: configuration.pages, subtitle: LeafControlValue.current(pages: configuration.pages).subtitle)
    }
}

/// Moves the bookmark on by a few pages, during a session or between them, without opening Leaf.
struct LeafLogPagesControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: LeafWidgetStore.logControlKind, provider: LeafLogPagesProvider()) { value in
            ControlWidgetButton(action: LogPagesIntent(pages: value.pages)) {
                Label {
                    Text(value.pages == 1 ? "Log a page" : "Log \(value.pages) pages")
                    Text(value.subtitle)
                } icon: {
                    Image(systemName: "bookmark.fill")
                }
            }
        }
        .displayName("Log pages")
        .description("Moves your bookmark on without opening Leaf.")
    }
}
