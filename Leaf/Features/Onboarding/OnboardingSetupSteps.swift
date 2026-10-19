import SwiftUI

// MARK: - Step v: minutes

/// "A little, often.": the dial over a live sentence about what those minutes add up to.
struct OnboardingMinutesView: View {
    @Binding var minutes: Int
    let wpm: Double
    let daysPerWeek: Int

    var body: some View {
        let preview = OnboardingCopy.minutesPreview(minutes: minutes, wpm: wpm, daysPerWeek: daysPerWeek)
        OnboardingPage {
            VStack(spacing: Space.xxl) {
                OnboardingHeading(title: "A little, often.", message: "Choose the minutes you can give most days.")
                // The ruler runs edge to edge, past the page margins.
                MinutesDial(minutes: $minutes)
                    .padding(.horizontal, -Space.margin)
                VStack(spacing: Space.s) {
                    Text(preview.quote)
                        .leafStyle(.pullQuote)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(preview.caption)
                        .leafStyle(.caption)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 340)
            }
        }
    }
}

// MARK: - Step vi: days

/// "Which days?": the weekday picker over a sentence that says what the week looks like.
struct OnboardingDaysView: View {
    @Binding var days: Set<Int>
    let minutes: Int

    var body: some View {
        OnboardingPage {
            VStack(spacing: Space.xxl) {
                OnboardingHeading(title: "Which days?", message: "Rest days are part of the plan.")
                WeekdayPicker(selection: $days)
                VStack(spacing: Space.s) {
                    Text(OnboardingCopy.weekSummary(days))
                        .leafStyle(.pullQuote)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if !days.isEmpty {
                        Text(OnboardingCopy.weeklyTime(minutes: minutes, days: days.count))
                            .leafStyle(.caption)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: 340)
            }
        }
    }
}

// MARK: - Step vii: reminder

/// "A quiet nudge.": a wheel for the time over a preview of the notification it will send.
/// A second time a new reader can add with one tap.
enum OnboardingExtraTime: String, CaseIterable, Identifiable {
    case morning, lunch

    var id: String { rawValue }
    var hour: Int { self == .morning ? 7 : 12 }
    var minute: Int { 30 }
    var label: String { self == .morning ? "Morning tea" : "Lunch break" }
    var chip: String { self == .morning ? "Also a morning cup, 7:30" : "Also at lunch, 12:30" }
}

/// "When will you read?": the reader's first reading time on the time drum, an optional second one, and what the
/// gentle reminder would say. Leaf shares each day's pages between the times.
struct OnboardingTimesView: View {
    @Binding var hour: Int
    @Binding var minute: Int
    @Binding var extra: OnboardingExtraTime?
    /// The real reminder body for the chosen time.
    let message: String

    var body: some View {
        OnboardingPage {
            VStack(spacing: Space.xl) {
                OnboardingHeading(
                    title: "When will you read?",
                    message: "Pick your reading time. Leaf plans each day’s pages around it and can give you a quiet nudge."
                )
                TimeDrum(hour: $hour, minute: $minute)
                    .frame(maxWidth: .infinity)
                HStack(spacing: Space.s) {
                    ForEach(OnboardingExtraTime.allCases) { option in
                        let isOn = extra == option
                        Button {
                            Haptics.shared.selection()
                            extra = isOn ? nil : option
                        } label: {
                            Text(option.chip)
                                .leafStyle(.caption, color: isOn ? Color.accent : Color.inkSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Space.m)
                                .padding(.vertical, Space.s)
                                .frame(maxWidth: .infinity, minHeight: Space.hitTarget)
                                .background(isOn ? Color.accentSoft : Color.paperRaised, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                OnboardingNotificationPreview(message: message)
            }
        }
    }
}

/// What the reminder will look like: a glass rounded rect with the app icon, "LEAF · now" and the body.
struct OnboardingNotificationPreview: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            miniIcon
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Leaf · now")
                    .leafStyle(.eyebrow)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .glassEffect(.regular.tint(Color.glassTint), in: .rect(cornerRadius: Radius.card))
        .overlay {
            Radius.shape(Radius.card)
                .strokeBorder(Color.hairline, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of your reminder from Leaf: \(message)")
    }

    /// A 20 pt stand-in for the app icon: a green leaf with a ribbon tail on paper.
    private var miniIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .fill(Color.paperRaised)
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 0.5)
            Image(systemName: "leaf.fill")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.accent)
                .offset(y: -1)
            Capsule()
                .fill(Color.ribbon)
                .frame(width: 1.5, height: 5)
                .offset(y: 6)
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}
