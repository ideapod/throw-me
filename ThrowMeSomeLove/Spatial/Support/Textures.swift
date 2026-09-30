import RealityKit
import SwiftUI

/// Renders small SwiftUI drawings into RealityKit textures and caches them.
/// Placeholder media (photos, notes) and the wrapping paper are all drawn this way.
enum Textures {
    private static var cache: [String: TextureResource] = [:]

    static func render<V: View>(_ key: String, size: CGSize, @ViewBuilder _ view: () -> V) -> TextureResource? {
        if let hit = cache[key] { return hit }
        let renderer = ImageRenderer(content: view().frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let texture = try? TextureResource(image: image, options: .init(semantic: .color)) else { return nil }
        cache[key] = texture
        return texture
    }

    static var wrappingPaper: TextureResource? {
        render("wrap", size: CGSize(width: 256, height: 256)) { WrappingPaper() }
    }

    static func photo(seed: UInt32) -> TextureResource? {
        render("photo-\(seed)", size: CGSize(width: 256, height: 256)) { PlaceholderPhoto(seed: seed) }
    }

    static var emptyPhoto: TextureResource? {
        render("empty-photo", size: CGSize(width: 256, height: 256)) {
            ZStack {
                Color(white: 0.88)
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(Color(white: 0.55))
            }
        }
    }

    static var emptyNote: TextureResource? {
        render("empty-note", size: CGSize(width: 256, height: 256)) {
            ZStack {
                Color(uiColor: Palette.paper)
                VStack(spacing: 10) {
                    Image(systemName: "mic")
                        .font(.system(size: 44, weight: .light))
                    Text("tap to write")
                        .font(.custom("Noteworthy-Bold", size: 30))
                }
                .foregroundStyle(Palette.ink.opacity(0.35))
            }
        }
    }

    static func note(_ text: String, seed: UInt32) -> TextureResource? {
        render("note-\(seed)-\(text)", size: CGSize(width: 256, height: 256)) { NoteCard(text: text, seed: seed) }
    }
}

/// Kraft paper scattered with hand-drawn white hearts and dots.
struct WrappingPaper: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.kraft))
            var rng = SeededRandom(7)
            let heart = ctx.resolve(Image(systemName: "heart.fill"))
            for row in 0..<5 {
                for col in 0..<5 {
                    let jitter = CGPoint(x: CGFloat(rng.range(-8...8)), y: CGFloat(rng.range(-8...8)))
                    let offset: CGFloat = row.isMultiple(of: 2) ? 0 : 25
                    let p = CGPoint(x: CGFloat(col) * 51 + 25 + offset + jitter.x, y: CGFloat(row) * 51 + 25 + jitter.y)
                    var c = ctx
                    c.translateBy(x: p.x, y: p.y)
                    c.rotate(by: .degrees(Double(rng.range(-25...25))))
                    c.opacity = 0.85
                    if (row + col).isMultiple(of: 2) {
                        c.draw(heart, in: CGRect(x: -9, y: -8, width: 18, height: 16))
                    } else {
                        c.fill(Path(ellipseIn: CGRect(x: -3, y: -3, width: 6, height: 6)), with: .color(.white))
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }
}

/// A dreamy little landscape standing in for a real photo until import exists.
struct PlaceholderPhoto: View {
    let seed: UInt32

    var body: some View {
        var rng = SeededRandom(seed)
        let hue = Double(rng.unit())
        let sunX = CGFloat(rng.range(0.2...0.8))
        let hills = (0..<3).map { _ in (CGFloat(rng.range(0.45...0.75)), CGFloat(rng.range(0.1...0.9))) }
        return Canvas { ctx, size in
            let sky = Gradient(colors: [
                Color(hue: hue, saturation: 0.35, brightness: 0.95),
                Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.45, brightness: 1.0),
            ])
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.fill(Path(ellipseIn: CGRect(x: sunX * size.width - 28, y: size.height * 0.18, width: 56, height: 56)),
                     with: .color(Color(red: 1, green: 0.93, blue: 0.7)))
            for (i, hill) in hills.enumerated() {
                var path = Path()
                let top = hill.0 * size.height + CGFloat(i) * 22
                path.move(to: CGPoint(x: 0, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: top + 30))
                path.addQuadCurve(to: CGPoint(x: size.width, y: top + 40),
                                  control: CGPoint(x: hill.1 * size.width, y: top - 50))
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                let shade = 0.55 - Double(i) * 0.12
                ctx.fill(path, with: .color(Color(hue: (hue + 0.35).truncatingRemainder(dividingBy: 1), saturation: 0.4, brightness: shade)))
            }
        }
    }
}

/// Cream card with faint ruled lines and handwritten ink.
struct NoteCard: View {
    let text: String
    let seed: UInt32

    var body: some View {
        ZStack {
            Color(uiColor: Palette.paper)
            VStack(spacing: 30) {
                ForEach(0..<7, id: \.self) { _ in
                    Rectangle().fill(Color.blue.opacity(0.12)).frame(height: 1.5)
                }
            }
            .padding(.top, 20)
            Text(text)
                .font(.custom("Noteworthy-Bold", size: 34))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .rotationEffect(.degrees(Double(seed % 7) - 3))
                .padding(22)
        }
    }
}
