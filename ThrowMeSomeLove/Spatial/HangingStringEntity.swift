import RealityKit
import UIKit

/// A length of twine between two tacks with items clipped along it, like Christmas lights.
/// Used for the string you're making, strings hung in the room, and the sample rail.
final class HangingStringEntity {
    let id: UUID
    let root = Entity()
    private(set) var itemEntities: [StringItemEntity] = []
    private(set) var span: Float
    private let fixedSpan: Bool
    private let sagDepth: Float = 0.05
    private let twine = ModelEntity()
    private var isHighlighted = false
    private var gapIndex: Int?
    private let leftTack = ModelEntity(mesh: .generateSphere(radius: 0.005), materials: [Materials.matte(Palette.wood)])
    private let rightTack = ModelEntity(mesh: .generateSphere(radius: 0.005), materials: [Materials.matte(Palette.wood)])

    static let spacing: Float = 0.1

    var items: [StringItem] { itemEntities.map(\.item) }

    init(id: UUID = UUID(), items: [StringItem], span: Float? = nil, revealed: Bool = true, movable: Bool = true) {
        self.id = id
        self.fixedSpan = span != nil
        self.span = span ?? Self.naturalSpan(for: items.count)
        root.addChild(twine)
        root.addChild(leftTack)
        root.addChild(rightTack)
        for item in items {
            let e = StringItemEntity(item: item, revealed: revealed)
            tag(e)
            itemEntities.append(e)
            root.addChild(e.root)
        }
        rebuildTwine()
        layout(animator: nil)

        // Grabbing the twine moves the whole string (not the one being made — it would steal taps).
        if movable {
            twine.components.set(RoleComponent(role: .twine(stringID: id)))
            twine.components.set(InputTargetComponent())
            twine.components.set(HoverEffectComponent())
        }
    }

    static func naturalSpan(for count: Int) -> Float { max(0.4, Float(count) * spacing + 0.12) }

    // MARK: Geometry

    private var leftEnd: SIMD3<Float> { [-span / 2, 0, 0] }
    private var rightEnd: SIMD3<Float> { [span / 2, 0, 0] }

    func point(at t: Float) -> SIMD3<Float> {
        Meshes.sag(from: leftEnd, to: rightEnd, depth: sagDepth, t: t)
    }

    private func slotT(_ index: Int, of count: Int) -> Float {
        Float(index + 1) / Float(count + 1)
    }

    private func rebuildTwine() {
        let points = (0...40).map { point(at: Float($0) / 40) }
        if let mesh = Meshes.tube(points: points, radius: 0.0012) {
            twine.model = ModelComponent(mesh: mesh, materials: [Materials.matte(Palette.twine)])
        }
        if twine.components.has(InputTargetComponent.self) {
            twine.components.set(CollisionComponent(shapes: [.generateBox(size: [span, 0.04, 0.03]).offsetBy(translation: [0, -sagDepth / 2, 0])]))
        }
        leftTack.position = leftEnd
        rightTack.position = rightEnd
    }

    /// Spreads items evenly along the twine.
    func layout(animator: Animator?) {
        if !fixedSpan {
            let newSpan = Self.naturalSpan(for: itemEntities.count)
            if newSpan != span { span = newSpan; rebuildTwine() }
        }
        // While something is hovering to be dropped, leave a gap where it would go.
        let slots = itemEntities.count + (gapIndex == nil ? 0 : 1)
        for (i, e) in itemEntities.enumerated() {
            let slot = gapIndex.map { i >= $0 ? i + 1 : i } ?? i
            let target = point(at: slotT(slot, of: slots))
            // RealityKit won't animate entities that aren't active in the scene; place those directly.
            if animator != nil, root.isActive {
                var transform = e.root.transform
                transform.translation = target
                transform.scale = .one
                e.root.move(to: transform, relativeTo: root, duration: 0.35, timingFunction: .easeOut)
            } else {
                e.root.position = target
            }
        }
    }

    // MARK: Editing

    var isFull: Bool { itemEntities.count >= LoveString.maxItems }

