import SwiftUI

/// The small window you start from.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color(red: 0.85, green: 0.3, blue: 0.3))
                Text("throw me some love")
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                Text("String together little lights and send them to someone.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button {
                    Task { await sendSomeLove() }
                } label: {
                    Label("Send some love", systemImage: "sparkles")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    openWindow(id: SceneID.inbox)
                } label: {
                    Label(model.inbox.isEmpty ? "Place my inbox" : "My inbox (\(model.inbox.count))", systemImage: "shippingbox")
                        .frame(maxWidth: 260)
                }

                Button {
                    Task { await toggleRoom() }
                } label: {
                    Label(model.immersiveOpen ? "Leave my room" : "Enter my room", systemImage: "lamp.table")
                        .frame(maxWidth: 260)
                }
            }

            #if DEBUG
            HStack {
                Button("Drop a test gift in my inbox") { model.dropTestGift() }
                Button("Resend welcome gift") { model.resendWelcome() }
            }
            .font(.footnote)
            #endif
        }
        .padding(40)
        .onChange(of: model.inbox.count) { old, new in
            // Something arrived: make sure the inbox is out so you can see the box land.
            if new > old { openWindow(id: SceneID.inbox) }
        }
        .task {
            model.deliverWelcomeIfNeeded()
            await runLaunchDemo()
        }
        .onAppear { model.homeOpen = true }
        .onDisappear { model.homeOpen = false }
    }

    private func sendSomeLove() async {
        model.mode = .making
        if !model.immersiveOpen { await openImmersiveSpace(id: SceneID.room) }
        // Get out of the way while you make; the palette's house button brings this panel back.
        dismissWindow(id: SceneID.home)
    }

    private func toggleRoom() async {
        if model.immersiveOpen {
            await dismissImmersiveSpace()
        } else {
            model.mode = .idle
            await openImmersiveSpace(id: SceneID.room)
        }
    }

    /// Debug only: `-demo making|making-edit|welcome|welcome-photo|tag|contacts|string|view-sound|view-photo|view-note|postboxes|inbox|unwrap|reveal|edit-sound|edit-photo|edit-note` jumps straight to a state.
    private func runLaunchDemo() async {
        #if DEBUG
        guard let demo = UserDefaults.standard.string(forKey: "demo") else { return }
        switch demo {
        case "making":
            await sendSomeLove()
        case "inbox":
            for _ in 0..<3 { model.dropTestGift() }
            openWindow(id: SceneID.inbox)
        case "unwrap", "reveal":
            model.dropTestGift()
            await openImmersiveSpace(id: SceneID.room)
            if let id = model.inbox.last?.id { model.requestUnwrap(id) }
        case "welcome":
            await openImmersiveSpace(id: SceneID.room)
            if let id = model.inbox.first(where: { $0.senderName == WelcomeGift.senderName })?.id { model.requestUnwrap(id) }
        case "welcome-photo":
            if let item = WelcomeGift.make().items.first(where: { $0.kind == .photo }) {
                openWindow(id: SceneID.viewer, value: ItemViewRequest(item: item, editable: false))
            }
        case "tag":
            await sendSomeLove()
            try? await Task.sleep(for: .seconds(2))
            model.pickedRecipient = Person(name: "Kate Bell", handle: "kate-bell@mac.com")
        case "contacts":
            openWindow(id: SceneID.contacts)
        case "string":
            await sendSomeLove()
        case "view-sound", "view-photo", "view-note":
            let kind = ItemKind(rawValue: String(demo.dropFirst(5))) ?? .note
            openWindow(id: SceneID.viewer, value: ItemViewRequest(item: .random(kind), editable: true))
        case "postboxes":
            await openImmersiveSpace(id: SceneID.room)
            dismissWindow(id: SceneID.home)
        case "making-edit":
            await sendSomeLove()
            try? await Task.sleep(for: .seconds(2))
            openWindow(id: SceneID.editor, value: StringItem.empty(.sound))
        case "edit-sound", "edit-photo", "edit-note":
            let kind = ItemKind(rawValue: String(demo.dropFirst(5))) ?? .note
            openWindow(id: SceneID.editor, value: StringItem.empty(kind))
        default:
            break
        }
        #endif
    }
}
