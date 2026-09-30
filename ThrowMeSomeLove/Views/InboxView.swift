import RealityKit
import SwiftUI

/// A small volume you park anywhere in your room. Unopened gifts pile up in it as a stack of boxes.
struct InboxView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var stack = InboxStack()

    var body: some View {
        RealityView { content in
            content.add(stack.root)
            stack.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                stack.animator.tick(Float(event.deltaTime))
            }
            stack.sync(model.inbox)
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard case .inboxBox(let id)? = value.entity.roleCarrier()?.1 else { return }
                    Task {
                        if !model.immersiveOpen { await openImmersiveSpace(id: SceneID.room) }
                        model.requestUnwrap(id)
                    }
                }
        )
        .onChange(of: model.inbox.map(\.id)) { stack.sync(model.inbox) }
        .ornament(attachmentAnchor: .scene(.bottomFront)) {
            Text(caption)
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .glassBackgroundEffect()
        }
    }

    private var caption: String {
        switch model.inbox.count {
        case 0: "No gifts yet"
        case 1: "1 gift from \(model.inbox[0].senderName)"
        default: "\(model.inbox.count) gifts waiting"
        }
    }
}

/// Lays gift boxes out as a slightly wonky pile and animates arrivals and departures.
final class InboxStack {
    let root = Entity()
    let animator = Animator()
    var updateSubscription: EventSubscription?
    private var boxes: [UUID: GiftBoxEntity] = [:]

    private static let boxSize: SIMD3<Float> = [0.1, 0.065, 0.1]
    private static let floor: Float = -0.16
    private static let perPile = 4
    private static let piles: [SIMD2<Float>] = [[0, 0], [-0.1, 0.04], [0.1, 0.04], [-0.05, -0.08], [0.05, -0.08]]

    func sync(_ inbox: [LoveString]) {
        let visible = Array(inbox.prefix(Self.perPile * Self.piles.count))
        let wanted = Set(visible.map(\.id))

        for (id, box) in boxes where !wanted.contains(id) {
            boxes[id] = nil
            let start = box.root.position
            animator.run(0.5, ease: Ease.out) { t in
                box.root.position = start + [0, 0.15 * t, 0]
                box.root.scale = .init(repeating: 1 - t)
            } done: { box.root.removeFromParent() }
        }

        for (i, gift) in visible.enumerated() {
            let target = slot(i, id: gift.id)
            if let box = boxes[gift.id] {
                var transform = box.root.transform
                transform.translation = target.position
                box.root.move(to: transform, relativeTo: root, duration: 0.3, timingFunction: .easeInOut)
                continue
            }
            let box = GiftBoxEntity(size: Self.boxSize)
            box.root.components.set(RoleComponent(role: .inboxBox(gift.id)))
            // Who it's from, with their picture if we have one.
            box.attachTag(GiftTagEntity(person: gift.sender ?? Person(name: gift.senderName), direction: .from, draggable: false),
                          animator: nil)
            box.root.orientation = target.rotation
            box.root.position = target.position + [0, 0.25, 0]
            root.addChild(box.root)
            boxes[gift.id] = box
            // Drop in from above with a little bounce.
            animator.run(0.6, ease: Ease.backOut) { t in
                box.root.position = target.position + [0, 0.25 * (1 - t), 0]
            } done: {
                SoundBank.shared.play(.pop, on: box.root, gain: -14)
            }
        }
    }

    private func slot(_ index: Int, id: UUID) -> (position: SIMD3<Float>, rotation: simd_quatf) {
        var rng = SeededRandom(UInt32(truncatingIfNeeded: id.hashValue))
        let pile = Self.piles[(index / Self.perPile) % Self.piles.count]
        let level = index % Self.perPile
        let position = SIMD3<Float>(pile.x + rng.range(-0.008...0.008),
                                    Self.floor + Float(level) * (Self.boxSize.y + 0.022),
                                    pile.y + rng.range(-0.008...0.008))
        return (position, simd_quatf(angle: rng.range(-0.35...0.35), axis: [0, 1, 0]))
    }
}