    /// Where along the string an item dropped at this local x would be inserted.
    /// Compares against where items rest (not where they are mid-animation), so the gap
    /// opening up while you hover doesn't change the answer.
    private func insertionIndex(forLocalX x: Float) -> Int {
        itemEntities.indices.filter { point(at: slotT($0, of: itemEntities.count)).x < x }.count
    }

    func insertionIndex(forWorld p: SIMD3<Float>, eye: SIMD3<Float>?) -> Int {
        insertionIndex(forLocalX: dropPoint(forWorld: p, eye: eye).x)
    }

    /// Where a held item *appears* to be on the string's plane, seen from the eye.
    /// Items are held nearer or further than the string, so their raw x would be off.
    private func dropPoint(forWorld p: SIMD3<Float>, eye: SIMD3<Float>?) -> SIMD3<Float> {
        let local = root.convert(position: p, from: nil)
        guard let eye else { return local }
        let e = root.convert(position: eye, from: nil)
        let dz = local.z - e.z
        guard abs(dz) > 0.001 else { return local }
        let t = -e.z / dz
        return t > 0 ? e + (local - e) * t : local
    }

    /// Whether an item held at this world point would clip on if let go.
    /// Generous in depth, because judging distance along your line of sight is hard.
    func accepts(worldPoint p: SIMD3<Float>, eye: SIMD3<Float>?) -> Bool {
        guard !isFull, abs(root.convert(position: p, from: nil).z) < 0.4 else { return false }
        let local = dropPoint(forWorld: p, eye: eye)
        guard abs(local.x) < span / 2 + 0.06 else { return false }
        let t = min(max(local.x / span + 0.5, 0), 1)
        return abs(local.y - point(at: t).y) < 0.12
    }

    /// Opens (or closes, with nil) a gap in the string where a hovering item would land.
    func setGap(_ index: Int?, animator: Animator) {
        guard index != gapIndex else { return }
        gapIndex = index
        layout(animator: animator)
    }

    /// Warms the twine up while something is hovering where it would land.
    func setHighlighted(_ on: Bool) {
        guard on != isHighlighted else { return }
        isHighlighted = on
        twine.model?.materials = [on ? Materials.bulb(lit: true) : Materials.matte(Palette.twine)]
        twine.scale = on ? [1, 1.8, 1.8] : .one
    }

    func insert(_ e: StringItemEntity, atWorld p: SIMD3<Float>, eye: SIMD3<Float>?, animator: Animator) {
        let index = insertionIndex(forWorld: p, eye: eye)
        gapIndex = nil
        tag(e)
        e.root.setParent(root, preservingWorldTransform: true)
        itemEntities.insert(e, at: index)
        layout(animator: animator)
    }

    /// Detaches an item (keeping it where it is in the world) and closes the gap.
    func remove(itemID: UUID, animator: Animator?) -> StringItemEntity? {
        guard let index = itemEntities.firstIndex(where: { $0.item.id == itemID }) else { return nil }
        let e = itemEntities.remove(at: index)
        e.root.setParent(root.parent ?? root, preservingWorldTransform: true)
        layout(animator: animator)
        return e
    }

    func removeAll() {
        for e in itemEntities { e.root.removeFromParent() }
        itemEntities.removeAll()
        layout(animator: nil)
    }

    /// Rebuilds one item in place after its content has been filled in.
    @discardableResult
    func replace(_ item: StringItem, animator: Animator?) -> StringItemEntity? {
        guard let index = itemEntities.firstIndex(where: { $0.item.id == item.id }) else { return nil }
        let old = itemEntities[index]
        let fresh = StringItemEntity(item: item)
        tag(fresh)
        fresh.root.transform = old.root.transform
        old.root.removeFromParent()
        root.addChild(fresh.root)
        itemEntities[index] = fresh
        if let animator {
            fresh.root.scale = .init(repeating: 0.7)
            animator.pop(fresh.root, to: 1, duration: 0.4)
        }
        return fresh
    }

    func entity(for itemID: UUID) -> StringItemEntity? {
        itemEntities.first { $0.item.id == itemID }
    }

    private func tag(_ e: StringItemEntity) {
        e.root.components.set(RoleComponent(role: .stringItem(stringID: id, itemID: e.item.id)))
    }
}
