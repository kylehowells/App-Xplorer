import Foundation

// MARK: - TransportAdapter

/// Protocol for transport adapters (HTTP, WebSocket, Iroh, Bluetooth, etc.)
///
/// Each transport adapter is responsible for:
/// 1. Listening for incoming connections/messages
/// 2. Converting transport-specific data to Request objects
/// 3. Passing requests to the RequestHandler
/// 4. Converting Response objects back to transport format
/// 5. Sending responses to clients
public protocol TransportAdapter: AnyObject {
	/// The request handler to dispatch requests to
	var requestHandler: RequestHandler? { get set }

	/// Start the transport adapter
	func start() throws

	/// Stop the transport adapter
	func stop()

	/// Whether the adapter is currently running
	var isRunning: Bool { get }
}
