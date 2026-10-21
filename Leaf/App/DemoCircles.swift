import Foundation

extension DemoData {
    /// Reading circles to go with the demo library: a weekly club three days from its first meeting (*Circe*, which
    /// the demo reader is 88 pages into), a two-person circle that hasn't started, and one put away after the last
    /// meeting.
    static func circles(now: Date = Date(), calendar: Calendar = .current) -> [ReadingCircle] {
        func day(_ offset: Int, hour: Int = 19) -> Date {
            let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(bySettingHour: hour, minute: 30, second: 0, of: start) ?? start
        }

        var club = ReadingCircle(
            id: UUID(uuidString: "6C1A0000-0000-4000-8000-00000000C1BE") ?? UUID(),
            name: "Thursday Club",
            book: circe,
            startsOn: day(-11),
            meetings: CirclePlanner.schedule(pages: circe.pages, firstMeeting: day(3), everyDays: 7, count: 4, calendar: calendar, now: day(-11)),
            members: [
                CircleMember(name: "You", kind: .me, page: 88, paletteToken: CozyPalette.matcha, updatedAt: day(0)),
                CircleMember(name: "Sam", page: 104, paletteToken: CozyPalette.chai, updatedAt: day(-1)),
                CircleMember(name: "Priya", page: 70, paletteToken: CozyPalette.rooibos, updatedAt: day(-2)),
                CircleMember(name: "Jo", page: 31, paletteToken: CozyPalette.steam, updatedAt: day(-5)),
            ],
            createdAt: day(-12)
        )
        if !club.meetings.isEmpty { club.meetings[0].place = "Sam’s kitchen" }

        let mum = ReadingCircle(
            id: UUID(uuidString: "6C1A0000-0000-4000-8000-00000000A0A0") ?? UUID(),
            name: "Long distance with Mum",
            book: piranesi,
            startsOn: day(2),
            meetings: CirclePlanner.schedule(pages: piranesi.pages, firstMeeting: day(12), everyDays: 14, count: 2, calendar: calendar, now: day(-1)),
            members: [
                CircleMember(name: "You", kind: .me, paletteToken: CozyPalette.matcha, updatedAt: day(-1)),
                CircleMember(name: "Mum", paletteToken: CozyPalette.rose, updatedAt: day(-1)),
            ],
            createdAt: day(-1)
        )

        let library = ReadingCircle(
            id: UUID(uuidString: "6C1A0000-0000-4000-8000-0000000B00C5") ?? UUID(),
            name: "Library book group",
            book: klara,
            startsOn: day(-40),
            meetings: CirclePlanner.schedule(pages: klara.pages, firstMeeting: day(-30), everyDays: 14, count: 2, calendar: calendar, now: day(-40)),
            members: [
                CircleMember(name: "You", kind: .me, page: klara.pages, paletteToken: CozyPalette.matcha, updatedAt: day(-16)),
                CircleMember(name: "Ruth", page: klara.pages, paletteToken: CozyPalette.amber, updatedAt: day(-16)),
                CircleMember(name: "Tom", page: 260, paletteToken: CozyPalette.chai, updatedAt: day(-16)),
            ],
            createdAt: day(-41),
            archivedAt: day(-15)
        )
        return [club, mum, library]
    }
}
