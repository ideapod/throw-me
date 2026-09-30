import SwiftUI

/// The gift waiting in every new user's inbox: a voice welcome, a family photo and a note.
///
/// To change the content, replace the files in `Resources/Welcome/`:
/// - `welcome-voice.m4a` — the spoken welcome (currently a text-to-speech stand-in)
/// - `welcome-photo.jpg` — optional; without it, `WelcomeIllustration` is drawn instead
enum WelcomeGift {
    static let senderName = "Throw Me Some Love"

    static func make() -> LoveString {
        let sender = Person(name: senderName, photo: renderImage(HeartAvatar(), size: 256))

        var voice = StringItem.empty(.sound)
        if let url = Bundle.main.url(forResource: "welcome-voice", withExtension: "m4a") {
            voice.media = try? MediaStore.copyIn(url, kind: .audio)
        }
        if voice.media == nil { voice.generated = true }

        var photo = StringItem.empty(.photo)
        if let url = Bundle.main.url(forResource: "welcome-photo", withExtension: "jpg") {
            photo.media = try? MediaStore.importImage(from: url)
        }
        if photo.media == nil { photo.media = renderImage(WelcomeIllustration(), size: 1024) }

        var note = StringItem.empty(.note)
        note.text = "go send some love!"

        return LoveString(senderName: senderName, recipientName: "You", items: [voice, photo, note], sender: sender)
    }

    private static func renderImage<V: View>(_ view: V, size: CGFloat) -> MediaRef? {
        let renderer = ImageRenderer(content: view.frame(width: size, height: size))
        renderer.scale = 1
        guard let image = renderer.uiImage, let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        return try? MediaStore.importImage(data: data)
    }
}

/// The app's face on gift tags: a heart on warm red.
private struct HeartAvatar: View {
    var body: some View {
        ZStack {
            Color(red: 0.85, green: 0.3, blue: 0.3)
            Image(systemName: "heart.fill")
                .font(.system(size: 130))
                .foregroundStyle(.white)
        }
    }
}

/// A family flying a kite on a hill at sunset, drawn as warm silhouettes.
/// Stands in for a real photo until one is dropped into `Resources/Welcome/welcome-photo.jpg`.
struct WelcomeIllustration: View {
    private let shadow = Color(red: 0.24, green: 0.11, blue: 0.20)

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let sky = Gradient(colors: [Color(red: 0.98, green: 0.62, blue: 0.55),
                                        Color(red: 1.0, green: 0.78, blue: 0.55),
                                        Color(red: 1.0, green: 0.9, blue: 0.7)])
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

            // Low sun with a soft halo.
            let sun = CGPoint(x: w * 0.68, y: h * 0.6)
            ctx.fill(Path(ellipseIn: CGRect(x: sun.x - w * 0.22, y: sun.y - w * 0.22, width: w * 0.44, height: w * 0.44)),
                     with: .color(Color(red: 1, green: 0.95, blue: 0.8).opacity(0.35)))
            ctx.fill(Path(ellipseIn: CGRect(x: sun.x - w * 0.12, y: sun.y - w * 0.12, width: w * 0.24, height: w * 0.24)),
                     with: .color(Color(red: 1, green: 0.96, blue: 0.85)))

            // Distant and near hills.
            var far = Path()
            far.move(to: CGPoint(x: 0, y: h * 0.72))
            far.addQuadCurve(to: CGPoint(x: w, y: h * 0.7), control: CGPoint(x: w * 0.55, y: h * 0.6))
            far.addLine(to: CGPoint(x: w, y: h)); far.addLine(to: CGPoint(x: 0, y: h)); far.closeSubpath()
            ctx.fill(far, with: .color(Color(red: 0.62, green: 0.36, blue: 0.4)))
            var near = Path()
            near.move(to: CGPoint(x: 0, y: h * 0.86))
            near.addQuadCurve(to: CGPoint(x: w, y: h * 0.84), control: CGPoint(x: w * 0.4, y: h * 0.7))
            near.addLine(to: CGPoint(x: w, y: h)); near.addLine(to: CGPoint(x: 0, y: h)); near.closeSubpath()
            ctx.fill(near, with: .color(shadow))

