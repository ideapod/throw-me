import RealityKit
import SwiftUI

enum SceneID {
    static let home = "home"
    static let inbox = "inbox"
    static let room = "room"
    static let editor = "editor"
    static let viewer = "viewer"
    static let contacts = "contacts"
}

@main
struct ThrowMeSomeLoveApp: App {
    @State private var model = AppModel()
    @State private var immersionStyle: any ImmersionStyle = MixedImmersionStyle.mixed

    init() {
        RoleComponent.registerComponent()
    }

    var body: some SwiftUI.Scene {
        WindowGroup(id: SceneID.home) {
            HomeView()
                .environment(model)
        }
        .defaultSize(width: 480, height: 560)

        WindowGroup(id: SceneID.inbox) {
            InboxView()
                .environment(model)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.36, height: 0.36, depth: 0.36, in: .meters)

        WindowGroup(id: SceneID.editor, for: StringItem.self) { $item in
            if let item {
                ItemEditorView(item: item)
                    .environment(model)
            }
        }
        .defaultSize(width: 520, height: 440)
        .windowResizability(.contentSize)
        // Opens close to you and within reach, like other small tool windows.
        .defaultWindowPlacement { _, _ in WindowPlacement(.utilityPanel) }
        // A one-off tool window; don't bring it back on the next launch.
        .restorationBehavior(.disabled)

        WindowGroup(id: SceneID.viewer, for: ItemViewRequest.self) { $request in
            if let request {
                ItemViewerView(request: request)
                    .environment(model)
            }
        }
        .defaultSize(width: 520, height: 620)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, _ in WindowPlacement(.utilityPanel) }
        // A one-off tool window; don't bring it back on the next launch.
        .restorationBehavior(.disabled)

        WindowGroup(id: SceneID.contacts) {
            ContactPickerWindow()
                .environment(model)
        }
        .defaultSize(width: 520, height: 640)
        .defaultWindowPlacement { _, _ in WindowPlacement(.utilityPanel) }
        .restorationBehavior(.disabled)

        ImmersiveSpace(id: SceneID.room) {
            RoomView()
                .environment(model)
        }
        .immersionStyle(selection: $immersionStyle, in: .mixed)
    }
}
