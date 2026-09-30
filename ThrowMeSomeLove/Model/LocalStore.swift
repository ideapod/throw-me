import Foundation

/// Everything that lives on this device between launches.
nonisolated struct LocalState: Codable, Sendable {
    var inbox: [LoveString] = []
    var hung: [HungString] = []
    var shelf: [LoveString] = []
    var postboxPosition: SIMD3<Float>?
    /// Optional so state saved before the welcome gift existed still loads (and still gets one).
    var welcomeDelivered: Bool?
}

/// Tiny JSON-file persistence. Good enough until the data outgrows one file.
enum LocalStore {
    private static var url: URL {
        let dir = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "state.json")
    }

    static func load() -> LocalState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(LocalState.self, from: data) else { return LocalState() }
        return state
    }

    static func save(_ state: LocalState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
