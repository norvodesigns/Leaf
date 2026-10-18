# Leaf — engineering guide

Read this before you write any code. The design spec is [`DESIGN.md`](DESIGN.md).
The product brief is [`BRIEF.md`](BRIEF.md).

## Ground rules

- SwiftUI only, **iOS 26.0** / **watchOS 26.0** deployment targets, **Swift 5 language
  mode**. CI builds with **Xcode 26.6** (iOS 26.5 SDK). No third-party packages. APIs
  introduced after iOS 26.0 (e.g. `tabViewBottomAccessory(isEnabled:content:)` in 26.1) must
  be wrapped in `if #available(iOS 26.1, *)` with a sensible fallback.
- You can't compile SwiftUI on this Linux box, but you **must** syntax-check every file you
  write: `/home/user/tools/swift-6.4.1-RELEASE-ubuntu24.04/usr/bin/swiftc -parse <files>`.
  Then re-read your code against the real type and method names in `Shared/`, `Leaf/Services/`,
  `Leaf/App/` and `Leaf/DesignSystem/`. A wrong label or a missing `try` costs a full CI round.
- The Xcode project uses **synchronized folders**: any file you create under `Leaf/`,
  `LeafWatch/`, `Shared/`, `LeafTests/`, `LeafWidgets/` (widget extension only) or
  `LiveActivityShared/` (app and extension) is part of its target automatically. Only a new
  target, entitlement or build setting needs `Leaf.xcodeproj`; edit it by hand carefully and run
  `python3 scripts/check_pbxproj.py` (CI runs it first). See `docs/PLATFORM.md`.
- Logic tests for `Shared/` run anywhere with a Swift toolchain: `scripts/linux_tests.sh`.
  Keep expressions inside `#expect(...)` simple (annotate intermediate `Double`/`Int` values):
  the Xcode compiler gives up on long chained expressions that the Linux one accepts.
- Look at the macOS CI build (errors, screenshots) from anywhere with `python3 scripts/ci.py`.
- The UI and design pass is described in `docs/OPUS_HANDOFF.md`.
- `Shared/` is plain Foundation (it compiles on Linux for tests): no SwiftUI, UIKit, or
  WatchKit there.
- Match the existing code style: 4-space indent, doc comments on types and non-obvious
  functions only, small focused views, `private` helpers, no force unwraps on user data.
- Every interactive element gets an accessibility label if its text isn't self-describing.
  Respect `@Environment(\.accessibilityReduceMotion)` for anything beyond a fade.
- All text uses Dynamic Type via the typography tokens. Never hard-code a font without
  `relativeTo:` unless the spec says it's fixed (e.g. the giant display numerals).

## State and services (already written — read them)

| Thing | File | How to use |
| --- | --- | --- |
| `LibraryStore` | `Leaf/Services/LibraryStore.swift` | `@Environment(LibraryStore.self) private var store`. All reads (`reading`, `toRead`, `finished`, `plan`, `todayAssignments`, `minutesReadToday`, `goalProgress`, `streak`, `week`, `activeSession`, `preferences`, `wpm`) and all mutations (`add`, `move`, `startReading`, `markFinished`, `remove`, `setPage`, `reorder`, `moveToFront`, `updateBook`, `updatePreferences`, `recordSpeedTest`, `startSession`, `pauseSession`, `resumeSession`, `cancelSession`, `finishSession(toPage:)`, `resetEverything`). |
| `AppRouter` | `Leaf/App/AppRouter.swift` | `@Environment(AppRouter.self) private var router`. Tabs, per-tab `NavigationStack` paths of `BookRoute`, `showSettings`, `showSession` (open it with `router.presentSession(from: "hero" | "accessory")` so the zoom source is recorded in `sessionSource`), `showSpeedTest`, `lastOutcome`, `libraryShelf`, `searchQuery`. Open a book with `router.open(book)`. |
| `BookCatalog` | `Leaf/Services/BookCatalog.swift` | `@Environment(BookCatalog.self) private var catalog`. `search(_:)`, `collections(wpm:excluding:)`, `book(id:)`, `isLoaded`. |
| `OpenLibrary` | `Leaf/Services/OpenLibrary.swift` | `try await OpenLibrary.search(query)` → `[Book]`. |
| `Reminders` | `Leaf/Services/Reminders.swift` | `Reminders.shared.requestAuthorization()`, `authorizationStatus()`. Rescheduling happens automatically on every store change. |
| `Haptics` | `Leaf/Services/Haptics.swift` | `Haptics.shared.selection()`, `.tap()`, `.soft(0.6)`, `.rigid(0.8)`, `.press()`, `.success()`, `.warning()`, `.error()`, `.play(.reorderLift, heft: Haptics.heft(pages: book.pages))`, `.riffle(count:earlier:)`. Respects Settings → Feel automatically. Use the haptics map in DESIGN.md §8. |
| Preferences extras | `Shared/Models.swift` | `ReadingPreferences` also has `onboardedAt`, `learnFromSessions`, `hapticsLevel: HapticsLevel (.full/.subtle/.off)`, `appearance: AppearancePreference (.system/.day/.night)`. The app applies appearance and haptics level itself. `store.issueNumber` is Today's "No. 42"; `store.sessionCount(for:)`, `store.sessions(for:)` (newest first). |
| Planner, models | `Shared/*.swift` | `Book`, `LibraryItem`, `ReadingSession`, `ActiveSession`, `ReadingPlan`/`PlannedBook`/`PlanDay`/`Assignment`, `ReadingSpeed`, `ReadingStats`, `LeafFormat` (durations, dates, pages). |
| Speed test content | `Leaf/Core/SpeedTestPassages.swift` | `SpeedTestPassages.all`, `.passage(after:)`. |
| Demo data | `Leaf/App/DemoData.swift` | `DemoData.make()` and the sample books (`DemoData.hobbit` …). Use these in `#Preview`s with `LibraryStore(persistence: .ephemeral())` + `replaceAll(with:)`. |

