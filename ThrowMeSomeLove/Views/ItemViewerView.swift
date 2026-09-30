import AVFoundation
import AVKit
import SwiftUI

/// Shows one item from a string, large: the photo or video, the note, or a sound to play.
/// Items on the string you're making can be changed or taken off from here.
struct ItemViewerView: View {
    let request: ItemViewRequest
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    private var item: StringItem { request.item }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Group {
                    switch item.kind {
                    case .photo: PhotoView(item: item)
                    case .note: NoteCard(text: item.text ?? "", seed: item.seed).frame(width: 380, height: 380)
                    case .sound: SoundView(item: item)
                    }
                }
                .frame(maxHeight: .infinity)

                if request.editable {
                    HStack(spacing: 16) {
                        Button("Change", systemImage: "pencil") {
                            openWindow(id: SceneID.editor, value: item)
                            dismissWindow()
                        }
                        Button("Take off string", systemImage: "scissors", role: .destructive) {
                            model.removingItemID = item.id
                            dismissWindow()
                        }
                    }
                }
            }
            .padding(28)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismissWindow() }
                }
            }
        }
        .onAppear { model.viewerOpen = true }
        .onDisappear { model.viewerOpen = false }
    }

    private var title: String {
        switch item.kind {
        case .photo: item.media?.kind == .video ? "Video" : "Photo"
        case .note: "Note"
        case .sound: "Sound"
        }
    }
}

/// The photo in a polaroid frame, or the video playing inside one.
private struct PhotoView: View {
    let item: StringItem
    @State private var image: UIImage?
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if item.generated {
                    PlaceholderPhoto(seed: item.seed)
                } else {
                    Color(white: 0.3)
                }
            }
            .frame(width: 360, height: 360)
            .clipped()
            Color.clear.frame(height: 56)
        }
        .padding([.horizontal, .top], 16)
        .background(Color(uiColor: Palette.polaroid), in: .rect(cornerRadius: 4))
        .rotationEffect(.degrees(Double(item.seed % 5) - 2))
        .task {
            guard let media = item.media else { return }
            let url = MediaStore.url(for: media)
            switch media.kind {
            case .video:
                let player = AVPlayer(url: url)
                self.player = player
                player.play()
            case .image:
                image = (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
            case .audio:
                break
            }
        }
        .onDisappear { player?.pause() }
    }
}

/// A big warm bulb you tap to hear the sound.
private struct SoundView: View {
    let item: StringItem
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false

    var body: some View {
        VStack(spacing: 20) {
            Button {
                isPlaying ? stop() : play()
            } label: {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color(uiColor: Palette.bulbWarm), Color(uiColor: Palette.bulbWarm).opacity(0.25)],
                                             center: .center, startRadius: 10, endRadius: 110))
                        .frame(width: 200, height: 200)
                        .scaleEffect(isPlaying ? 1.08 : 1)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPlaying)
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(Palette.ink)
                }
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Stop" : "Play")

            if let player {
                Text(String(format: "0:%02d", Int(player.duration.rounded())))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .task { load() }
        .onDisappear { stop() }
    }

    private func load() {
        let url: URL? = if let media = item.media { MediaStore.url(for: media) }
            else { SoundBank.shared.fileURL(for: .chime(Int(item.seed % 7))) }
        player = url.flatMap { try? AVAudioPlayer(contentsOf: $0) }
    }

    private func play() {
        guard let player else { return }
        player.currentTime = 0
        player.play()
        isPlaying = true
        Task {
            while player.isPlaying { try? await Task.sleep(for: .milliseconds(100)) }
            isPlaying = false
        }
    }

    private func stop() {
        player?.stop()
        isPlaying = false
    }
}
