import AVFoundation
import RealityKit

/// Small synthesized sounds so the loop has voice before real audio assets exist.
/// Each sound is rendered once to a .caf in Caches, then played spatially from entities.
enum Sound: Hashable {
    /// A soft bell. Degree indexes a pentatonic scale so any string sounds pleasant.
    case chime(Int)
    case pop
    case rustle
    case clunk
    case whoosh

    fileprivate var name: String {
        switch self {
        case .chime(let d): "chime-\(d)"
        case .pop: "pop"
        case .rustle: "rustle"
        case .clunk: "clunk"
        case .whoosh: "whoosh"
        }
    }
}

final class SoundBank {
    static let shared = SoundBank()

    private var cache: [Sound: AudioFileResource] = [:]
    private static let sampleRate = 44_100.0
    private static let pentatonic: [Double] = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.66]

    func play(_ sound: Sound, on entity: Entity, gain: Double = -6) {
        Task {
            guard let resource = await resource(sound) else { return }
            if entity.components[SpatialAudioComponent.self] == nil {
                entity.components.set(SpatialAudioComponent(gain: gain))
            }
            entity.playAudio(resource)
        }
    }

    /// Plays a recorded or imported clip from disk, spatially from the entity.
    func play(file url: URL, on entity: Entity, gain: Double = 0) {
        Task {
            guard let resource = try? await AudioFileResource(contentsOf: url) else { return }
            entity.components.set(SpatialAudioComponent(gain: gain))
            entity.playAudio(resource)
        }
    }

    /// The rendered sound on disk, so windows can play it with AVAudioPlayer too.
    func fileURL(for sound: Sound) -> URL? {
        let url = URL.cachesDirectory.appending(path: "\(sound.name).caf")
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            guard Self.write(Self.samples(for: sound), to: url) else { return nil }
        }
        return url
    }

    private func resource(_ sound: Sound) async -> AudioFileResource? {
        if let hit = cache[sound] { return hit }
        guard let url = fileURL(for: sound),
              let resource = try? await AudioFileResource(contentsOf: url) else { return nil }
        cache[sound] = resource
        return resource
    }

    // MARK: Synthesis

    private static func samples(for sound: Sound) -> [Float] {
        switch sound {
        case .chime(let degree):
            let f = pentatonic[((degree % pentatonic.count) + pentatonic.count) % pentatonic.count]
            return synth(seconds: 1.6) { t in
                let env = exp(-t * 3.2) * min(t / 0.004, 1)
                return env * (0.6 * sin(2 * .pi * f * t) + 0.25 * sin(2 * .pi * f * 2.01 * t) * exp(-t * 4)
                    + 0.12 * sin(2 * .pi * f * 3.02 * t) * exp(-t * 6))
            }
        case .pop:
            return synth(seconds: 0.18) { t in
                let f = 900 - 3000 * t
                return exp(-t * 28) * sin(2 * .pi * f * t) * 0.7
            }
        case .rustle:
            var rng = SeededRandom(3)
            return synth(seconds: 0.5) { t in
                let crinkle = Double(rng.range(-1...1)) * (0.5 + 0.5 * sin(2 * .pi * 23 * t))
                return crinkle * exp(-t * 6) * 0.35
            }
        case .clunk:
            var rng = SeededRandom(5)
            return synth(seconds: 0.45) { t in
                let body = sin(2 * .pi * 95 * t) * exp(-t * 12)
                let knock = Double(rng.range(-1...1)) * exp(-t * 60)
                return body * 0.8 + knock * 0.4
            }
        case .whoosh:
            var rng = SeededRandom(9)
            return synth(seconds: 0.6) { t in
                let env = sin(.pi * min(t / 0.6, 1))
                return Double(rng.range(-1...1)) * env * 0.25
            }
        }
    }

    private static func synth(seconds: Double, _ f: (Double) -> Double) -> [Float] {
        let count = Int(seconds * sampleRate)
        return (0..<count).map { Float(f(Double($0) / sampleRate)) }
    }

    private static func write(_ samples: [Float], to url: URL) -> Bool {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return false }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            return true
        } catch {
            return false
        }
    }
}