`Book.coverURL(.medium)` gives the Open Library cover. Always render a `GeneratedCover`
underneath and fade the real image in, because many books have no cover.

## Screens and file ownership

| Area | Folder | Root view (exact name and init) |
| --- | --- | --- |
| Onboarding | `Leaf/Features/Onboarding/` | `OnboardingFlow(startAt: OnboardingStep = .welcome, onFinish: () -> Void)` and `enum OnboardingStep: String, CaseIterable { case welcome, speedtest, quiz, result, minutes, days, reminder, books }`. Also `SpeedTestView(onComplete: (SpeedTestResult) -> Void)` reusable from Settings for a retake. |
| Today | `Leaf/Features/Today/` | `TodayView()` |
| Session | `Leaf/Features/Session/` | `SessionView()` (full-screen; reads `store.activeSession`), `SessionOutcomeView(outcome: SessionOutcome)`, `SessionAccessory()` (the tab-bar bottom accessory shown while a session runs, e.g. one started on the watch) |
| Library | `Leaf/Features/Library/` | `LibraryView()` with an internal shelf picker; respects `router.libraryShelf` |
| Book detail | `Leaf/Features/Book/` | `BookDetailView(book: Book)` (works whether or not the book is in the library) and `AddBookManuallyView()` |
| Plan | `Leaf/Features/Plan/` | `PlanView()` |
| Search | `Leaf/Features/Search/` | `SearchView()` (catalog collections when empty; merged local + Open Library results when typing; respects `router.searchQuery` as the initial query) |
| Settings | `Leaf/Features/Settings/` | `SettingsView()` (sheet) |
| Shell | `Leaf/App/RootView.swift`, `Leaf/App/MainTabs.swift` | Already wired: onboarding vs tabs, sheets, full-screen session, screenshot routing. |
| Design system | `Leaf/DesignSystem/` | Tokens and shared components — see DESIGN.md and the files themselves. Feature code must use these rather than re-creating them. |

## iOS 26 API cheat sheet (known-good signatures)

```swift
// Liquid Glass
view.glassEffect()                                            // regular, capsule
view.glassEffect(.regular.tint(color).interactive(), in: .rect(cornerRadius: 24))
view.glassEffect(.clear, in: .circle)
GlassEffectContainer(spacing: 16) { ... }                     // groups glass so shapes can merge/morph
view.glassEffectID("play", in: namespace)                     // morphing between states (with @Namespace)
Button("Start") { }.buttonStyle(.glassProminent)              // tinted by .tint(...)
Button("Pause") { }.buttonStyle(.glass)

// Tabs (iOS 18+ Tab API; iOS 26 floating glass tab bar)
TabView(selection: $tab) {
    Tab("Today", systemImage: "sun.horizon", value: AppTab.today) { TodayView() }
    Tab(value: AppTab.search, role: .search) { SearchView() }
}
.tabBarMinimizeBehavior(.onScrollDown)
.tabViewBottomAccessory { SessionAccessory() }

// Navigation
NavigationStack(path: $path) { ... }.navigationDestination(for: BookRoute.self) { BookDetailView(book: $0.book) }
cover.matchedTransitionSource(id: book.id, in: namespace)
BookDetailView(book: book).navigationTransition(.zoom(sourceID: book.id, in: namespace))
.toolbar { ToolbarItem(placement: .topBarTrailing) { ... }; ToolbarSpacer(.fixed) }
.scrollEdgeEffectStyle(.soft, for: .top)

// Search
.searchable(text: $query, prompt: "Title or author")

// Motion & feedback
.sensoryFeedback(.selection, trigger: value)
.contentTransition(.numericText(value: Double(minutes)))
.symbolEffect(.bounce, value: trigger)
.scrollTransition { content, phase in content.opacity(phase.isIdentity ? 1 : 0.6) }
PhaseAnimator([0, 1], trigger: t) { content, phase in ... } animation: { _ in .spring(duration: 0.4) }
KeyframeAnimator(initialValue: Values(), trigger: t) { content, v in ... } keyframes: { _ in KeyframeTrack(\.scale) { SpringKeyframe(1.1, duration: 0.2) } }
MeshGradient(width: 3, height: 3, points: [...9 SIMD2<Float>], colors: [...9 Color])
withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { ... }

// Sheets
.sheet(isPresented: $show) { SettingsView().presentationDetents([.large]) }
.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
.fullScreenCover(isPresented: $show) { SessionView() }
```

Avoid: `UIScreen.main` (deprecated), `NavigationView`, `onChange(of:perform:)` (old
single-parameter form, use `{ old, new in }`), `foregroundColor` (use `foregroundStyle`),
`.cornerRadius()` (use `clipShape(.rect(cornerRadius:))`), `PreviewProvider` (use `#Preview`),
and any `@available(iOS 27…)` API.

## Screenshot routing

CI launches debug builds with `-LeafDemo YES -LeafScreen <key>` and screenshots each
screen (see `scripts/ci_screenshots.sh`). `RootView` maps keys to router state:
`onboarding.<step>`, `today`, `library`, `library.finished`, `plan`, `search`,
`search.query`, `book:<id>`, `session`, `session.outcome`, `settings`. Each screen must look
complete and correct in that state with the demo library, in both light and dark mode.
