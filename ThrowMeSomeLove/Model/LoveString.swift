import Foundation

/// What hangs from the string. Each kind has its own physical form:
/// sounds are glowing bulbs, photos are pegged polaroids, text is a hanging note.
nonisolated enum ItemKind: String, Codable, CaseIterable, Sendable {
    case sound
    case photo
    case note
}

/// A media file the user picked or recorded, stored in the app's media folder.
nonisolated struct MediaRef: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case image, video, audio }
    var file: String
    var kind: Kind
}

/// One thing clipped onto a string.
///
/// Items start empty when dragged off the palette and are filled in by tapping them.
/// `generated` items draw placeholder media from `seed` (used for test gifts).
nonisolated struct StringItem: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var kind: ItemKind
    var seed: UInt32
    var text: String?
    var media: MediaRef?
    var generated = false

    var isFilled: Bool {
        switch kind {
        case .note: !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .sound, .photo: generated || media != nil
        }
    }

    init(id: UUID = UUID(), kind: ItemKind, seed: UInt32, text: String? = nil, media: MediaRef? = nil, generated: Bool = false) {
        self.id = id
        self.kind = kind
        self.seed = seed
        self.text = text
        self.media = media
        self.generated = generated
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(ItemKind.self, forKey: .kind)
        seed = try c.decode(UInt32.self, forKey: .seed)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        media = try c.decodeIfPresent(MediaRef.self, forKey: .media)
        // Items saved before real media existed were all placeholders.
        generated = try c.decodeIfPresent(Bool.self, forKey: .generated) ?? (media == nil)
    }

    static func empty(_ kind: ItemKind) -> StringItem {
        StringItem(kind: kind, seed: UInt32.random(in: 0...UInt32.max))
    }

    static func random(_ kind: ItemKind) -> StringItem {
        let seed = UInt32.random(in: 0...UInt32.max)
        let text = kind == .note ? NoteLines.all[Int(seed % UInt32(NoteLines.all.count))] : nil
        return StringItem(kind: kind, seed: seed, text: text, generated: true)
    }
}

nonisolated enum NoteLines {
    static let all = [
        "thinking of you",
        "tea soon?",
        "miss your face",
        "you're my favourite",
        "this made me smile",
        "big hug x",
        "remember this?",
        "wish you were here",
    ]
}

/// Someone a string is from or to. `photo` is their contact picture, if we have one.
nonisolated struct Person: Codable, Hashable, Sendable {
    var name: String
    /// Email or phone number, used to find them on the service (backend to come).
    var handle: String?
    var photo: MediaRef?

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

/// Asks for an item to be shown large. `editable` items (on the string you're making)
/// can be changed or taken off; received ones are just for looking at.
nonisolated struct ItemViewRequest: Codable, Hashable, Sendable {
    var item: StringItem
    var editable: Bool
}

/// A finite "some love" gift, or a string two people keep growing together.
nonisolated enum StringKind: String, Codable, Sendable {
    case someLove
    case growing
}

nonisolated struct LoveString: Identifiable, Codable, Hashable, Sendable {
    static let maxItems = 12

    var id = UUID()
    var kind: StringKind = .someLove
    var senderName: String
    var recipientName: String
    var items: [StringItem]
    /// Who it's from / to, with their picture. Optional so older saved strings still load.
    var sender: Person?
    var recipient: Person?
    var createdAt = Date()
}

/// A received string hanging somewhere in the room.
nonisolated struct HungString: Identifiable, Codable, Hashable, Sendable {
    var string: LoveString
    /// Centre of the string in immersive-space coordinates.
    /// On device this will become a world anchor so it survives across sessions.
    var position: SIMD3<Float>
    var yaw: Float
    var id: UUID { string.id }
}
