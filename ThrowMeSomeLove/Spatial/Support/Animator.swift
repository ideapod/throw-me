import Foundation
import RealityKit

/// Frame-driven tweens for motion RealityKit's `move(to:)` can't express (arcs, opacity, sequences).
/// Driven by the scene's update event, so it runs at display rate.
final class Animator {
    private struct Job {
        var elapsed: Float = 0
        let duration: Float
        let step: (Float) -> Void
        let done: (() -> Void)?
    }

    private var jobs: [UUID: Job] = [:]

    @discardableResult
    func run(_ duration: Float, delay: Float = 0, ease: @escaping (Float) -> Float = Ease.inOut,
             step: @escaping (Float) -> Void, done: (() -> Void)? = nil) -> UUID {
        let id = UUID()
        // A negative starting elapsed time acts as a delay.
        var job = Job(duration: max(duration, 0.001), step: { t in step(ease(t)) }, done: done)
        job.elapsed = -delay
        jobs[id] = job
        return id
    }

    func cancel(_ id: UUID) { jobs[id] = nil }

    func tick(_ dt: Float) {
        for (id, var job) in jobs {
            job.elapsed += dt
            if job.elapsed < 0 { jobs[id] = job; continue }
            let t = min(job.elapsed / job.duration, 1)
            job.step(t)
            if t >= 1 {
                jobs[id] = nil
                job.done?()
            } else {
                jobs[id] = job
            }
        }
    }

    /// Fades an entity's opacity from its current value.
    func fade(_ entity: Entity, to target: Float, duration: Float, delay: Float = 0, done: (() -> Void)? = nil) {
        let start = entity.components[OpacityComponent.self]?.opacity ?? 1
        run(duration, delay: delay, step: { t in
            entity.components.set(OpacityComponent(opacity: start + (target - start) * t))
        }, done: done)
    }

    /// Scales an entity uniformly with an optional overshoot for a playful pop.
    func pop(_ entity: Entity, to target: Float, duration: Float = 0.35, delay: Float = 0, done: (() -> Void)? = nil) {
        let start = entity.scale.x
        run(duration, delay: delay, ease: Ease.backOut, step: { t in
            entity.scale = .init(repeating: start + (target - start) * t)
        }, done: done)
    }
}

nonisolated enum Ease {
    static func inOut(_ t: Float) -> Float { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }
    static func out(_ t: Float) -> Float { 1 - (1 - t) * (1 - t) }
    static func linear(_ t: Float) -> Float { t }
    static func backOut(_ t: Float) -> Float {
        let c1: Float = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
}
