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
        #expect(snap.statusLine == "The meeting is today, up to page 200. You’re ready.")
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
        #expect(snap.statusLine == "The last meeting has been. A whole book, read together.")
    }

    @Test func noMeetingsAsksForADate() {
        let c = circle(meetings: [], members: [])
        let snap = CirclePlanner.snapshot(for: c, myPage: nil, wpm: 250, now: day(0), calendar: calendar)
        #expect(!snap.isComplete)
        #expect(snap.statusLine.hasPrefix("No meetings yet"))
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
}
