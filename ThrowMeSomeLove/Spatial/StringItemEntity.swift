import AVFoundation
import RealityKit
import UIKit

/// The physical form of one `StringItem`: a peg on the twine with a bulb, polaroid or note below it.
/// The root's origin is the point where it clips onto the string.
///
/// Empty items (fresh off the palette) look like ghosts of themselves until they're filled in.
final class StringItemEntity {
    let item: StringItem
    let root = Entity()
    private(set) var isRevealed = true
    private(set) var isActive = false

    private var bulb: ModelEntity?
    private var glow: ModelEntity?
    /// The photo / ink layer that "develops" from transparent to visible.
    private var revealLayer: ModelEntity?
    private var posterMaterial: RealityKit.Material?
    private var player: AVPlayer?
    private let sway: Float

    init(item: StringItem, revealed: Bool = true) {
        self.item = item
        var rng = SeededRandom(item.seed)
        sway = rng.range(-0.1...0.1)

        let peg = ModelEntity(mesh: .generateBox(size: [0.007, 0.018, 0.006], cornerRadius: 0.001),
                              materials: [Materials.matte(Palette.peg)])
        peg.position = [0, -0.004, 0]
        root.addChild(peg)

        let body = Entity()
        body.orientation = simd_quatf(angle: sway, axis: [0, 0, 1])
        root.addChild(body)

        switch item.kind {
        case .sound: buildBulb(in: body)
        case .photo: buildPolaroid(in: body)
        case .note: buildNote(in: body)
        }

        root.components.set(CollisionComponent(shapes: [hitShape]))
        root.components.set(InputTargetComponent())
        root.components.set(HoverEffectComponent())
        setRevealed(revealed, animator: nil)
    }

    /// How far below the twine the item hangs; used to size hit targets and spacing.
    var hangDepth: Float {
        switch item.kind {
        case .sound: 0.05
        case .photo: 0.11
        case .note: 0.085
        }
    }

    private var hitShape: ShapeResource {
        let width: Float = item.kind == .sound ? 0.045 : 0.085
        return ShapeResource.generateBox(size: [width, hangDepth + 0.01, 0.03]).offsetBy(translation: [0, -hangDepth / 2, 0])
    }

    private func buildBulb(in body: Entity) {
        let socket = ModelEntity(mesh: .generateCylinder(height: 0.012, radius: 0.0065), materials: [Materials.matte(Palette.socket, roughness: 0.6)])
        socket.position = [0, -0.014, 0]
        body.addChild(socket)

        let bulb = ModelEntity(mesh: .generateSphere(radius: 0.015), materials: [Materials.bulb(lit: true)])
        bulb.position = [0, -0.034, 0]
        bulb.scale = [1, 1.3, 1]
        body.addChild(bulb)
        self.bulb = bulb
        if !item.isFilled { bulb.components.set(OpacityComponent(opacity: 0.45)) }

        let glow = ModelEntity(mesh: .generateSphere(radius: 0.024), materials: [Materials.glow])
        glow.position = bulb.position
        glow.scale = [1, 1.2, 1]
        body.addChild(glow)
        self.glow = glow
    }

    private func buildPolaroid(in body: Entity) {
        let frameTop: Float = -0.011
        let frame = ModelEntity(mesh: .generateBox(size: [0.08, 0.095, 0.0015], cornerRadius: 0.0005),
                                materials: [Materials.matte(Palette.polaroid, roughness: 0.7)])
        frame.position = [0, frameTop - 0.0475, 0]
        body.addChild(frame)

        let photoCentre: SIMD3<Float> = [0, frameTop - 0.006 - 0.034, 0.0009]
        let base = ModelEntity(mesh: .generatePlane(width: 0.068, height: 0.068), materials: [Materials.matte(Palette.undeveloped, roughness: 0.5)])
        base.position = photoCentre
        body.addChild(base)

        let photo = ModelEntity(mesh: .generatePlane(width: 0.068, height: 0.068), materials: [photoMaterial(nil)])
        photo.position = photoCentre + [0, 0, 0.0002]
        body.addChild(photo)
        revealLayer = photo

        if let media = item.media {
            Task { [weak self] in
                guard let image = await MediaStore.squareImage(for: media),
                      let texture = try? await TextureResource(image: image, options: .init(semantic: .color)) else { return }
                self?.setPhoto(Materials.textured(texture, fallback: .gray, roughness: 0.5))
            }
        }
    }

