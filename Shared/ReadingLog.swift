import Foundation

/// Every sitting and every finish, newest first, filtered and searched. Pure, so the list, the CSV and the Markdown
/// export always agree.
enum ReadingLog {
    enum Show: String, CaseIterable, Hashable, Sendable {
        case everything, sittings, finishes

        var title: String {
            switch self {
            case .everything: return "Everything"
            case .sittings: return "Sittings"
            case .finishes: return "Finished"
            }
        }
    }

    struct Filter: Hashable, Sendable {
        var show: Show = .everything
        /// Matched against title and author, ignoring case and accents.
        var query: String = ""
        /// Only entries from this range (inclusive of the whole last day), or all when nil.
        var range: DateInterval?

        init(show: Show = .everything, query: String = "", range: DateInterval? = nil) {
            self.show = show
            self.query = query
            self.range = range
        }
    }

    struct Entry: Identifiable, Hashable, Sendable {
        enum Kind: Hashable, Sendable {
            case sitting(minutes: Double, fromPage: Int, toPage: Int, teaName: String?, isTyped: Bool)
            /// `times` is which finish of the book this is (2 for a second read).
            case finished(rating: Int?, days: Int?, times: Int)
        }

        var id: String
        var date: Date
        var bookID: String
        var title: String
        var author: String
        var kind: Kind

        var isFinish: Bool {
            if case .finished = kind { return true }
            return false
        }
    }

    static func entries(data: LeafData, filter: Filter = Filter(), calendar: Calendar) -> [Entry] {
        var books: [String: (title: String, author: String)] = [:]
        for item in data.items where books[item.id] == nil { books[item.id] = (item.book.title, item.book.author) }
        for entry in data.journal where books[entry.bookID] == nil { books[entry.bookID] = (entry.bookTitle, entry.bookAuthor) }

        var out: [Entry] = []
        if filter.show != .finishes {
            for session in data.sessions {
                let book = books[session.bookID] ?? ("A book", "")
                let teaName: String? = TeaShelf.tea(id: session.teaID, cabinet: data.cabinet)?.name
                let kind = Entry.Kind.sitting(
                    minutes: max(0, session.seconds) / 60, fromPage: session.fromPage, toPage: session.toPage,
                    teaName: teaName, isTyped: session.kind == .manual
                )
                out.append(Entry(id: "session.\(session.id.uuidString)", date: session.startedAt, bookID: session.bookID, title: book.title, author: book.author, kind: kind))
            }
        }
        if filter.show != .sittings {
            for item in data.items {
                for (index, read) in item.readThroughs.enumerated() {
                    let kind = Entry.Kind.finished(rating: read.rating, days: read.days(calendar: calendar), times: index + 1)
                    out.append(Entry(id: "finish.\(read.id.uuidString)", date: read.finishedAt, bookID: item.id, title: item.book.title, author: item.book.author, kind: kind))
                }
            }
        }

        let query = fold(filter.query)
        if !query.isEmpty {
            out = out.filter { fold($0.title).contains(query) || fold($0.author).contains(query) }
        }
        if let range = filter.range {
            let first = calendar.startOfDay(for: range.start)
            let lastDay = calendar.startOfDay(for: range.end)
            let after = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? range.end
            out = out.filter { $0.date >= first && $0.date < after }
        }
        return out.sorted { (a: Entry, b: Entry) -> Bool in
            if a.date != b.date { return a.date > b.date }
            return a.id < b.id
        }
    }

    /// Lowercased, without accents, trimmed.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Totals for the list's header: sittings, minutes, finishes.
    static func totals(_ entries: [Entry]) -> (sittings: Int, minutes: Double, finishes: Int) {
        var sittings = 0
        var minutes = 0.0
        var finishes = 0
        for entry in entries {
            switch entry.kind {
            case .sitting(let m, _, _, _, _):
                sittings += 1
                minutes += m
            case .finished:
                finishes += 1
            }
        }
        return (sittings, minutes, finishes)
    }
}

