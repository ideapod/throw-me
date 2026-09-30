import RealityKit
import SwiftUI

/// The mixed immersive space: your real room plus the workshop, postbox, table and hung strings.
struct RoomView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var room = RoomController()

    var body: some View {
        RealityView { content, attachments in
            room.setUp(model: model)
            content.add(room.root)
            room.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                room.tick(Float(event.deltaTime))
            }
            if let palette = attachments.entity(for: "palette") { room.placePalette(palette) }
            if let label = attachments.entity(for: "postbox") { room.placePostboxLabel(label) }
            if let hint = attachments.entity(for: "hint") { room.placeHint(hint) }
        } attachments: {
            Attachment(id: "palette") { PaletteView(room: room) }
            Attachment(id: "postbox") { PostboxLabel(room: room) }
            Attachment(id: "hint") {
                Label("Tap to unwrap", systemImage: "hand.tap")
                    .font(.title3)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassBackgroundEffect()
            }
        }
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    let p = value.convert(value.location3D, from: .local, to: .scene)
                    room.dragChanged(value.entity, at: p, time: value.time.timeIntervalSinceReferenceDate)
                }
                .onEnded { _ in room.dragEnded() }
        )
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in room.tap(value.entity) }
        )
        .task { await room.startTracking() }
        .onChange(of: model.mode) { room.sync() }
        .onChange(of: model.pendingUnwrap?.id) { room.sync() }
        .onChange(of: model.hung.map(\.id)) { room.sync() }
        .onChange(of: model.editingItem) {
            guard let item = model.editingItem else { return }
            openWindow(id: SceneID.editor, value: item)
            model.editingItem = nil
        }
        .onChange(of: windowOverWorkshop) { room.setWindowOpen(windowOverWorkshop) }
        .onChange(of: model.contactPickerRequested) {
            guard model.contactPickerRequested else { return }
            openWindow(id: SceneID.contacts)
            model.contactPickerRequested = false
        }
        .onChange(of: model.pickedRecipient) {
            guard let person = model.pickedRecipient else { return }
            room.setRecipient(person)
            model.pickedRecipient = nil
        }
        .onChange(of: model.viewingItem) {
            guard let request = model.viewingItem else { return }
            openWindow(id: SceneID.viewer, value: request)
            model.viewingItem = nil
        }
        .onChange(of: model.removingItemID) {
            guard let id = model.removingItemID else { return }
            room.takeOff(itemID: id)
            model.removingItemID = nil
        }
        .onChange(of: model.completedEdit) {
            guard let item = model.completedEdit else { return }
            room.applyEdit(item)
            model.completedEdit = nil
        }
        .onAppear {
            model.immersiveOpen = true
            room.setWindowOpen(windowOverWorkshop)
        }
        .onDisappear {
            model.immersiveOpen = false
            model.mode = .idle
            // Always leave a window behind, or the app has nothing to show on its next launch.
            if !model.homeOpen { openWindow(id: SceneID.home) }
        }
    }
}

extension RoomView {
    /// An editor, or the app panel while making, is open and the workshop should step back.
    private var windowOverWorkshop: Bool {
        model.editorOpen || model.viewerOpen || model.contactsOpen || (model.homeOpen && model.mode == .making)
    }
}

/// The tool palette under the string you're making: a glass tray, styled like a visionOS toolbar,
/// with wells holding an empty light, photo and note to drag up, plus the workshop's tools.
struct PaletteView: View {
    static let size = CGSize(width: 860, height: 210)
    private static let padding: CGFloat = 22
    private static let hintHeight: CGFloat = 30
    private static let wellSize = CGSize(width: 140, height: size.height - padding * 2 - hintHeight - 10)
    private static let wellSpacing: CGFloat = 12

    /// Centre of a well in the view's own points, so the room can put a 3D item there.
    static func wellCentre(_ index: Int) -> CGPoint {
        CGPoint(x: padding + wellSize.width / 2 + CGFloat(index) * (wellSize.width + wellSpacing),
                y: padding + hintHeight + 10 + wellSize.height / 2)
    }

    let room: RoomController
    @Environment(\.openWindow) private var openWindow
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hint)
                .font(.headline)
                .frame(height: Self.hintHeight)
            HStack(spacing: Self.wellSpacing) {
                ForEach(ItemKind.allCases, id: \.self) { kind in
                    well(kind.label)
                }
                // The gift tag well: choose who it's for, then drag the tag onto the wrapped gift.
                well("Gift tag")
                    .overlay {
                        if !room.tagWaiting {
                            Button {
                                model.contactPickerRequested = true
                            } label: {
                                Label("Who's it for?", systemImage: "person.crop.circle.badge.plus")
                                    .labelStyle(.iconOnly)
                                    .font(.system(size: 34))
                            }
                            .buttonBorderShape(.circle)
                            .buttonStyle(.borderless)
                            .help("Who's it for?")
                            .padding(.bottom, 16)
                        }
                    }
                Spacer(minLength: 16)
                tools
            }
        }
        .padding(Self.padding)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .glassBackgroundEffect(in: .rect(cornerRadius: 40))
    }

    private func well(_ label: String) -> some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.black.opacity(0.14))
            .frame(width: Self.wellSize.width, height: Self.wellSize.height)
            .overlay(alignment: .bottom) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
    }

    private var tools: some View {
        VStack(spacing: 12) {
            Button {
                room.wrap()
            } label: {
                Label("Wrap it up", systemImage: "gift")
            }
            .buttonStyle(.borderedProminent)
            .disabled(room.draftCount == 0 || room.emptyCount > 0 || room.hasOutgoingBox)

            HStack(spacing: 12) {
                Button {
                    openWindow(id: SceneID.home)
                } label: {
                    Label("Show app panel", systemImage: "house")
                }
                .help("Show app panel")

                Button {
                    room.clearDraft()
                } label: {
                    Label("Clear string", systemImage: "arrow.uturn.backward")
                }
                .help("Clear string")
                .disabled(room.draftCount == 0)
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .buttonStyle(.borderless)
        }
    }

    private var hint: String {
        if room.hasOutgoingBox && !room.giftAddressed {
            return room.tagWaiting ? "Drag the gift tag onto your gift" : "Who's it for? Choose someone for the gift tag"
        }
        if room.hasOutgoingBox { return "Pick up your gift and throw it into the post box" }
        if room.draftCount == 0 { return "Drag a light, photo or note up onto the string" }
        if room.emptyCount == 1 { return "Tap the empty one on the string to fill it" }
        if room.emptyCount > 1 { return "Tap the empty ones on the string to fill them" }
        return "Add more, or wrap it up when you're ready"
    }
}

private extension ItemKind {
    var label: String {
        switch self {
        case .sound: "Sound"
        case .photo: "Photo or video"
        case .note: "Note"
        }
    }
}

/// Floats above the postbox so its purpose is obvious wherever you are in the world.
struct PostboxLabel: View {
    let room: RoomController

    var body: some View {
        VStack(spacing: 4) {
            Text("Post Box")
                .font(.system(size: 64, weight: .bold, design: .serif))
            Text(room.needsTagNudge && !room.giftAddressed ? "Tie a gift tag on first!"
                 : room.isOverPostbox ? "Let go to post it!"
                 : room.hasOutgoingBox ? "Throw your gift in here!" : "Wrap your gift and send it")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 26)
        .glassBackgroundEffect()
    }
}
