import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

struct CircleTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        c.locale = Locale(identifier: "en_US")
        return c
    }

    /// 2026-10-19 is a Monday.
    private func day(_ offset: Int, hour: Int = 19) -> Date {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: hour)) ?? Date()
        return calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
    }

    private let book = Book(id: "circle-book", title: "Circe", author: "Madeline Miller", pages: 400, words: 108_000, genres: ["fantasy"])

    private func circle(meetings: [CircleMeeting], members: [CircleMember]) -> ReadingCircle {
        ReadingCircle(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000C1C1") ?? UUID(),
            name: "Thursday Club", book: book, startsOn: day(0), meetings: meetings, members: members, createdAt: day(0)
        )
    }

    // MARK: Schedule

    @Test func scheduleSplitsEvenlyAndEndsOnTheLastPage() {
        let meetings = CirclePlanner.schedule(pages: 400, firstMeeting: day(3), everyDays: 7, count: 4, calendar: calendar)
        let pages = meetings.map(\.throughPage)
        #expect(pages == [100, 200, 300, 400])
        let gaps = zip(meetings, meetings.dropFirst()).map { calendar.dateComponents([.day], from: $0.date, to: $1.date).day ?? 0 }
        #expect(gaps == [7, 7, 7])
    }

    @Test func scheduleRoundsToFivesAndStartsFromTheStartPage() {
        let meetings = CirclePlanner.schedule(pages: 311, startPage: 20, firstMeeting: day(1), everyDays: 3, count: 3, calendar: calendar)
        let pages = meetings.map(\.throughPage)
        // 20 + 291/3 = 117, 20 + 194 = 214: rounded to fives, and the last is the end of the book.
        #expect(pages == [115, 215, 311])
    }

    @Test func scheduleNeverStandsStillOnTinyBooks() {
        let meetings = CirclePlanner.schedule(pages: 3, firstMeeting: day(1), everyDays: 1, count: 10, calendar: calendar)
        let pages = meetings.map(\.throughPage)
        #expect(pages == [1, 2, 3])
    }

    @Test func normalizedSortsAndKeepsPagesGoingUp() {
        let late = CircleMeeting(date: day(10), throughPage: 50)
        let early = CircleMeeting(date: day(3), throughPage: 120)
        let wild = CircleMeeting(date: day(14), throughPage: 9_000)
        let pages = CirclePlanner.normalized([late, wild, early], pages: 400).map(\.throughPage)
        #expect(pages == [120, 120, 400])
    }

    // MARK: Snapshot

    @Test func snapshotFindsTheNextMeetingAndTheSection() {
        let meetings = CirclePlanner.schedule(pages: 400, firstMeeting: day(3), everyDays: 7, count: 4, calendar: calendar)
        let c = circle(meetings: meetings, members: [CircleMember(name: "Me", kind: .me)])
        let snap = CirclePlanner.snapshot(for: c, myPage: 150, wpm: 250, now: day(5), calendar: calendar)
        let index = snap.nextMeetingIndex
        let days = snap.daysUntilNext
        #expect(index == 1)
        #expect(days == 5)
        #expect(snap.sectionStart == 100)
        #expect(snap.sectionEnd == 200)
        #expect(snap.myPagesToGo == 50)
        // 50 pages × 270 words ÷ 250 wpm = 54 minutes over 6 evenings (today counts).
        let minutes = snap.myMinutesPerDay
        #expect(minutes == 9)
        #expect(snap.statusLine == "50 pages before Thursday, about 9 minutes a day.")
    }

    @Test func meetingTodayIsStillTheNextMeeting() {
        let meetings = [CircleMeeting(date: day(2, hour: 20), throughPage: 200), CircleMeeting(date: day(9), throughPage: 400)]
        let c = circle(meetings: meetings, members: [CircleMember(name: "Me", kind: .me)])
        let snap = CirclePlanner.snapshot(for: c, myPage: 200, wpm: 250, now: day(2, hour: 9), calendar: calendar)
        let index = snap.nextMeetingIndex
        #expect(index == 0)
        #expect(snap.statusLine == "Today’s goal is page 200. You’re there.")
    }

    @Test func paceIsMeasuredAgainstASteadyLine() {
        // From the start (Monday) to page 200 on day 10: on day 5 a steady reader is at 100.
        let meetings = [CircleMeeting(date: day(10), throughPage: 200), CircleMeeting(date: day(20), throughPage: 400)]
        let members = [
            CircleMember(name: "Me", kind: .me, page: 0),
            CircleMember(name: "Sam", page: 210),
            CircleMember(name: "Jo", page: 90),
            CircleMember(name: "Ada", page: 20),
            CircleMember(name: "Bea", page: 400),
        ]
        let c = circle(meetings: meetings, members: members)
        let snap = CirclePlanner.snapshot(for: c, myPage: nil, wpm: 250, now: day(5), calendar: calendar)
        let paces = snap.members.map(\.pace)
        #expect(paces == [.catchingUp, .ready, .onPace, .catchingUp, .finished])
        let samSection = snap.members[1].sectionFraction
        #expect(samSection == 1)
    }

    @Test func myPageComesFromTheLibraryWhenThereIsOne() {
        let meetings = [CircleMeeting(date: day(10), throughPage: 200)]
        let c = circle(meetings: meetings, members: [CircleMember(name: "Me", kind: .me, page: 12)])
        let fromLibrary = CirclePlanner.snapshot(for: c, myPage: 180, wpm: 250, now: day(1), calendar: calendar).me?.page
        let fallback = CirclePlanner.snapshot(for: c, myPage: nil, wpm: 250, now: day(1), calendar: calendar).me?.page
        #expect(fromLibrary == 180)
        #expect(fallback == 12)
    }

    @Test func everyMeetingPassedIsComplete() {
        let meetings = [CircleMeeting(date: day(1), throughPage: 400)]
        let c = circle(meetings: meetings, members: [CircleMember(name: "Me", kind: .me)])
        let snap = CirclePlanner.snapshot(for: c, myPage: 400, wpm: 250, now: day(3), calendar: calendar)
        #expect(snap.isComplete)
        #expect(snap.nextMeeting == nil)
        #expect(snap.statusLine == "Every goal has passed. A whole book, read together.")
    }

    @Test func noMeetingsAsksForADate() {
        let c = circle(meetings: [], members: [])
        let snap = CirclePlanner.snapshot(for: c, myPage: nil, wpm: 250, now: day(0), calendar: calendar)
        #expect(!snap.isComplete)
        #expect(snap.statusLine.hasPrefix("No goals yet"))
    }

    // MARK: Goals by a finish date

    @Test func goalsRunWeeklyToTheFinishDate() {
        let finish = day(28, hour: 20)
        let goals = CirclePlanner.goals(pages: 400, startsOn: day(0), finishBy: finish, everyDays: 7, calendar: calendar)
        #expect(goals.map(\.throughPage) == [100, 200, 300, 400])
        let offsets = goals.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: day(0)), to: calendar.startOfDay(for: $0.date)).day ?? 0 }
        #expect(offsets == [7, 14, 21, 28])
        #expect(goals.last?.date == finish)
        #expect(goals.allSatisfy { calendar.component(.hour, from: $0.date) == 20 })
    }

    @Test func aFinishBetweenWeeksStillEndsOnTheDay() {
        // 30 days is about four weeks: three weekly goals, then the end of the book on day 30.
        let goals = CirclePlanner.goals(pages: 400, startsOn: day(0), finishBy: day(30, hour: 20), everyDays: 7, calendar: calendar)
        let offsets = goals.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: day(0)), to: calendar.startOfDay(for: $0.date)).day ?? 0 }
        #expect(offsets == [7, 14, 21, 30])
        #expect(goals.last?.throughPage == 400)
        let single = CirclePlanner.goals(pages: 400, startsOn: day(0), finishBy: day(10, hour: 20), everyDays: 0, calendar: calendar)
        #expect(single.map(\.throughPage) == [400])
        #expect(single.first?.date == day(10, hour: 20))
    }

    // MARK: Logs

    @Test func movesAreLoggedAsSittings() {
        var sam = CircleMember(name: "Sam", remoteID: "_sam", updatedAt: day(0))
        sam.move(to: 30, at: day(0, hour: 20))
        #expect(sam.log == [CircleCheckIn(date: day(0, hour: 20), page: 30, pages: 0)], "joining at page 30 isn’t reading 30 pages")
        sam.move(to: 50, at: day(1, hour: 20))
        sam.move(to: 62, at: day(1, hour: 20).addingTimeInterval(10 * 60))
        #expect(sam.log.count == 2, "a sitting logged page by page is one entry")
        #expect(sam.log.last?.pages == 32)
        #expect(sam.page == 62)
        #expect(sam.updatedAt == day(1, hour: 20).addingTimeInterval(10 * 60))
        for hour in 0..<60 { sam.move(to: 62 + hour + 1, at: day(2).addingTimeInterval(Double(hour) * 3600)) }
        #expect(sam.log.count == CircleCheckIn.logLimit)
    }

    @Test func myPageGoesInWithItsLog() {
        let c = shared(updated: 1, me: 0, sam: 30)
        let started = CircleShareRules.withMyPage(c, page: 0, now: day(2))
        #expect(started.me?.log.map(\.pages) == [0], "the first time is where the reader starts")
        let read = CircleShareRules.withMyPage(started, page: 24, now: day(3))
        #expect(read.me?.log.map(\.pages) == [0, 24])
        #expect(CircleShareRules.withMyPage(read, page: 24, now: day(4)) == read)
    }

    @Test func sessionsAreTheReadersLog() {
        let sessions = [
            ReadingSession(bookID: book.id, startedAt: day(1), seconds: 1200, fromPage: 10, toPage: 30),
            ReadingSession(bookID: "other", startedAt: day(1), seconds: 600, fromPage: 0, toPage: 9),
            ReadingSession(bookID: book.id, startedAt: day(0), seconds: 600, fromPage: 0, toPage: 10),
            ReadingSession(bookID: book.id, startedAt: day(2), seconds: 60, fromPage: 30, toPage: 30),
        ]
        let log = CircleCheckIn.log(from: sessions, bookID: book.id)
        #expect(log.map(\.page) == [10, 30])
        #expect(log.map(\.pages) == [10, 20])
        #expect(log.first?.date == day(0).addingTimeInterval(600))
    }

    @Test func membersFromBeforeLogsStillDecode() throws {
        let json = #"{"id":"00000000-0000-0000-0000-0000000000E2","name":"Sam","kind":"friend","page":30,"paletteToken":"chai","updatedAt":0}"#
        let sam = try JSONDecoder().decode(CircleMember.self, from: Data(json.utf8))
        #expect(sam.log.isEmpty)
        #expect(sam.page == 30)
        var moved = sam
        moved.move(to: 40, at: day(1))
        let back = try JSONDecoder().decode(CircleMember.self, from: JSONEncoder().encode(moved))
        #expect(back == moved)
    }

    // MARK: Standings

    /// Sam reads at seven in the evening, Jo at six.
    private func race() -> ReadingCircle {
        func friend(_ name: String, joined: Int, hour: Int, _ moves: [(Int, Int)]) -> CircleMember {
            var member = CircleMember(name: name, remoteID: "_\(name)", updatedAt: day(joined, hour: hour))
            member.move(to: 0, at: day(joined, hour: hour))
            for (offset, page) in moves { member.move(to: page, at: day(offset, hour: hour)) }
            return member
        }
        let goals = [CircleMeeting(date: day(3), throughPage: 100), CircleMeeting(date: day(10), throughPage: 200), CircleMeeting(date: day(17), throughPage: 400)]
        return circle(meetings: goals, members: [
            CircleMember(name: "You", kind: .me, page: 0, remoteID: "_me"),
            friend("Sam Reed", joined: 0, hour: 19, [(2, 60), (3, 110), (5, 150)]),
            friend("Jo", joined: 1, hour: 18, [(4, 90), (5, 120)]),
        ])
    }

    @Test func standingsRankByPageWithLatelyAndGoals() {
        let c = race()
        let mine = [CircleCheckIn(date: day(1), page: 40, pages: 40), CircleCheckIn(date: day(5, hour: 8), page: 120, pages: 80)]
        let snap = CirclePlanner.snapshot(for: c, myPage: 120, myLog: mine, wpm: 250, now: day(5, hour: 22), calendar: calendar)
        #expect(snap.standings.map(\.member.name) == ["Sam Reed", "You", "Jo"], "level on the page, the reader goes first")
        #expect(snap.members.map(\.rank) == [2, 1, 2])
        let sam = snap.members[1]
        #expect(sam.pagesToday == 40)
        #expect(sam.pagesThisWeek == 150)
        #expect(sam.goalsMet == 1, "Sam reached page 100 on the goal's day")
        #expect(sam.pagesToGoal == 50)
        let jo = snap.members[2]
        #expect(jo.goalsMet == 0, "Jo got to page 100 a day late")
        #expect(snap.me?.goalsMet == 0)
        #expect(snap.me?.pagesToday == 80)
        #expect(snap.standingLine == "You’re 30 pages behind Sam.")
    }

    @Test func standingLinesSayWhereTheReaderIs() {
        func line(me: Int, _ others: [(String, Int)]) -> String? {
            let members = [CircleMember(name: "You", kind: .me)] + others.map { CircleMember(name: $0.0, page: $0.1) }
            let c = circle(meetings: [CircleMeeting(date: day(10), throughPage: 400)], members: members)
            return CirclePlanner.snapshot(for: c, myPage: me, wpm: 250, now: day(1), calendar: calendar).standingLine
        }
        #expect(line(me: 50, []) == nil)
        #expect(line(me: 50, [("Sam", 51)]) == "You’re 1 page behind Sam.")
        #expect(line(me: 50, [("Sam", 70), ("Jo", 70), ("Ada", 90)]) == "You’re 20 pages behind Sam and Jo.")
        #expect(line(me: 90, [("Sam", 70), ("Jo", 40)]) == "You’re out in front, 20 pages ahead of Sam.")
        #expect(line(me: 70, [("Sam", 70)]) == "You and Sam are on the same page.")
        #expect(line(me: 70, [("Sam", 70), ("Jo", 70)]) == "You’re all on the same page.")
        #expect(line(me: 70, [("Sam", 70), ("Jo", 20)]) == "You and Sam are out in front.")
        #expect(line(me: 400, [("Sam", 400)]) == "Everyone has finished the book.")
    }

    @Test func latelyListsSittingsGoalsFinishesAndJoins() {
        var c = race()
        var bea = CircleMember(name: "Bea", remoteID: "_bea", updatedAt: day(4))
        bea.move(to: 380, at: day(4))
        bea.move(to: 400, at: day(5, hour: 7))
        c.members.append(bea)
        let events = CirclePlanner.activity(for: c, myLog: [], now: day(5, hour: 22), calendar: calendar, limit: 10)
        let first = events.first
        #expect(first?.kind == .read(pages: 40), "Sam's sitting tonight is the newest")
        #expect(events.contains { $0.kind == .finished && $0.memberID == bea.id })
        #expect(events.contains { $0.kind == .joined(page: 380) && $0.memberID == bea.id })
        let samGoal = events.first { $0.memberID == c.members[1].id && $0.date == day(3) }
        #expect(samGoal?.kind == .reachedGoal(page: 100, goalDate: day(3)))
        #expect(events.map(\.date) == events.map(\.date).sorted(by: >))
        #expect(CirclePlanner.activity(for: c, myLog: [], now: day(5, hour: 22), calendar: calendar, limit: 2).count == 2)
        // Long ago is not "lately".
        #expect(CirclePlanner.activity(for: c, myLog: [], now: day(40), calendar: calendar).isEmpty)
    }

    // MARK: Prompts

    @Test func promptsFollowWhereTheMeetingFalls() {
        let meetings = CirclePlanner.schedule(pages: 400, firstMeeting: day(3), everyDays: 7, count: 3, calendar: calendar)
        let c = circle(meetings: meetings, members: [])
        let first = CirclePrompts.prompts(for: c, meetingIndex: 0)
        let middle = CirclePrompts.prompts(for: c, meetingIndex: 1)
        let last = CirclePrompts.prompts(for: c, meetingIndex: 2)
        let firstKinds = first.map(\.kind)
        let middleKinds = middle.map(\.kind)
        let lastKinds = last.map(\.kind)
        // Fantasy adds one genre question at the end.
        #expect(firstKinds == [.opening, .opening, .genre])
        #expect(middleKinds == [.middle, .middle, .genre])
        #expect(lastKinds == [.closing, .closing, .genre])
    }

    @Test func promptsAreStableAndShuffleChangesThem() {
        let meetings = CirclePlanner.schedule(pages: 400, firstMeeting: day(3), everyDays: 7, count: 3, calendar: calendar)
        let c = circle(meetings: meetings, members: [])
        let once = CirclePrompts.prompts(for: c, meetingIndex: 1, count: 4).map(\.text)
        let again = CirclePrompts.prompts(for: c, meetingIndex: 1, count: 4).map(\.text)
        #expect(once == again)
        let distinct = Set(once).count
        #expect(distinct == once.count)
        let sets = (0..<6).map { CirclePrompts.prompts(for: c, meetingIndex: 1, count: 2, shuffle: $0).map(\.text) }
        let different = Set(sets).count
        #expect(different > 1)
    }

    @Test func promptsAreWarmWrittenText() {
        let all = CirclePrompts.opening + CirclePrompts.middle + CirclePrompts.closing + CirclePrompts.byGenre.values.flatMap { $0 }
        let shouting = all.filter { $0.contains("!") }
        let straight = all.filter { $0.contains("'") }
        #expect(shouting.isEmpty)
        #expect(straight.isEmpty)
    }

    // MARK: Model

    @Test func initialsAndRoundTrip() throws {
        let sam = CircleMember(name: "Sam Marsh-Lee", updatedAt: day(0))
        let jo = CircleMember(name: "jo")
        let blank = CircleMember(name: "  ")
        #expect(sam.initials == "SM")
        #expect(jo.initials == "J")
        #expect(blank.initials == "?")

        let c = circle(meetings: [CircleMeeting(date: day(3), throughPage: 100, place: "Sam’s", updatedAt: day(0))], members: [sam])
        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(ReadingCircle.self, from: data)
        #expect(back == c)
    }

    @Test func olderFilesWithoutNewFieldsStillDecode() throws {
        let bookJSON = String(decoding: try JSONEncoder().encode(book), as: UTF8.self)
        let json = #"{"id":"00000000-0000-0000-0000-00000000C1C1","book":\#(bookJSON)}"#
        let back = try JSONDecoder().decode(ReadingCircle.self, from: Data(json.utf8))
        #expect(back.meetings.isEmpty)
        #expect(back.members.isEmpty)
        #expect(back.name.isEmpty)
    }

    // MARK: In the library

    private func shared(updated: Int, me: Int, sam: Int, meUpdated: Int = 0, samUpdated: Int = 0) -> ReadingCircle {
        var c = circle(meetings: [CircleMeeting(date: day(7), throughPage: 100, updatedAt: day(0))], members: [
            CircleMember(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E1") ?? UUID(), name: "You", kind: .me, page: me, updatedAt: day(meUpdated)),
            CircleMember(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E2") ?? UUID(), name: "Sam", page: sam, updatedAt: day(samUpdated)),
        ])
        c.updatedAt = day(updated)
        return c
    }

    @Test func twoPeopleReadingAtOnceBothKeepTheirPages() {
        // This phone moved its own page (and so the circle); Sam's phone moved Sam's, a little earlier.
        let mine = shared(updated: 2, me: 60, sam: 0, meUpdated: 2)
        let sams = shared(updated: 1, me: 0, sam: 45, samUpdated: 1)
        var a = LeafData(), b = LeafData()
        a.circles = [mine]
        b.circles = [sams]
        let merged = a.merged(with: b, now: day(3))
        #expect(merged.circles.count == 1)
        #expect(merged.circles.first?.members.map(\.page) == [60, 45])
        #expect(merged.circles == b.merged(with: a, now: day(3)).circles)
        #expect(merged.merged(with: b, now: day(3)).circles == merged.circles)
    }

    @Test func aRemovedFriendStaysRemovedAndADeletedCircleStaysDeleted() {
        let before = shared(updated: 1, me: 10, sam: 30, samUpdated: 1)
        var after = before
        after.members.removeAll { $0.kind != .me }
        after.updatedAt = day(2)
        var a = LeafData(), b = LeafData()
        a.circles = [after]
        b.circles = [before]
        #expect(a.merged(with: b, now: day(3)).circles.first?.members.count == 1)

        var gone = LeafData()
        gone.tombstones = [Tombstone(kind: .circle, key: before.id.uuidString, deletedAt: day(2))]
        #expect(gone.merged(with: b, now: day(3)).circles.isEmpty)
        // A change after the deletion brings it back, as a book re-added after a delete does.
        var later = before
        later.updatedAt = day(4)
        b.circles = [later]
        #expect(gone.merged(with: b, now: day(5)).circles.count == 1)
    }

    @Test func aTieOnTheStampPicksTheSameCircleInAnyOrder() {
        var x = shared(updated: 1, me: 5, sam: 0, meUpdated: 1)
        var y = shared(updated: 1, me: 0, sam: 7, samUpdated: 1)
        var z = shared(updated: 1, me: 0, sam: 0)
        x.name = "Club A"
        y.name = "Club B"
        z.name = "Club C"
        func data(_ c: ReadingCircle) -> LeafData { var d = LeafData(); d.circles = [c]; return d }
        let now = day(2)
        let left = data(x).merged(with: data(y), now: now).merged(with: data(z), now: now)
        let right = data(x).merged(with: data(y).merged(with: data(z), now: now), now: now)
        let swapped = data(z).merged(with: data(x), now: now).merged(with: data(y), now: now)
        #expect(left.circles == right.circles)
        #expect(left.circles == swapped.circles)
        #expect(left.circles.first?.members.map(\.page) == [5, 7])
    }

    @Test func circlesTravelAsRecordsAndInBackups() throws {
        let c = shared(updated: 1, me: 12, sam: 30)
        let record = try #require(SyncRecordMapper.record(for: .circle(c)))
        #expect(record.type == .circle)
        #expect(record.type.rawValue == "LeafCircle")
        #expect(record.name == "circle." + c.id.uuidString)
        #expect(SyncRecordName(record.name) == .circle(c.id))
        #expect(SyncRecordMapper.entity(from: record) == .circle(c))

        var old = LeafData(), new = LeafData()
        new.circles = [c]
        #expect(SyncDiff.changes(from: old, to: new).saves == [record.name])
        old = new
        new.circles = []
        new.tombstones = [Tombstone(kind: .circle, key: c.id.uuidString, deletedAt: day(2))]
        let gone = SyncDiff.changes(from: old, to: new)
        #expect(gone.deletes == [record.name])
        #expect(gone.saves == [SyncRecordName.tombstone(.circle, c.id.uuidString).string])

        var library = LeafData()
        library.circles = [c]
        let bytes = try LeafBackup.encode(library, exportedAt: day(3))
        let back = try LeafBackup.decode(bytes)
        #expect(back.circles == [c])
        #expect(LeafBackup.preview(of: back, against: LeafData()).circles == 1)
        #expect(!LeafBackup.preview(of: back, against: LeafData()).isEmpty)
    }

    // MARK: Sharing

    @Test func eachDeviceWorksOutWhoIsMe() {
        var owners = shared(updated: 1, me: 40, sam: 10)
        owners = CircleShareRules.claimingMe(owners, me: "_owner", now: day(2))
        #expect(owners.me?.remoteID == "_owner")
        #expect(owners.updatedAt == day(2))
        #expect(CircleShareRules.claimingMe(owners, me: "_owner", now: day(3)) == owners, "claiming twice changes nothing")

        // Sam accepts: everyone who arrived is a friend there, and Sam joins first, as "me".
        let joined = CircleShareRules.joining(owners, me: "_sam", name: "Sam Reed", paletteToken: "rose", now: day(4))
        #expect(joined.members.map(\.name) == ["Sam Reed", "You", "Sam"])
        #expect(joined.members.map(\.kind) == [.me, .friend, .friend])
        #expect(joined.me?.remoteID == "_sam")
        #expect(joined.updatedAt == day(4))
        #expect(CircleShareRules.joining(joined, me: "_sam", name: "Sam Reed", paletteToken: "rose", now: day(5)) == joined)

        // Back on the owner's phone the owner is "me" again and Sam is a friend.
        let back = CircleShareRules.localized(joined, me: "_owner")
        #expect(back.members.first?.remoteID == "_owner")
        #expect(back.members.filter { $0.kind == .me }.count == 1)
        #expect(back.members.first { $0.remoteID == "_sam" }?.kind == .friend)
        // A circle that was never shared is left alone.
        let local = shared(updated: 1, me: 0, sam: 0)
        #expect(CircleShareRules.localized(local, me: "_anyone") == local)
    }

    @Test func myPageGoesIntoMyOwnMemberOnly() {
        let c = shared(updated: 1, me: 10, sam: 30)
        let moved = CircleShareRules.withMyPage(c, page: 900, now: day(2))
        #expect(moved.members.map(\.page) == [400, 30])
        #expect(moved.updatedAt == day(2))
        #expect(CircleShareRules.withMyPage(moved, page: 400, now: day(3)) == moved)
        #expect(CircleShareRules.withMyPage(c, page: nil, now: day(3)) == c)
    }

    @Test func zoneNamesRoundTrip() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-00000000C1C1") ?? UUID()
        #expect(CircleShareRules.zoneName(for: id) == "Circle-00000000-0000-0000-0000-00000000C1C1")
        #expect(CircleShareRules.circleID(inZone: CircleShareRules.zoneName(for: id)) == id)
        #expect(CircleShareRules.circleID(inZone: "LeafZone") == nil)
    }

    @Test func aLibraryFromBeforeCirclesStillLoads() throws {
        let back = try JSONDecoder().decode(LeafData.self, from: Data(#"{"version":2,"items":[]}"#.utf8))
        #expect(back.circles.isEmpty)
    }
}
