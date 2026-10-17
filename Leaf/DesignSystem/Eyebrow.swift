import SwiftUI

/// Small uppercase label: `eyebrow` style (caption2 semibold, tracking 1.5, `inkTertiary`).
/// Pass sentence case; it's uppercased on screen and VoiceOver reads it naturally.
struct Eyebrow: View {
    let text: String
    var color: Color?

    init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text).leafStyle(.eyebrow, color: color)
    }
}

/// A running-order numeral, "01", in `index` `inkTertiary`, at least 40 pt wide.
struct IndexNumeral: View {
    let number: Int

    init(_ number: Int) {
        self.number = number
    }

    var body: some View {
        Text(String(format: "%02d", number))
            .leafStyle(.index)
            .frame(minWidth: 40, alignment: .leading)
            .accessibilityLabel("Number \(number)")
    }
}

/// Leader dots between a title and a date: 2 pt `inkFaint` dots every 6 pt. Hidden from VoiceOver.
/// Sits on the text baseline inside an `HStack(alignment: .firstTextBaseline)`.
struct LeaderDots: View {
    init() {}

    var body: some View {
        DotLine()
            .stroke(Color.inkFaint, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0, 6]))
            .frame(minWidth: 12, maxWidth: .infinity)
            .frame(height: 2)
            .accessibilityHidden(true)
    }
}

private struct DotLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 1, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.midY))
        return path
    }
}

#Preview("Labels") {
    VStack(alignment: .leading, spacing: Space.l) {
        Eyebrow("Next in the running order")
        Eyebrow("Goal met · keep going", color: .accent)
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            IndexNumeral(1)
            Text("Piranesi").leafStyle(.headline)
            LeaderDots()
            Text("3 Dec").leafStyle(.data)
        }
    }
    .leafMargins()
    .frame(maxHeight: .infinity)
    .paperBackground()
}
