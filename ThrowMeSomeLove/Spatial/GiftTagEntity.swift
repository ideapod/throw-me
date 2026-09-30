import RealityKit
import SwiftUI

/// A kraft-paper gift tag on a loop of red string: "To" on gifts you send, "From" on gifts you get.
/// Shows the person's name and their contact photo (or initials).
final class GiftTagEntity {
    enum Direction: String { case to = "To", from = "From" }

    static let size: SIMD2<Float> = [0.09, 0.05]

    let person: Person
    let root = Entity()

    /// `draggable` tags can be picked up (the one you tie onto a gift);
    /// tags already on a box are just decoration and let taps through to the box.
    init(person: Person, direction: Direction, draggable: Bool) {
        self.person = person
        let (w, h) = (Self.size.x, Self.size.y)

        let card = ModelEntity(mesh: .generateBox(size: [w, h, 0.0008], cornerRadius: 0.002),
                               materials: [Materials.textured(Textures.giftTag(person, direction: direction),
                                                              fallback: Palette.peg, roughness: 0.9)])
        root.addChild(card)

        // A little loop of string from the tag's hole, for tying on.
        let hole = SIMD3<Float>(-w / 2 + 0.008, 0, 0.001)
        let loop = (0...12).map { i -> SIMD3<Float> in
            let t = Float(i) / 12
            return hole + [-0.018 * sin(t * .pi), 0.02 * t, 0]
        }
        if let mesh = Meshes.tube(points: loop, radius: 0.0007) {
            root.addChild(ModelEntity(mesh: mesh, materials: [Materials.matte(Palette.ribbon, roughness: 0.6)]))
        }

        if draggable {
            root.makeInteractive(role: .giftTag, shape: .generateBox(size: [w + 0.01, h + 0.01, 0.02]))
        }
    }
}

extension Textures {
    static func giftTag(_ person: Person, direction: GiftTagEntity.Direction) -> TextureResource? {
        render("tag-\(direction.rawValue)-\(person.name)-\(person.photo?.file ?? "")", size: CGSize(width: 360, height: 200)) {
            GiftTagCard(person: person, direction: direction)
        }
    }
}

/// The printed face of a gift tag.
struct GiftTagCard: View {
    let person: Person
    let direction: GiftTagEntity.Direction

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.black.opacity(0.35))
                .frame(width: 18, height: 18)
            avatar
            VStack(alignment: .leading, spacing: 0) {
                Text(direction.rawValue)
                    .font(.custom("Noteworthy-Bold", size: 26))
                    .opacity(0.6)
                Text(person.name)
                    .font(.custom("Noteworthy-Bold", size: 38))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
            }
            .foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.kraft.opacity(0.85))
    }

    @ViewBuilder private var avatar: some View {
        let photo = person.photo.flatMap { try? Data(contentsOf: MediaStore.url(for: $0)) }.flatMap(UIImage.init(data:))
        ZStack {
            Circle().fill(Color(uiColor: Palette.paper))
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill().clipShape(Circle())
            } else {
                Text(person.initials)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink.opacity(0.7))
            }
        }
        .frame(width: 110, height: 110)
        .overlay(Circle().stroke(Color.white, lineWidth: 5))
    }
}
