import Foundation
import RealityKit

/// Tags an interactive entity with what it *is*, so gesture handlers can route a hit
/// without caring which child mesh the ray actually struck.
nonisolated struct RoleComponent: Component, Sendable {
    enum Role: Sendable, Equatable {
        case trayItem(ItemKind)
        case stringItem(stringID: UUID, itemID: UUID)
        case twine(stringID: UUID)
        case outgoingBox
        case incomingBox
        case inboxBox(UUID)
        case postbox
        case giftTag
    }

    var role: Role
}

extension Entity {
    /// Walks up from a hit entity to the nearest ancestor that carries a role.
    func roleCarrier() -> (Entity, RoleComponent.Role)? {
        var e: Entity? = self
        while let current = e {
            if let role = current.components[RoleComponent.self]?.role { return (current, role) }
            e = current.parent
        }
        return nil
    }

    /// Makes an entity tappable/draggable with a system hover glow when looked at.
    func makeInteractive(role: RoleComponent.Role, shape: ShapeResource) {
        components.set(RoleComponent(role: role))
        components.set(CollisionComponent(shapes: [shape]))
        components.set(InputTargetComponent())
        components.set(HoverEffectComponent())
    }

    /// Turns tap/drag targeting on or off for this entity and everything under it.
    func setInputEnabled(_ enabled: Bool) {
        if var input = components[InputTargetComponent.self] {
            input.isEnabled = enabled
            components.set(input)
        }
        for child in children { child.setInputEnabled(enabled) }
    }

    var worldPosition: SIMD3<Float> {
        get { position(relativeTo: nil) }
        set { setPosition(newValue, relativeTo: nil) }
    }
}
