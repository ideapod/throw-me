import Foundation
import RealityKit
import UIKit

/// A public posting box styled after the one on the user's own street corner.
/// Shapes and colours only — no postal-service marks or logos.
///
/// Covers every country where Vision Pro is sold (researched Sept 2026), plus a few neighbours.
enum PostboxStyle {
    /// Round pillar box (UK, Hong Kong, Ireland, India…)
    case pillar(UIColor)
    /// Box on legs with a domed top (US, Canada)
    case domed(UIColor)
    /// Rectangular box mounted on a post, optionally with a painted band (Germany, France…)
    case onPost(UIColor, band: UIColor?)
    /// Free-standing rectangular column, with a painted band and one or two slots (Japan, Australia, China, Korea…)
    case column(UIColor, band: UIColor?, slots: Int)
    /// Two columns side by side in different colours (Taiwan's red + green pair)
    case twin(UIColor, UIColor)

    private static let red = UIColor(red: 0.78, green: 0.07, blue: 0.09, alpha: 1)
    private static let yellow = UIColor(red: 0.98, green: 0.78, blue: 0.05, alpha: 1)
    private static let postGreen = UIColor(red: 0.0, green: 0.45, blue: 0.27, alpha: 1)

    /// Vision Pro countries, roughly in order of market size, for the debug line-up.
    static let visionProRegions = ["US", "CN", "JP", "GB", "DE", "CA", "FR", "AU", "KR", "HK", "SG", "TW", "AE"]

    static func forRegion(_ region: String?) -> PostboxStyle {
        switch region?.uppercased() {
        case "US": .domed(UIColor(red: 0.10, green: 0.23, blue: 0.52, alpha: 1))
        case "CA": .domed(red)
        case "GB", "IN", "MT", "CY": .pillar(red)
        case "HK": .pillar(postGreen)  // green since 1997
        case "IE": .pillar(UIColor(red: 0.0, green: 0.42, blue: 0.26, alpha: 1))
        case "JP": .column(red, band: nil, slots: 2)  // letters left, other mail right
        case "AU": .column(red, band: .white, slots: 1)
        case "NZ": .column(red, band: nil, slots: 1)
        case "KR": .column(red, band: nil, slots: 1)
        case "CN": .column(postGreen, band: nil, slots: 1)
        case "SG": .column(UIColor(red: 0.96, green: 0.45, blue: 0.08, alpha: 1), band: .white, slots: 1)  // orange + white stripes
        case "TW": .twin(red, postGreen)
        case "FR": .onPost(yellow, band: UIColor(red: 0.16, green: 0.27, blue: 0.62, alpha: 1))  // blue trim
        case "DE", "AT", "CH", "ES", "SE", "BR", "BE", "LU": .onPost(yellow, band: nil)
        case "NL": .onPost(UIColor(red: 0.95, green: 0.45, blue: 0.10, alpha: 1), band: nil)
        // UAE street boxes couldn't be confirmed; a neutral red column until we can check.
        default: .column(red, band: nil, slots: 1)
        }
    }

    /// Debug builds can force a country with `-postboxRegion JP`.
    static var local: PostboxStyle {
        forRegion(UserDefaults.standard.string(forKey: "postboxRegion") ?? Locale.current.region?.identifier)
    }
}

final class PostboxEntity {
    let root = Entity()
    /// Where thrown boxes aim, in the postbox's local space (just in front of the slot).
    private(set) var slotLocal: SIMD3<Float> = .zero
    /// Height of the top of the box, for placing its label above it.
    private(set) var height: Float = 1
    private let body = Entity()

    var slotWorld: SIMD3<Float> { root.convert(position: slotLocal, to: nil) }
    /// World-space bounds of the box itself (not its floating label).
    var worldBounds: BoundingBox { body.visualBounds(relativeTo: nil) }

