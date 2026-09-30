import Foundation
import RealityKit
import simd

enum Meshes {
    /// A round tube swept along a polyline — used for twine and ribbon.
    static func tube(points: [SIMD3<Float>], radius: Float, sides: Int = 6) -> MeshResource? {
        guard points.count >= 2 else { return nil }
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for (i, p) in points.enumerated() {
            let next = i < points.count - 1 ? points[i + 1] : p
            let prev = i > 0 ? points[i - 1] : p
            let tangent = simd_normalize(next - prev)
            var up = SIMD3<Float>(0, 1, 0)
            if abs(simd_dot(up, tangent)) > 0.95 { up = [1, 0, 0] }
            let side = simd_normalize(simd_cross(tangent, up))
            let binormal = simd_cross(side, tangent)
            for s in 0..<sides {
                let a = Float(s) / Float(sides) * 2 * .pi
                let n = side * cos(a) + binormal * sin(a)
                positions.append(p + n * radius)
                normals.append(n)
            }
        }
        for i in 0..<(points.count - 1) {
            for s in 0..<sides {
                let a = UInt32(i * sides + s)
                let b = UInt32(i * sides + (s + 1) % sides)
                let c = a + UInt32(sides)
                let d = b + UInt32(sides)
                indices += [a, b, c, b, d, c]
            }
        }
        var descriptor = MeshDescriptor(name: "tube")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    /// A gently sagging curve between two points, like string hung between two tacks.
    static func sag(from a: SIMD3<Float>, to b: SIMD3<Float>, depth: Float, t: Float) -> SIMD3<Float> {
        let p = a + (b - a) * t
        return p - SIMD3<Float>(0, depth * 4 * t * (1 - t), 0)
    }
}

/// Deterministic randomness so a given item always looks the same on every device.
nonisolated struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(_ seed: UInt32) { state = UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Float { Float.random(in: 0...1, using: &self) }
    mutating func range(_ r: ClosedRange<Float>) -> Float { Float.random(in: r, using: &self) }
}
