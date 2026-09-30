import AVFoundation
import UIKit

/// Keeps the photos, videos and sounds people put on strings, already trimmed to the app's limits:
/// photos ≤ 2048px JPEG (~2MB), clips ≤ 15 seconds.
nonisolated enum MediaStore {
    static let maxClipSeconds: Double = 15

    enum ImportError: Error { case unreadable, exportFailed }

    static var directory: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "media")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for ref: MediaRef) -> URL { directory.appending(path: ref.file) }

    static func importImage(data: Data) throws -> MediaRef {
        guard let image = UIImage(data: data) else { throw ImportError.unreadable }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 2048 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { throw ImportError.unreadable }
        let ref = MediaRef(file: "\(UUID().uuidString).jpg", kind: .image)
        try jpeg.write(to: url(for: ref))
        return ref
    }

    static func importImage(from source: URL) throws -> MediaRef {
        try importImage(data: Data(contentsOf: source))
    }

    static func importVideo(from source: URL) async throws -> MediaRef {
        let ref = MediaRef(file: "\(UUID().uuidString).mp4", kind: .video)
        try await export(source, to: url(for: ref), preset: AVAssetExportPresetMediumQuality, type: .mp4)
        return ref
    }

    static func importAudio(from source: URL) async throws -> MediaRef {
        let ref = MediaRef(file: "\(UUID().uuidString).m4a", kind: .audio)
        try await export(source, to: url(for: ref), preset: AVAssetExportPresetAppleM4A, type: .m4a)
        return ref
    }

    /// Copies a file (e.g. one bundled with the app) into the media folder as-is.
    static func copyIn(_ source: URL, kind: MediaRef.Kind) throws -> MediaRef {
        let ref = MediaRef(file: "\(UUID().uuidString).\(source.pathExtension)", kind: kind)
        try FileManager.default.copyItem(at: source, to: url(for: ref))
        return ref
    }

    /// Adopts a file already recorded into our folder (the recorder caps its own length).
    static func adoptRecording(at source: URL) throws -> MediaRef {
        let ref = MediaRef(file: "\(UUID().uuidString).m4a", kind: .audio)
        try FileManager.default.moveItem(at: source, to: url(for: ref))
        return ref
    }

    private static func export(_ source: URL, to destination: URL, preset: String, type: AVFileType) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw ImportError.exportFailed }
        let duration = try await asset.load(.duration)
        session.timeRange = CMTimeRange(start: .zero, duration: min(duration, CMTime(seconds: maxClipSeconds, preferredTimescale: 600)))
        try await session.export(to: destination, as: type)
    }

    /// A square, centre-cropped image for a polaroid: the photo itself or a video's first frame.
    static func squareImage(for ref: MediaRef) async -> CGImage? {
        let source: CGImage?
        switch ref.kind {
        case .image:
            // Read via Data: `URL.path()` percent-encodes the space in "Application Support".
            source = (try? Data(contentsOf: url(for: ref))).flatMap { UIImage(data: $0)?.cgImage }
        case .video:
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url(for: ref)))
            generator.appliesPreferredTrackTransform = true
            source = try? await generator.image(at: .zero).image
        case .audio:
            source = nil
        }
        guard let source else { return nil }
        let side = min(source.width, source.height)
        let crop = CGRect(x: (source.width - side) / 2, y: (source.height - side) / 2, width: side, height: side)
        return source.cropping(to: crop)
    }
}