// MARK: - Export

/// The reading log as CSV (for spreadsheets) or Markdown (for notes apps). Dates are written in the calendar's time
/// zone with fixed English formats, so an export reads the same on every device.
enum ReadingLogExport {
    static let csvHeader = ["Type", "Date", "Time", "Title", "Author", "Minutes", "From page", "To page", "Pages", "Tea", "Rating", "Read"]

    static func csv(_ entries: [ReadingLog.Entry], calendar: Calendar) -> String {
        let day = formatter("yyyy-MM-dd", calendar: calendar)
        let time = formatter("HH:mm", calendar: calendar)
        var lines = [csvHeader.map(field).joined(separator: ",")]
        for entry in entries {
            var row: [String]
            switch entry.kind {
            case .sitting(let minutes, let from, let to, let tea, let isTyped):
                row = [
                    isTyped ? "Sitting (typed in)" : "Sitting", day.string(from: entry.date), time.string(from: entry.date),
                    entry.title, entry.author, number(minutes), "\(from)", "\(to)", "\(max(0, to - from))", tea ?? "", "", "",
                ]
            case .finished(let rating, _, let times):
                row = [
                    "Finished", day.string(from: entry.date), time.string(from: entry.date), entry.title, entry.author,
                    "", "", "", "", "", rating.map(String.init) ?? "", "\(times)",
                ]
            }
            lines.append(row.map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// One field, quoted when it holds a comma, a quote or a line break (RFC 4180), with a leading formula character
    /// defused so a spreadsheet never runs a title as a formula.
    static func field(_ value: String) -> String {
        var text = value
        if let first = text.first, "=+-@".contains(first), Double(text) == nil { text = "'" + text }
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func markdown(_ entries: [ReadingLog.Entry], title: String, calendar: Calendar) -> String {
        let month = formatter("MMMM yyyy", calendar: calendar)
        let day = formatter("EEE d MMM", calendar: calendar)
        var out = "# \(markdownEscape(title))\n"
        var currentMonth: String?
        for entry in entries {
            let heading = month.string(from: entry.date)
            if heading != currentMonth {
                out += "\n## \(heading)\n\n"
                currentMonth = heading
            }
            let book = "*\(markdownEscape(entry.title))*" + (entry.author.isEmpty ? "" : " by \(markdownEscape(entry.author))")
            switch entry.kind {
            case .sitting(let minutes, let from, let to, let tea, _):
                var parts = ["\(day.string(from: entry.date))", book, "\(Int(minutes.rounded())) min"]
                if to > from { parts.append(LeafFormat.pages(from: from + 1, to: to)) }
                if let tea { parts.append(markdownEscape(tea)) }
                out += "- " + parts.joined(separator: " · ") + "\n"
            case .finished(let rating, let days, let times):
                var parts = ["\(day.string(from: entry.date))", "Finished \(book)"]
                if times > 1 { parts.append(ReadsHistory.ordinal(times).lowercased()) }
                if let days { parts.append(days == 1 ? "in a day" : "in \(days) days") }
                if let rating { parts.append("rated \(rating) of 5") }
                out += "- " + parts.joined(separator: " · ") + "\n"
            }
        }
        return out
    }

    /// Backslashes the characters Markdown would read as formatting.
    static func markdownEscape(_ text: String) -> String {
        var out = ""
        for character in text {
            if "\\`*_[]#<>|".contains(character) { out.append("\\") }
            out.append(character)
        }
        return out
    }

    /// "Leaf reading log 2026-10-20.csv"
    static func fileName(extension ext: String, now: Date, calendar: Calendar) -> String {
        "Leaf reading log \(formatter("yyyy-MM-dd", calendar: calendar).string(from: now)).\(ext)"
    }

    private static func number(_ minutes: Double) -> String {
        let rounded = (minutes * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
