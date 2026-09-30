import RealityKit
import UIKit

/// A wrapped present built from hinged panels, so it can fold closed around a string
/// when sent and fall open like a flower when unwrapped.
/// The root's origin sits at the centre of the box's base.
final class GiftBoxEntity {
    enum Stage: Int { case open, wrapped, ribbonOff, lidOff, unwrapped }

    let root = Entity()
    let size: SIMD3<Float>
    private(set) var stage: Stage

    private var hinges: [(hinge: Entity, open: simd_quatf)] = []
    private let lid = Entity()
    private let bow = Entity()
    private var ribbonParts: [Entity] = []
    private let lidRest: SIMD3<Float>
    private(set) var tag: GiftTagEntity?

    init(size: SIMD3<Float> = [0.16, 0.12, 0.16], stage: Stage = .wrapped) {
        self.size = size
        self.stage = stage
        lidRest = [0, size.y, 0]
        let (w, h, d) = (size.x, size.y, size.z)
        let t: Float = 0.003
        let paper = Materials.textured(Textures.wrappingPaper, fallback: Palette.wood, roughness: 0.85)
        let ribbon = Materials.matte(Palette.ribbon, roughness: 0.6)
        let ribbonWidth = w * 0.09

        let bottom = ModelEntity(mesh: .generateBox(size: [w, t, d]), materials: [paper])
        bottom.position = [0, t / 2, 0]
        root.addChild(bottom)

        // (hinge position, panel size, panel offset from hinge, outward normal, open rotation)
        let sides: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, simd_quatf)] = [
            ([0, 0, d / 2], [w, h, t], [0, h / 2, -t / 2], [0, 0, 1], simd_quatf(angle: .pi / 2, axis: [1, 0, 0])),
            ([0, 0, -d / 2], [w, h, t], [0, h / 2, t / 2], [0, 0, -1], simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])),
            ([w / 2, 0, 0], [t, h, d], [-t / 2, h / 2, 0], [1, 0, 0], simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])),
            ([-w / 2, 0, 0], [t, h, d], [t / 2, h / 2, 0], [-1, 0, 0], simd_quatf(angle: .pi / 2, axis: [0, 0, 1])),
        ]
        for (hingePos, panelSize, offset, normal, open) in sides {
            let hinge = Entity()
            hinge.position = hingePos
            let panel = ModelEntity(mesh: .generateBox(size: panelSize), materials: [paper])
            panel.position = offset
            hinge.addChild(panel)

            let stripSize: SIMD3<Float> = normal.x != 0 ? [0.0015, h, ribbonWidth] : [ribbonWidth, h, 0.0015]
            let strip = ModelEntity(mesh: .generateBox(size: stripSize), materials: [ribbon])
            strip.position = offset + normal * (t / 2 + 0.001)
            hinge.addChild(strip)
            ribbonParts.append(strip)

            root.addChild(hinge)
            hinges.append((hinge, open))
        }

        let lidHeight: Float = h * 0.22
        let lidMesh = ModelEntity(mesh: .generateBox(size: [w + 0.008, lidHeight, d + 0.008]), materials: [paper])
        lidMesh.position = [0, lidHeight / 2 - lidHeight * 0.4, 0]
        lid.addChild(lidMesh)
        let lidTop = lidHeight * 0.6 + 0.001
        for stripSize in [SIMD3<Float>(w + 0.01, 0.002, ribbonWidth), SIMD3<Float>(ribbonWidth, 0.002, d + 0.01)] {
            let strip = ModelEntity(mesh: .generateBox(size: stripSize), materials: [ribbon])
            strip.position = [0, lidTop, 0]
            lid.addChild(strip)
            ribbonParts.append(strip)
        }

        for side: Float in [-1, 1] {
            let loop = ModelEntity(mesh: .generateSphere(radius: w * 0.14), materials: [ribbon])
            loop.scale = [1, 0.45, 0.6]
            loop.orientation = simd_quatf(angle: side * 0.5, axis: [0, 0, 1])
            loop.position = [side * w * 0.11, w * 0.05, 0]
            bow.addChild(loop)
        }
        let knot = ModelEntity(mesh: .generateSphere(radius: w * 0.05), materials: [ribbon])
        knot.position = [0, w * 0.04, 0]
        bow.addChild(knot)
        bow.position = [0, lidTop, 0]
        lid.addChild(bow)
        lid.position = lidRest
        root.addChild(lid)

        root.components.set(CollisionComponent(shapes: [
            .generateBox(size: [w, h + 0.05, d]).offsetBy(translation: [0, (h + 0.05) / 2, 0]),
        ]))
        root.components.set(InputTargetComponent())
        root.components.set(HoverEffectComponent())

        apply(stage)
    }

    /// Snaps to a stage with no animation.
    private func apply(_ stage: Stage) {
        for (hinge, open) in hinges {
            hinge.orientation = stage == .open || stage == .unwrapped ? open : simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        }
        let ribbonOn = stage == .wrapped
        for part in ribbonParts + [bow] { part.isEnabled = ribbonOn }
        lid.isEnabled = stage == .wrapped || stage == .ribbonOff
    }

    /// Ties a gift tag on the front, hanging off the ribbon, sized to suit the box.
    func attachTag(_ tag: GiftTagEntity, animator: Animator?) {
        self.tag?.root.removeFromParent()
        self.tag = tag
        let rest = Transform(scale: .init(repeating: size.x / 0.16),
                             rotation: simd_quatf(angle: -0.18, axis: [0, 0, 1]),
                             translation: [size.x * 0.18, size.y * 0.58, size.z / 2 + 0.004])
        tag.root.setParent(root, preservingWorldTransform: animator != nil)
        if animator != nil {
            tag.root.move(to: rest, relativeTo: root, duration: 0.35, timingFunction: .easeOut)
            SoundBank.shared.play(.rustle, on: root, gain: -12)
        } else {
            tag.root.transform = rest
        }
    }

    // MARK: Wrapping (sender)

    /// Folds an open box closed, drops the lid on and ties the ribbon.
    func wrapUp(animator: Animator, done: @escaping () -> Void) {
        stage = .wrapped
        SoundBank.shared.play(.rustle, on: root)
        for (i, (hinge, _)) in hinges.enumerated() {
            let from = hinge.orientation
            animator.run(0.45, delay: Float(i) * 0.12, ease: Ease.backOut) { t in
                hinge.orientation = simd_slerp(from, simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), t)
            }
        }
        lid.isEnabled = true
        lid.position = lidRest + [0, 0.15, 0]
        animator.run(0.4, delay: 0.6, ease: Ease.out) { [lid, lidRest] t in
            lid.position = lidRest + [0, 0.15 * (1 - t), 0]
        } done: { [weak self] in
            guard let self else { return }
            SoundBank.shared.play(.pop, on: root)
            for part in ribbonParts + [bow] {
                part.isEnabled = true
                part.scale = .init(repeating: 0.01)
                animator.pop(part, to: 1, duration: 0.4)
            }
            animator.run(0.45, step: { _ in }, done: done)
        }
    }

    // MARK: Unwrapping (recipient) — one tap per step

    func advanceUnwrap(animator: Animator, done: @escaping (Stage) -> Void) {
        switch stage {
        case .wrapped:
            stage = .ribbonOff
            SoundBank.shared.play(.pop, on: root)
            let start = bow.position
            animator.run(0.5, ease: Ease.out) { [bow] t in
                bow.position = start + [0, 0.12 * t, 0]
                bow.orientation = simd_quatf(angle: t * 2, axis: [0, 1, 0])
            }
            animator.fade(bow, to: 0, duration: 0.5)
            for part in ribbonParts { animator.fade(part, to: 0, duration: 0.35) }
            if let tag { animator.fade(tag.root, to: 0, duration: 0.35) }
            animator.run(0.5, step: { _ in }, done: { [weak self] in
                guard let self else { return }
                for part in ribbonParts + [bow] { part.isEnabled = false }
                done(stage)
            })

        case .ribbonOff:
            stage = .lidOff
            SoundBank.shared.play(.rustle, on: root)
            animator.run(0.7, ease: Ease.out) { [lid, lidRest] t in
                lid.position = lidRest + [0.18 * t, 0.14 * sin(t * .pi * 0.8), 0]
                lid.orientation = simd_quatf(angle: -0.6 * t, axis: [0, 0, 1])
            }
            animator.fade(lid, to: 0, duration: 0.4, delay: 0.4) { [weak self] in
                guard let self else { return }
                lid.isEnabled = false
                done(stage)
            }

        case .lidOff:
            stage = .unwrapped
            SoundBank.shared.play(.rustle, on: root)
            for (i, (hinge, open)) in hinges.enumerated() {
                animator.run(0.6, delay: Float(i) * 0.06, ease: Ease.backOut) { t in
                    hinge.orientation = simd_slerp(simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), open, t)
                }
            }
            animator.run(0.8, step: { _ in }, done: { [weak self] in
                guard let self else { return }
                done(stage)
            })

        case .open, .unwrapped:
            done(stage)
        }
    }
}