            // The family, holding hands along the hilltop: adult, child, child, adult.
            let ground = h * 0.795
            let people: [(x: CGFloat, height: CGFloat)] = [(0.22, 0.2), (0.33, 0.12), (0.42, 0.13), (0.53, 0.21)]
            var hands: [CGPoint] = []
            for p in people {
                let x = w * p.x, tall = h * p.height
                let head = tall * 0.17
                ctx.fill(Path(ellipseIn: CGRect(x: x - head / 2, y: ground - tall, width: head, height: head)), with: .color(shadow))
                ctx.fill(Path(roundedRect: CGRect(x: x - head * 0.55, y: ground - tall + head * 1.05, width: head * 1.1, height: tall * 0.45),
                              cornerRadius: head * 0.4), with: .color(shadow))
                var legs = Path()
                legs.move(to: CGPoint(x: x - head * 0.25, y: ground - tall * 0.42)); legs.addLine(to: CGPoint(x: x - head * 0.35, y: ground))
                legs.move(to: CGPoint(x: x + head * 0.25, y: ground - tall * 0.42)); legs.addLine(to: CGPoint(x: x + head * 0.35, y: ground))
                ctx.stroke(legs, with: .color(shadow), style: StrokeStyle(lineWidth: head * 0.35, lineCap: .round))
                hands.append(CGPoint(x: x, y: ground - tall * 0.55))
            }
            var arms = Path()
            for pair in zip(hands, hands.dropFirst()) {
                arms.move(to: pair.0)
                arms.addQuadCurve(to: pair.1, control: CGPoint(x: (pair.0.x + pair.1.x) / 2, y: max(pair.0.y, pair.1.y) + h * 0.02))
            }
            ctx.stroke(arms, with: .color(shadow), style: StrokeStyle(lineWidth: w * 0.009, lineCap: .round))

            // A kite, flown by the dad on the right.
            let hand = CGPoint(x: w * 0.6, y: ground - h * 0.2)
            var raised = Path()
            raised.move(to: CGPoint(x: w * 0.53, y: ground - h * 0.15)); raised.addLine(to: hand)
            ctx.stroke(raised, with: .color(shadow), style: StrokeStyle(lineWidth: w * 0.009, lineCap: .round))
            let kite = CGPoint(x: w * 0.8, y: h * 0.2)
            var line = Path()
            line.move(to: hand)
            line.addQuadCurve(to: kite, control: CGPoint(x: w * 0.78, y: h * 0.45))
            ctx.stroke(line, with: .color(shadow.opacity(0.7)), lineWidth: 2)
            var diamond = Path()
            diamond.move(to: CGPoint(x: kite.x, y: kite.y - h * 0.06))
            diamond.addLine(to: CGPoint(x: kite.x + w * 0.045, y: kite.y))
            diamond.addLine(to: CGPoint(x: kite.x, y: kite.y + h * 0.08))
            diamond.addLine(to: CGPoint(x: kite.x - w * 0.045, y: kite.y))
            diamond.closeSubpath()
            ctx.fill(diamond, with: .color(Color(red: 0.8, green: 0.2, blue: 0.25)))
            for i in 0..<3 {
                let bow = CGPoint(x: kite.x - w * 0.02 * CGFloat(i + 1), y: kite.y + h * (0.1 + 0.04 * CGFloat(i)))
                ctx.fill(Path(ellipseIn: CGRect(x: bow.x - 6, y: bow.y - 4, width: 12, height: 8)), with: .color(Color(red: 0.8, green: 0.2, blue: 0.25)))
            }

            // A few birds heading home.
            for (bx, by) in [(0.2, 0.22), (0.26, 0.18), (0.31, 0.25)] {
                var bird = Path()
                let c = CGPoint(x: w * bx, y: h * by)
                bird.move(to: CGPoint(x: c.x - 14, y: c.y - 6))
                bird.addQuadCurve(to: c, control: CGPoint(x: c.x - 6, y: c.y - 10))
                bird.addQuadCurve(to: CGPoint(x: c.x + 14, y: c.y - 6), control: CGPoint(x: c.x + 6, y: c.y - 10))
                ctx.stroke(bird, with: .color(shadow.opacity(0.6)), lineWidth: 3)
            }
        }
    }
}
