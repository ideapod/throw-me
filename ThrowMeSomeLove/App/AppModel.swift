import Foundation
import Observation

/// App-wide state shared by the home window, the inbox volume and the immersive room.
@Observable
final class AppModel {
    static let maxHungStrings = 5

    enum RoomMode { case idle, making }

    var immersiveOpen = false
    var mode: RoomMode = .idle

    private(set) var inbox: [LoveString]
    private(set) var hung: [HungString]
    /// Strings retired from the wall, waiting in their boxes. (Shelf + bag of holding come later.)
    private(set) var shelf: [LoveString]
    var postboxPosition: SIMD3<Float>? { didSet { save() } }

    /// Set by the inbox when a box is tapped; the room picks it up and puts it on the table.
    var pendingUnwrap: LoveString?

    /// An item on the string being made that was tapped; the room opens the editor window for it.
    var editingItem: StringItem?
    /// An item that was tapped to be looked at; the room opens the viewer window for it.
    var viewingItem: ItemViewRequest?
    /// True while an item viewer window is on screen.
    var viewerOpen = false
    /// An item the viewer asked to take off the string being made.
    var removingItemID: UUID?
    /// The contact just chosen in the contact picker, waiting to become a gift tag.
    var pickedRecipient: Person?
    /// Something in the room asked for the contact picker to open.
    var contactPickerRequested = false
    /// True while the contact picker window is on screen.
    var contactsOpen = false
    /// True while an item editor window is on screen.
    var editorOpen = false
    /// True while the app panel (home window) is on screen.
    var homeOpen = false
    /// Content saved by the editor window, waiting for the room to clip it on.
    var completedEdit: StringItem?

    let transport: ThrowTransport
    private var welcomeDelivered: Bool

    init(transport: ThrowTransport = LoopbackTransport()) {
        let state = LocalStore.load()
        inbox = state.inbox
        hung = state.hung
        shelf = state.shelf
        postboxPosition = state.postboxPosition
        welcomeDelivered = state.welcomeDelivered ?? false
        self.transport = transport
        transport.onArrival = { [weak self] string in self?.receive(string) }
    }

    /// Puts the welcome gift in the inbox the first time the app runs.
    func deliverWelcomeIfNeeded() {
        guard !welcomeDelivered else { return }
        welcomeDelivered = true
        receive(WelcomeGift.make())
    }

    // MARK: Sending

    func post(_ string: LoveString) {
        Task { try? await transport.send(string) }
    }

    // MARK: Receiving

    func receive(_ string: LoveString) {
        inbox.append(string)
        save()
    }

    func requestUnwrap(_ id: UUID) {
        guard pendingUnwrap == nil, let index = inbox.firstIndex(where: { $0.id == id }) else { return }
        pendingUnwrap = inbox.remove(at: index)
        save()
    }

    /// Hangs a string; if the wall is full, the oldest goes back in its box on the shelf.
    func hang(_ string: LoveString, at position: SIMD3<Float>, yaw: Float) {
        hung.append(HungString(string: string, position: position, yaw: yaw))
        while hung.count > Self.maxHungStrings {
            shelf.insert(hung.removeFirst().string, at: 0)
        }
        save()
    }

    func move(hungID: UUID, to position: SIMD3<Float>) {
        guard let index = hung.firstIndex(where: { $0.id == hungID }) else { return }
        hung[index].position = position
        save()
    }

    // MARK: Debug

    func resendWelcome() {
        welcomeDelivered = false
        deliverWelcomeIfNeeded()
    }

    func dropTestGift() {
        let kinds: [ItemKind] = [.sound, .photo, .sound, .note, .sound, .photo, .sound]
        receive(LoveString(senderName: "Test Sender", recipientName: "You", items: kinds.map(StringItem.random),
                           sender: Person(name: "Test Sender")))
    }

    private func save() {
        LocalStore.save(LocalState(inbox: inbox, hung: hung, shelf: shelf, postboxPosition: postboxPosition,
                                   welcomeDelivered: welcomeDelivered))
    }
}