    init(style: PostboxStyle = .local) {
        root.addChild(body)
        let dark = Materials.matte(UIColor(white: 0.12, alpha: 1), roughness: 0.5)
        let hitSize: SIMD3<Float>

        switch style {
        case .pillar(let color):
            let paint = Materials.matte(color, roughness: 0.35)
            add(.generateCylinder(height: 0.06, radius: 0.21), dark, at: [0, 0.03, 0])
            add(.generateCylinder(height: 0.98, radius: 0.18), paint, at: [0, 0.55, 0])
            add(.generateCylinder(height: 0.04, radius: 0.2), paint, at: [0, 1.05, 0])
            add(.generateSphere(radius: 0.2), paint, at: [0, 1.07, 0], scale: [1, 0.4, 1])
            add(.generateBox(size: [0.13, 0.018, 0.03], cornerRadius: 0.005), dark, at: [0, 0.9, 0.17])
            slotLocal = [0, 0.9, 0.26]
            hitSize = [0.42, 1.2, 0.42]

        case .domed(let color):
            let paint = Materials.matte(color, roughness: 0.35)
            for x: Float in [-0.17, 0.17] {
                for z: Float in [-0.19, 0.19] {
                    add(.generateBox(size: [0.03, 0.14, 0.03]), dark, at: [x, 0.07, z])
                }
            }
            add(.generateBox(size: [0.42, 0.56, 0.46]), paint, at: [0, 0.42, 0])
            let dome = add(.generateCylinder(height: 0.46, radius: 0.21), paint, at: [0, 0.7, 0], scale: [1, 1, 0.6])
            dome.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            let chute = add(.generateBox(size: [0.26, 0.03, 0.08], cornerRadius: 0.01), dark, at: [0, 0.78, 0.2])
            chute.orientation = simd_quatf(angle: 0.35, axis: [1, 0, 0])
            slotLocal = [0, 0.8, 0.3]
            hitSize = [0.46, 0.95, 0.5]

        case .column(let color, let band, let slots):
            addColumn(color, band: band, slots: slots, width: 0.36, at: 0, dark: dark)
            slotLocal = [slots == 2 ? -0.08 : 0, 0.92, 0.26]
            hitSize = [0.4, 1.12, 0.34]

        case .twin(let left, let right):
            addColumn(left, band: nil, slots: 1, width: 0.28, at: -0.16, dark: dark)
            addColumn(right, band: nil, slots: 1, width: 0.28, at: 0.16, dark: dark)
            slotLocal = [-0.16, 0.92, 0.26]
            hitSize = [0.64, 1.12, 0.34]

        case .onPost(let color, let band):
            let paint = Materials.matte(color, roughness: 0.35)
            add(.generateCylinder(height: 0.82, radius: 0.028), dark, at: [0, 0.41, 0])
            add(.generateBox(size: [0.34, 0.42, 0.24], cornerRadius: 0.03), paint, at: [0, 1.02, 0])
            let roof = add(.generateBox(size: [0.37, 0.03, 0.28], cornerRadius: 0.01), paint, at: [0, 1.25, -0.01])
            roof.orientation = simd_quatf(angle: -0.18, axis: [1, 0, 0])
            if let band {
                add(.generateBox(size: [0.345, 0.05, 0.245]), Materials.matte(band, roughness: 0.4), at: [0, 0.9, 0])
            }
            add(.generateBox(size: [0.18, 0.02, 0.02], cornerRadius: 0.005), dark, at: [0, 1.14, 0.12])
            slotLocal = [0, 1.14, 0.2]
            hitSize = [0.4, 1.3, 0.3]
        }

        height = hitSize.y
        root.makeInteractive(role: .postbox, shape: ShapeResource.generateBox(size: hitSize).offsetBy(translation: [0, hitSize.y / 2, 0]))
    }

    /// A free-standing rectangular box on a dark plinth, with a gently rounded top.
    private func addColumn(_ color: UIColor, band: UIColor?, slots: Int, width: Float, at x: Float, dark: PhysicallyBasedMaterial) {
        let paint = Materials.matte(color, roughness: 0.35)
        add(.generateBox(size: [width + 0.03, 0.06, 0.33]), dark, at: [x, 0.03, 0])
        add(.generateBox(size: [width, 1.0, 0.3], cornerRadius: 0.035), paint, at: [x, 0.56, 0])
        add(.generateBox(size: [width + 0.02, 0.04, 0.32], cornerRadius: 0.018), paint, at: [x, 1.07, 0])
        if let band {
            add(.generateBox(size: [width + 0.004, 0.07, 0.304]), Materials.matte(band, roughness: 0.4), at: [x, 0.62, 0])
        }
        let slotWidth: Float = slots == 2 ? width * 0.36 : width * 0.55
        let offsets: [Float] = slots == 2 ? [-width * 0.22, width * 0.22] : [0]
        for dx in offsets {
            add(.generateBox(size: [slotWidth, 0.02, 0.02], cornerRadius: 0.005), dark, at: [x + dx, 0.92, 0.15])
        }
    }

    @discardableResult
    private func add(_ mesh: MeshResource, _ material: some RealityKit.Material, at p: SIMD3<Float>, scale: SIMD3<Float> = .one) -> ModelEntity {
        let e = ModelEntity(mesh: mesh, materials: [material])
        e.position = p
        e.scale = scale
        body.addChild(e)
        return e
    }

    /// A happy squash-and-stretch when something is posted.
    func gulp(animator: Animator) {
        SoundBank.shared.play(.clunk, on: root, gain: -3)
        animator.run(0.5, ease: Ease.linear) { [body] t in
            let s = sin(t * .pi * 3) * (1 - t) * 0.06
            body.scale = [1 + s, 1 - s, 1 + s]
        }
    }
}
