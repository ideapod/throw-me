import ARKit
import QuartzCore
import simd

/// Where the wearer's head is and which way it faces. visionOS never tells apps where the eyes
/// look, so head direction is our stand-in for "gazing along the string".
/// Works in the simulator (the simulated camera has a pose) and on device without a permission prompt.
final class HeadTracker {
    private let session = ARKitSession()
    private let world = WorldTrackingProvider()
    private(set) var isRunning = false

    func start() async {
        guard WorldTrackingProvider.isSupported, !isRunning else { return }
        do {
            try await session.run([world])
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    var transform: simd_float4x4? {
        guard isRunning,
              let anchor = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              anchor.isTracked else { return nil }
        return anchor.originFromAnchorTransform
    }

    var position: SIMD3<Float>? {
        transform.map { SIMD3($0.columns.3.x, $0.columns.3.y, $0.columns.3.z) }
    }

    var forward: SIMD3<Float>? {
        transform.map { -simd_normalize(SIMD3($0.columns.2.x, $0.columns.2.y, $0.columns.2.z)) }
    }
}
