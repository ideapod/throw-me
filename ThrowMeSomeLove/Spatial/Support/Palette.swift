import RealityKit
import SwiftUI
import UIKit

/// The cozy, homemade look: kraft paper, twine, warm tungsten light, cream card.
enum Palette {
    static let bulbWarm = UIColor(red: 1.0, green: 0.86, blue: 0.62, alpha: 1)
    static let bulbOff = UIColor(red: 0.93, green: 0.91, blue: 0.87, alpha: 1)
    static let twine = UIColor(red: 0.66, green: 0.55, blue: 0.40, alpha: 1)
    static let wood = UIColor(red: 0.62, green: 0.45, blue: 0.30, alpha: 1)
    static let peg = UIColor(red: 0.80, green: 0.66, blue: 0.47, alpha: 1)
    static let socket = UIColor(red: 0.20, green: 0.30, blue: 0.22, alpha: 1)
    static let polaroid = UIColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1)
    static let undeveloped = UIColor(red: 0.28, green: 0.26, blue: 0.24, alpha: 1)
    static let paper = UIColor(red: 0.98, green: 0.95, blue: 0.86, alpha: 1)
    static let ribbon = UIColor(red: 0.74, green: 0.18, blue: 0.20, alpha: 1)
    static let kraft = Color(red: 0.72, green: 0.55, blue: 0.38)
    static let ink = Color(red: 0.26, green: 0.18, blue: 0.14)
}

enum Materials {
    static func matte(_ color: UIColor, roughness: Float = 0.9) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: 0)
        m.faceCulling = .none
        return m
    }

    static func textured(_ texture: TextureResource?, fallback: UIColor, roughness: Float = 0.8) -> PhysicallyBasedMaterial {
        var m = matte(fallback, roughness: roughness)
        if let texture { m.baseColor = .init(tint: .white, texture: .init(texture)) }
        return m
    }

    /// Opaque, soft white glass — lit or unlit.
    static func bulb(lit: Bool) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: lit ? Palette.bulbWarm : Palette.bulbOff)
        m.roughness = 0.35
        m.clearcoat = 0.6
        if lit {
            m.emissiveColor = .init(color: Palette.bulbWarm)
            m.emissiveIntensity = 1.6
        }
        return m
    }

    /// A faint warm halo around a lit bulb.
    static var glow: UnlitMaterial {
        var m = UnlitMaterial(color: Palette.bulbWarm)
        m.blending = .transparent(opacity: 0.18)
        return m
    }
}
