import Foundation

/// How strings travel between people. The app only talks to this protocol, so the backend
/// (CloudKit today, possibly a cross-platform service later) can be swapped without touching
/// the spatial code.
protocol ThrowTransport: AnyObject {
    func send(_ string: LoveString) async throws
    /// Called on the main actor whenever a new string lands in this user's inbox.
    var onArrival: ((LoveString) -> Void)? { get set }
}

/// Posts everything straight back to the local inbox after a short flight time.
/// Lets the full loop run on one simulator with no account or network.
final class LoopbackTransport: ThrowTransport {
    var onArrival: ((LoveString) -> Void)?
    var flightTime: Duration = .seconds(2)

    func send(_ string: LoveString) async throws {
        try await Task.sleep(for: flightTime)
        // Pretend the person it was addressed to has sent it straight back to us.
        var delivered = string
        delivered.sender = string.recipient ?? Person(name: "You (test)")
        delivered.senderName = delivered.sender?.name ?? "You (test)"
        onArrival?(delivered)
    }
}
