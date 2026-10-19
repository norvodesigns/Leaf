import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// What a cover leaves behind as atmosphere: a heavily blurred bitmap of it, a 3×3 grid of its colours for a mesh
/// gradient, and their average (the flat tint for Reduce Transparency).
struct CoverBackdropArt {
    let blurred: UIImage?
    /// Nine colours, row by row from the top left.
    let mesh: [Color]
    let average: Color
}

/// Renders backdrops once per book and keeps them (NEXT.md section 7: blur pre-rendered bitmaps, never live). The cover
/// is drawn small (60×90 pt) and blurred with Core Image, so a full-screen backdrop costs one cheap image.
@MainActor
final class CoverBackdropRenderer {
    static let shared = CoverBackdropRenderer()

    private let cache = NSCache<NSString, Box>()
    private let context = CIContext()
    private static let size = CGSize(width: 60, height: 90)

    private final class Box {
        let art: CoverBackdropArt
        init(_ art: CoverBackdropArt) { self.art = art }
    }

    private init() {
        cache.countLimit = 40
    }

    /// The backdrop for `book`, from its scan when one can be had, else from its generated cover.
    func backdrop(for book: Book) async -> CoverBackdropArt {
        // Any size already on screen will do (it is blurred to nothing); fetch the small one otherwise.
        let url = BookCover.imageURL(for: book, size: .m)
        var scan = [BookCover.Size.xl, .l, .m].lazy
            .compactMap { BookCover.imageURL(for: book, size: $0) }
            .compactMap { CoverImageCache.shared.cachedImage(for: $0) }
            .first
        if scan == nil, let url { scan = await CoverImageCache.shared.image(for: url) }
        let key = "\(book.id)|\(scan == nil ? "generated" : url?.absoluteString ?? "scan")" as NSString
        if let hit = cache.object(forKey: key) { return hit.art }
        let art = render(book, scan: scan)
        cache.setObject(Box(art), forKey: key)
        return art
    }

    /// The colours alone, without waiting for a scan (for a first frame).
    static func paletteMesh(for book: Book) -> [Color] {
        let palette = CoverPalette(book: book)
        let a = palette.background
        let b = palette.rule
        return [a, b, a, a, a, b, b, a, a]
    }

    private func render(_ book: Book, scan: UIImage?) -> CoverBackdropArt {
        let base = baseImage(book, scan: scan)
        let mesh = base.flatMap { Self.grid(of: $0) } ?? Self.paletteMesh(for: book)
        return CoverBackdropArt(
            blurred: base.flatMap { blur($0) },
            mesh: mesh,
            average: Self.average(base) ?? CoverPalette(book: book).background
        )
    }

    private func baseImage(_ book: Book, scan: UIImage?) -> UIImage? {
        let size = Self.size
        let content: AnyView
        if let scan {
            content = AnyView(Image(uiImage: scan).resizable().scaledToFill().frame(width: size.width, height: size.height).clipped())
        } else {
            content = AnyView(GeneratedCover(book: book, showsFinish: false).frame(width: size.width, height: size.height))
        }
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return renderer.uiImage
    }

    private func blur(_ image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = input.clampedToExtent()
        filter.radius = 16
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let cgImage = context.createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// The image squeezed to `side` × `side` pixels, read back as colours, top row first.
    static func grid(of image: UIImage, side: Int = 3) -> [Color]? {
        guard let cgImage = image.cgImage, side > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        return (0..<(side * side)).map { index in
            Color(
                red: Double(pixels[index * 4]) / 255,
                green: Double(pixels[index * 4 + 1]) / 255,
                blue: Double(pixels[index * 4 + 2]) / 255
            )
        }
    }

    private static func average(_ image: UIImage?) -> Color? {
        guard let image, let one = grid(of: image, side: 1) else { return nil }
        return one.first
    }
}

/// A cover turned into atmosphere (NEXT.md section 7): a mesh gradient from its colours, the pre-rendered blur over it,
/// and a paper scrim that rises toward the bottom so text on it stays legible. Reduce Transparency gets a flat tint of
/// the cover's average colour. Nothing animates; the art is rendered once per book and cached.
struct BlurredCoverBackdrop: View {
    let book: Book
    /// How much paper covers the middle; the bottom is always paper, so content below blends in.
    var scrim: Double = 0.5

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @State private var art: CoverBackdropArt?

    private static let points: [SIMD2<Float>] = [
        SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
        SIMD2(0, 0.5), SIMD2(0.5, 0.5), SIMD2(1, 0.5),
        SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1),
    ]

    var body: some View {
        ZStack {
            Color.paper
            if reduceTransparency {
                (art?.average ?? CoverPalette(book: book).background)
                    .opacity(0.18)
            } else {
                MeshGradient(width: 3, height: 3, points: Self.points, colors: art?.mesh ?? CoverBackdropRenderer.paletteMesh(for: book))
                    .opacity(colorScheme == .dark ? 0.5 : 0.38)
                if let blurred = art?.blurred {
                    Image(uiImage: blurred)
                        .resizable()
                        .scaledToFill()
                        .opacity(colorScheme == .dark ? 0.42 : 0.4)
                        .transition(.opacity)
                }
            }
            LinearGradient(
                stops: [
                    .init(color: Color.paper.opacity(0.1), location: 0),
                    .init(color: Color.paper.opacity(scrim), location: 0.55),
                    .init(color: Color.paper, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: BookCover.imageURL(for: book, size: .m)?.absoluteString ?? book.id) {
            let rendered = await CoverBackdropRenderer.shared.backdrop(for: book)
            withAnimation(Motion.coverFade) { art = rendered }
        }
    }
}

#Preview("Cover backdrop") {
    VStack(spacing: 0) {
        ZStack {
            BlurredCoverBackdrop(book: DemoData.hobbit)
            BookCover(book: DemoData.hobbit, size: .l)
        }
        .frame(height: 320)
        ZStack {
            BlurredCoverBackdrop(book: DemoData.piranesi)
            Text("Piranesi").leafStyle(.masthead)
        }
        .frame(height: 240)
    }
    .paperBackground()
}

#Preview("Cover backdrop · dark") {
    ZStack {
        BlurredCoverBackdrop(book: DemoData.circe)
        BookCover(book: DemoData.circe, size: .l)
    }
    .frame(height: 360)
    .paperBackground()
    .preferredColorScheme(.dark)
}