    private func photoMaterial(_ texture: TextureResource?) -> PhysicallyBasedMaterial {
        if let texture { return Materials.textured(texture, fallback: .gray, roughness: 0.5) }
        if item.generated { return Materials.textured(Textures.photo(seed: item.seed), fallback: .gray, roughness: 0.5) }
        return Materials.textured(Textures.emptyPhoto, fallback: .lightGray, roughness: 0.6)
    }

    private func setPhoto(_ material: RealityKit.Material) {
        posterMaterial = material
        if player == nil { revealLayer?.model?.materials = [material] }
    }

    private func buildNote(in body: Entity) {
        let centre: SIMD3<Float> = [0, -0.011 - 0.036, 0]
        let card = ModelEntity(mesh: .generateBox(size: [0.072, 0.072, 0.0008]), materials: [Materials.matte(Palette.paper)])
        card.position = centre
        body.addChild(card)

        let texture = item.isFilled ? Textures.note(item.text ?? "", seed: item.seed) : Textures.emptyNote
        let ink = ModelEntity(mesh: .generatePlane(width: 0.072, height: 0.072),
                              materials: [Materials.textured(texture, fallback: Palette.paper)])
        ink.position = centre + [0, 0, 0.0006]
        body.addChild(ink)
        revealLayer = ink
    }

    // MARK: States

    /// Unrevealed items are dark bulbs, undeveloped polaroids and blank cards.
    func setRevealed(_ revealed: Bool, animator: Animator?) {
        guard revealed != isRevealed || animator == nil else { return }
        isRevealed = revealed
        let lit = revealed && item.isFilled
        bulb?.model?.materials = [Materials.bulb(lit: lit)]
        glow?.isEnabled = lit
        guard let layer = revealLayer else { return }
        if let animator {
            // Polaroids develop slowly; ink appears a touch faster.
            animator.fade(layer, to: revealed ? 1 : 0, duration: item.kind == .photo ? 1.8 : 1.0)
        } else {
            layer.components.set(OpacityComponent(opacity: revealed ? 1 : 0))
        }
        if revealed, let animator {
            root.scale = .init(repeating: 0.85)
            animator.pop(root, to: 1)
        }
    }

    /// The item currently being looked at swells slightly; bulbs brighten; videos play.
    func setActive(_ active: Bool, animator: Animator) {
        guard active != isActive else { return }
        isActive = active
        animator.pop(root, to: active ? 1.25 : 1, duration: 0.3)
        if var material = bulb?.model?.materials.first as? PhysicallyBasedMaterial, isRevealed, item.isFilled {
            material.emissiveIntensity = active ? 3.2 : 1.6
            bulb?.model?.materials = [material]
        }
        glow?.scale = active ? [1.4, 1.6, 1.4] : [1, 1.2, 1]
        if item.media?.kind == .video { setVideoPlaying(active) }
    }

    private func setVideoPlaying(_ playing: Bool) {
        guard let media = item.media, let layer = revealLayer else { return }
        if playing {
            let player = AVPlayer(url: MediaStore.url(for: media))
            self.player = player
            layer.model?.materials = [VideoMaterial(avPlayer: player)]
            player.play()
        } else {
            player?.pause()
            player = nil
            if let posterMaterial { layer.model?.materials = [posterMaterial] }
        }
    }

    /// Plays this item's voice: its recorded sound, a chime for placeholder bulbs, or a paper rustle.
    func sound() {
        if let media = item.media, media.kind == .audio {
            SoundBank.shared.play(file: MediaStore.url(for: media), on: root)
            return
        }
        switch item.kind {
        case .sound where item.generated: SoundBank.shared.play(.chime(Int(item.seed % 7)), on: root)
        case .sound: SoundBank.shared.play(.pop, on: root, gain: -14)
        case .photo, .note: SoundBank.shared.play(.rustle, on: root, gain: -18)
        }
    }
}
