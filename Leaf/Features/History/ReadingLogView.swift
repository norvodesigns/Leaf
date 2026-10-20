import SwiftUI
import UniformTypeIdentifiers

/// Every sitting and every finish (`ReadingLog`), newest first, by month: filter by kind and range, search by title
/// or author, and export what's showing as CSV or Markdown.
struct ReadingLogView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var show: ReadingLog.Show = .everything
    @State private var range: InsightsRange = .allTime
    @State private var query = ""

    private var entries: [ReadingLog.Entry] {
        let interval = range.interval(data: store.data, now: store.now, calendar: store.calendar)
        let filter = ReadingLog.Filter(show: show, query: query, range: range == .allTime ? nil : interval)
        return ReadingLog.entries(data: store.data, filter: filter, calendar: store.calendar)
    }

    var body: some View {
        let entries = self.entries
        let months = groupedByMonth(entries)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                controls
                Text(totalsLine(entries))
                    .leafStyle(.caption)
                    .padding(.top, Space.s)
                    .padding(.bottom, Space.m)
                if entries.isEmpty {
                    Text(query.isEmpty ? "Nothing logged here yet." : "Nothing matches “\(query)”.")
                        .leafStyle(.body, color: .inkSecondary)
                        .padding(.top, Space.l)
                }
                ForEach(months, id: \.title) { month in
                    SectionHeader(month.title, topSpacing: Space.l)
                    ForEach(month.entries) { entry in
                        LogRow(entry: entry, calendar: store.calendar)
                        Divider().overlay(Color.hairline)
                    }
                }
            }
            .leafMargins()
            .padding(.bottom, Space.xxxl)
        }
        .scrollIndicators(.hidden)
        .paperBackground()
        .navigationTitle("Reading log")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Title or author")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(
                        item: ReadingLogCSV(entries: entries, calendar: store.calendar, name: ReadingLogExport.fileName(extension: "csv", now: store.now, calendar: store.calendar)),
                        preview: SharePreview("Reading log (CSV)")
                    ) {
                        Label("Export as CSV", systemImage: "tablecells")
                    }
                    ShareLink(
                        item: ReadingLogMarkdown(entries: entries, calendar: store.calendar, name: ReadingLogExport.fileName(extension: "md", now: store.now, calendar: store.calendar)),
                        preview: SharePreview("Reading log (Markdown)")
                    ) {
                        Label("Export as Markdown", systemImage: "doc.plaintext")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(entries.isEmpty)
                .accessibilityLabel("Export")
            }
        }
        .task {
            applyStage()
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Picker("Show", selection: $show) {
                ForEach(ReadingLog.Show.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: show) { _, _ in Haptics.shared.selection() }
            Menu {
                Picker("Range", selection: $range) {
                    ForEach(InsightsRange.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } label: {
                HStack(spacing: Space.xs) {
                    Text(range.title)
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .leafStyle(.ui, color: .accent)
                .frame(minHeight: Space.hitTarget)
            }
            .accessibilityLabel("Range, \(range.title)")
        }
    }

    /// "212 sittings · 98 h · 14 finishes"
    private func totalsLine(_ entries: [ReadingLog.Entry]) -> String {
        let totals = ReadingLog.totals(entries)
        var parts: [String] = []
        if totals.sittings > 0 {
            parts.append("\(LeafFormat.number(totals.sittings)) \(totals.sittings == 1 ? "sitting" : "sittings")")
            parts.append(LeafFormat.duration(minutes: totals.minutes))
        }
        if totals.finishes > 0 { parts.append("\(totals.finishes) \(totals.finishes == 1 ? "finish" : "finishes")") }
        return parts.joined(separator: " · ")
    }

    private struct Month {
        var title: String
        var entries: [ReadingLog.Entry]
    }

    private func groupedByMonth(_ entries: [ReadingLog.Entry]) -> [Month] {
        var months: [Month] = []
        for entry in entries {
            let title = LeafFormat.format(entry.date, template: "MMMMyyyy", calendar: store.calendar)
            if months.last?.title == title {
                months[months.count - 1].entries.append(entry)
            } else {
                months.append(Month(title: title, entries: [entry]))
            }
        }
        return months
    }

    /// Screenshot staging: "finished" shows finishes only, "search" searches for a title.
    private func applyStage() {
        guard let stage = router.historyStage else { return }
        router.historyStage = nil
        switch stage {
        case "finished": show = .finishes
        case "search": query = "hobbit"
        default: break
        }
    }
}

/// One line of the log.
private struct LogRow: View {
    let entry: ReadingLog.Entry
    let calendar: Calendar

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Text(LeafFormat.format(entry.date, template: "EEEd", calendar: calendar))
                .leafStyle(.data, color: .inkSecondary)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(entry.title)
                    .leafStyle(.headline)
                    .lineLimit(2)
                Text(detail)
                    .leafStyle(.caption, color: entry.isFinish ? .accent : nil)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.s)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        switch entry.kind {
        case .sitting(let minutes, let from, let to, let tea, let isTyped):
            var parts = [LeafFormat.duration(minutes: minutes)]
            if to > from { parts.append(LeafFormat.pages(from: from + 1, to: to)) }
            if let tea { parts.append(tea) }
            if isTyped { parts.append("typed in") }
            return parts.joined(separator: " · ")
        case .finished(let rating, let days, let times):
            var parts = [times > 1 ? "Finished, \(ReadsHistory.ordinal(times).lowercased())" : "Finished"]
            if let days { parts.append(days == 1 ? "in a day" : "in \(days) days") }
            if let rating { parts.append(rating == 1 ? "1 leaf" : "\(rating) leaves") }
            return parts.joined(separator: " · ")
        }
    }
}

// MARK: - Export files

/// The log as a CSV file, written only when it is shared.
struct ReadingLogCSV: Transferable {
    var entries: [ReadingLog.Entry]
    var calendar: Calendar
    var name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            SentTransferredFile(try ExportFiles.write(ReadingLogExport.csv(file.entries, calendar: file.calendar), named: file.name))
        }
    }
}

/// The log as a Markdown file, written only when it is shared.
struct ReadingLogMarkdown: Transferable {
    var entries: [ReadingLog.Entry]
    var calendar: Calendar
    var name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { file in
            let text = ReadingLogExport.markdown(file.entries, title: "Reading log", calendar: file.calendar)
            return SentTransferredFile(try ExportFiles.write(text, named: file.name))
        }
    }
}

/// The whole library as a backup file, written only when it is shared.
struct LibraryBackupFile: Transferable {
    var data: LeafData
    var exportedAt: Date
    var name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            let bytes = try LeafBackup.encode(file.data, exportedAt: file.exportedAt)
            return SentTransferredFile(try ExportFiles.write(bytes, named: file.name))
        }
    }
}

enum ExportFiles {
    /// Writes into a fresh folder in the temporary directory, so the shared file keeps its friendly name.
    static func write(_ text: String, named name: String) throws -> URL {
        try write(Data(text.utf8), named: name)
    }

    static func write(_ bytes: Data, named name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Exports-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try bytes.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
