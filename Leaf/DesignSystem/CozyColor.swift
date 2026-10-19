import SwiftUI
import UIKit

/// The cozy palette (NEXT.md section 6): tea-stained paper, chai, matcha, rooibos, steam, lamp amber and rose.
/// Warm tints for atmosphere only (tea in the cup, tea-ring stamps, the nook's light). Ink and the one green
/// accent still do the work, and none of these ever carries text.
///
/// The data layer names colours with `CozyPalette` tokens; `CozyColor.color(for:)` turns a token into a colour.
enum CozyColor {
    /// Tea-stained paper: the nook's table, quiet wells.
    static let teaPaper = Color(uiColor: .leafDynamic(light: 0xEADFCB, dark: 0x2A241D))
    static let chai = Color(uiColor: .leafDynamic(light: 0xB58456, dark: 0xC99A6E))
    static let matcha = Color(uiColor: .leafDynamic(light: 0x7F9C5A, dark: 0x9DB97A))
    static let rooibos = Color(uiColor: .leafDynamic(light: 0xA9532F, dark: 0xCC714C))
    /// Steam. A warm grey on light paper (white steam would vanish), nearly white at night.
    static let steam = Color(uiColor: .leafDynamic(light: 0x9A8F80, dark: 0xE8E1D3))
    /// Lamp amber: the glow in the nook.
    static let amber = Color(uiColor: .leafDynamic(light: 0xD99A42, dark: 0xE5AA55))
    static let rose = Color(uiColor: .leafDynamic(light: 0xB65A6B, dark: 0xD4808F))
    /// The brown of a dried tea ring on paper.
    static let teaRing = Color(uiColor: .leafDynamic(light: 0x9C6B3F, dark: 0xC9955F))

    /// The colour for a `CozyPalette` token. Unknown tokens fall back to tea-stained paper.
    static func color(for token: String) -> Color {
        switch token {
        case CozyPalette.chai: chai
        case CozyPalette.matcha: matcha
        case CozyPalette.rooibos: rooibos
        case CozyPalette.steam: steam
        case CozyPalette.amber: amber
        case CozyPalette.rose: rose
        default: teaPaper
        }
    }

    /// What the tea looks like in the cup. Liquor keeps its colour in dark mode, like the covers do.
    static func liquor(for tea: Tea) -> Color {
        switch tea.paletteToken {
        case CozyPalette.amber: Color(hex: 0xB8742E)
        case CozyPalette.chai: Color(hex: 0xBE8C5C)
        case CozyPalette.matcha: Color(hex: 0x8AA24C)
        case CozyPalette.rooibos: Color(hex: 0xA9502B)
        case CozyPalette.rose: Color(hex: 0xA8404F)
        case CozyPalette.steam: Color(hex: 0xD8C27E)
        default: Color(hex: 0xC9A35E)
        }
    }
}

#Preview("Cozy colours") {
    let tokens: [(String, Color)] = [
        ("teaPaper", CozyColor.teaPaper), ("chai", CozyColor.chai), ("matcha", CozyColor.matcha),
        ("rooibos", CozyColor.rooibos), ("steam", CozyColor.steam), ("amber", CozyColor.amber),
        ("rose", CozyColor.rose), ("teaRing", CozyColor.teaRing),
    ]
    return VStack(alignment: .leading, spacing: 8) {
        ForEach(tokens.indices, id: \.self) { index in
            HStack(spacing: 12) {
                Circle()
                    .fill(tokens[index].1)
                    .frame(width: 28, height: 28)
                Text(tokens[index].0).leafStyle(.data)
            }
        }
        HStack(spacing: 6) {
            ForEach(TeaCatalog.all) { tea in
                Circle().fill(CozyColor.liquor(for: tea)).frame(width: 16, height: 16)
            }
        }
    }
    .padding(20)
    .paperBackground()
}
