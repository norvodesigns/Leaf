import Foundation

extension DemoData {
    /// Reading circles to go with the demo library: a weekly circle three days from its first goal (*Circe*, which
    /// the demo reader is 88 pages into), where friends who joined from the invitation have been reading all week;
    /// a two-person circle that starts in two days; and one put away after the last goal (from before invitations,
    /// with friends added by name).
    static func circles(now: Date = Date(), calendar: Calendar = .current) -> [ReadingCircle] {
        func day(_ offset: Int, hour: Int = 19) -> Date {
            let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(bySettingHour: hour, minute: 30, second: 0, of: start) ?? start
        }
        /// A friend's log: where they joined, then a sitting at each (day, hour, page). Sittings still to come in the
        /// staged hour are left out, and the page is wherever the last one got to.
        func friend(_ name: String, token: String, joined: Int, at startPage: Int = 0, sittings: [(Int, Int, Int)]) -> CircleMember {
            var member = CircleMember(name: name, paletteToken: token, remoteID: "_demo-\(name.lowercased())", updatedAt: day(joined, hour: 20))
            member.move(to: startPage, at: day(joined, hour: 20))
            for (offset, hour, page) in sittings where day(offset, hour: hour) <= now {
                member.move(to: page, at: day(offset, hour: hour))
            }
            return member
        }

        var club = ReadingCircle(
            id: UUID(uuidString: "6C1A0000-0000-4000-8000-00000000C1BE") ?? UUID(),
            name: "Thursday Club",
            book: circe,
            startsOn: day(-11),
            meetings: CirclePlanner.schedule(pages: circe.pages, firstMeeting: day(3), everyDays: 7, count: 4, calendar: calendar, now: day(-11)),
            members: [
                CircleMember(name: "You", kind: .me, page: 88, paletteToken: CozyPalette.matcha, remoteID: "_demo-me", updatedAt: day(0)),
                friend("Sam", token: CozyPalette.chai, joined: -11, sittings: [(-9, 21, 24), (-6, 21, 52), (-3, 22, 80), (-1, 21, 104)]),
                friend("Priya", token: CozyPalette.rooibos, joined: -10, sittings: [(-7, 7, 25), (-4, 8, 48), (0, 8, 70)]),
                friend("Jo", token: CozyPalette.steam, joined: -2, at: 12, sittings: [(-1, 22, 31)]),
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
                CircleMember(name: "You", kind: .me, paletteToken: CozyPalette.matcha, remoteID: "_demo-me", updatedAt: day(-1)),
                friend("Mum", token: CozyPalette.rose, joined: -1, sittings: []),
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
