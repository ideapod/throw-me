import AVFoundation
import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A small window for filling in one item on the string: record or pick a sound,
/// choose a photo or video, or write (or dictate) a note.
struct ItemEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    let item: StringItem

    var body: some View {
        NavigationStack {
            Group {
                switch item.kind {
                case .note: NoteEditor(item: item, save: save)
                case .photo: PhotoEditor(item: item, save: save)
                case .sound: SoundEditor(item: item, save: save)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismissWindow() }
                }
            }
        }
        .onAppear { model.editorOpen = true }
        .onDisappear { model.editorOpen = false }
    }

    private var title: String {
        switch item.kind {
        case .note: "Write a note"
        case .photo: "Add a photo or video"
        case .sound: "Add a sound"
        }
    }

    private func save(_ updated: StringItem) {
        model.completedEdit = updated
        dismissWindow()
    }
}

// MARK: - Note

private struct NoteEditor: View {
    static let maxLength = 60
    let item: StringItem
    let save: (StringItem) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("What should it say?", text: $text, axis: .vertical)
                .lineLimit(2...4)
                .font(.title2)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onChange(of: text) { if text.count > Self.maxLength { text = String(text.prefix(Self.maxLength)) } }
            Label("Tap the microphone on the keyboard to say it instead", systemImage: "mic")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Text("\(text.count)/\(Self.maxLength)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Hang it", systemImage: "checkmark") {
                    var updated = item
                    updated.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    save(updated)
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            text = item.text ?? ""
            focused = true
        }
    }
}

// MARK: - Photo / video

private struct PhotoEditor: View {
    let item: StringItem
    let save: (StringItem) -> Void
    @State private var selection: PhotosPickerItem?
    @State private var showingFiles = false
    @State private var working = false
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 18) {
            PhotosPicker(selection: $selection, matching: .any(of: [.images, .videos])) {
                Label("Choose from Photos", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: 300)
            }
            .buttonStyle(.borderedProminent)

            Button {
                showingFiles = true
            } label: {
                Label("Find a file", systemImage: "folder")
                    .frame(maxWidth: 300)
            }

            Text("Videos are trimmed to their first \(Int(MediaStore.maxClipSeconds)) seconds.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if working { ProgressView("Getting it ready…") }
            if let failure { Text(failure).foregroundStyle(.red).font(.footnote) }
        }
        .disabled(working)
        .onChange(of: selection) {
            guard let selection else { return }
            Task { await load(selection) }
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.image, .movie]) { result in
            guard case .success(let url) = result else { return }
            Task { await importFile(url) }
        }
    }

    private func load(_ picked: PhotosPickerItem) async {
        await run {
            if picked.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }),
               let movie = try await picked.loadTransferable(type: PickedMovie.self) {
                return try await MediaStore.importVideo(from: movie.url)
            }
            guard let data = try await picked.loadTransferable(type: Data.self) else { throw MediaStore.ImportError.unreadable }
            return try MediaStore.importImage(data: data)
        }
    }

    private func importFile(_ url: URL) async {
        await run {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true {
                return try await MediaStore.importVideo(from: url)
            }
            return try MediaStore.importImage(from: url)
        }
    }

    private func run(_ work: () async throws -> MediaRef) async {
        working = true
        failure = nil
        do {
            var updated = item
            updated.media = try await work()
            save(updated)
        } catch {
            failure = "Couldn't use that one — try another?"
        }
        working = false
    }
}

/// Lets PhotosPicker hand over a video as a file we can copy.
private struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

// MARK: - Sound

private struct SoundEditor: View {
    let item: StringItem
    let save: (StringItem) -> Void
    @State private var recorder = ClipRecorder()
    @State private var player: AVAudioPlayer?
    @State private var showingFiles = false
    @State private var working = false
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 18) {
            Button {
                Task { recorder.isRecording ? recorder.stop() : await recorder.start() }
            } label: {
                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 34))
                    .frame(width: 84, height: 84)
            }
            .buttonBorderShape(.circle)
            .tint(recorder.isRecording ? .red : nil)
            .help(recorder.isRecording ? "Stop recording" : "Record")

            Text(recorder.isRecording || recorder.recordedURL != nil
                 ? String(format: "0:%02d / 0:%02d", Int(recorder.elapsed), Int(MediaStore.maxClipSeconds))
                 : "Tap to record up to \(Int(MediaStore.maxClipSeconds)) seconds")
                .font(.headline.monospacedDigit())

            if recorder.denied {
                Text("Microphone access is off. You can turn it on in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let url = recorder.recordedURL, !recorder.isRecording {
                HStack {
                    Button("Listen", systemImage: "play.fill") {
                        player = try? AVAudioPlayer(contentsOf: url)
                        player?.play()
                    }
                    Button("Use this sound", systemImage: "checkmark") {
                        guard let ref = try? MediaStore.adoptRecording(at: url) else { return }
                        var updated = item
                        updated.media = ref
                        save(updated)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Divider()

            Button {
                showingFiles = true
            } label: {
                Label("Choose a sound file", systemImage: "folder")
            }
            if working { ProgressView() }
            if let failure { Text(failure).foregroundStyle(.red).font(.footnote) }
        }
        .disabled(working)
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.audio]) { result in
            guard case .success(let url) = result else { return }
            Task {
                working = true
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let ref = try? await MediaStore.importAudio(from: url) {
                    var updated = item
                    updated.media = ref
                    save(updated)
                } else {
                    failure = "Couldn't use that file — try another?"
                }
                working = false
            }
        }
        .onDisappear { recorder.stop() }
    }
}

/// Records one short voice clip, stopping itself at the clip limit.
@Observable
final class ClipRecorder {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var recordedURL: URL?
    private(set) var denied = false
    @ObservationIgnored private var recorder: AVAudioRecorder?

    func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            denied = true
            return
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default)
        try? session.setActive(true)

        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return }
        self.recorder = recorder
        recordedURL = nil
        elapsed = 0
        recorder.record(forDuration: MediaStore.maxClipSeconds)
        isRecording = true

        while recorder.isRecording {
            try? await Task.sleep(for: .milliseconds(100))
            elapsed = recorder.currentTime
        }
        isRecording = false
        // The recorder resets its clock on stop, so read the clip's real length back.
        elapsed = (try? AVAudioPlayer(contentsOf: url).duration) ?? elapsed
        recordedURL = url
    }

    func stop() {
        recorder?.stop()
    }
}
