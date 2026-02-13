import Foundation
import AppXplorerServer
import IrohLib

// MARK: - IrohTransportAdapter

/// Iroh transport adapter for P2P connections
///
/// This adapter allows App-Xplorer to accept connections over the Iroh P2P network,
/// enabling debugging across different networks without requiring direct IP connectivity.
///
/// Usage:
/// ```swift
/// let server = AppXplorerServer()
/// let irohTransport = IrohTransportAdapter()
/// server.addTransport(irohTransport)
/// try server.start()
///
/// // Share this node ID with the CLI to connect
/// print("Iroh Node ID: \(irohTransport.nodeId ?? "")")
/// ```
public class IrohTransportAdapter: TransportAdapter {
	/// The Iroh node instance
	private var node: Iroh?

	/// The gossip sender for responding to requests
	private var gossipSender: Sender?

	/// The request handler
	public var requestHandler: RequestHandler?

	/// Whether the adapter is running
	public private(set) var isRunning: Bool = false

	/// The node ID (share this with clients to connect)
	public var nodeId: String? {
		return node?.net().nodeId()
	}

	/// The relay URL (helps with NAT traversal)
	public var relayUrl: String? {
		return node?.net().nodeAddr().relayUrl()
	}

	/// The topic used for request/response communication
	/// This is a blake3 hash of "app-xplorer-rpc" (pre-computed)
	private static let topicHex = "a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd"

	/// Storage path for the Iroh node
	private let storagePath: String

	/// Lock for thread safety
	private let lock = NSLock()

	/// Initialize with optional storage path
	/// - Parameter storagePath: Path for persistent storage (defaults to app's Library/Xplorer/iroh)
	public init(storagePath: String? = nil) {
		if let path = storagePath {
			self.storagePath = path
		} else {
			// Default to Library/Xplorer/iroh
			let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
			self.storagePath = libraryDir.appendingPathComponent("Xplorer/iroh").path
		}
	}

	// MARK: - TransportAdapter

	public func start() throws {
		guard !isRunning else { return }

		// Create storage directory if needed
		try? FileManager.default.createDirectory(
			atPath: storagePath,
			withIntermediateDirectories: true,
			attributes: nil
		)

		print("🌐 Iroh transport starting...")
		print("📁 Storage: \(storagePath)")

		// Use semaphore to bridge async startup
		let semaphore = DispatchSemaphore(value: 0)
		var startError: Error?

		Task {
			do {
				try await self.startAsync()
			} catch {
				startError = error
			}
			semaphore.signal()
		}

		semaphore.wait()

		if let error = startError {
			throw error
		}
	}

	public func stop() {
		guard isRunning else { return }

		Task {
			await self.stopAsync()
		}
	}

	// MARK: - Async Implementation

	/// Start the transport (async version)
	private func startAsync() async throws {
		// Create persistent node
		let node = try await Iroh.persistent(path: storagePath)

		lock.lock()
		self.node = node
		lock.unlock()

		// Wait for network
		try await node.net().waitOnline()

		let nodeId = node.net().nodeId()
		let nodeAddr = node.net().nodeAddr()

		print("🔑 Iroh Node ID: \(nodeId)")
		if let relay = nodeAddr.relayUrl() {
			print("🌐 Relay URL: \(relay)")
		}

		// Subscribe to the RPC topic
		let topic = Self.hexToData(Self.topicHex)
		let callback = IrohRequestCallback(adapter: self)

		let sender = try await node.gossip().subscribe(
			topic: topic,
			bootstrap: [],
			cb: callback
		)

		lock.lock()
		self.gossipSender = sender
		self.isRunning = true
		lock.unlock()

		print("✅ Iroh transport ready")
		print("📱 Share this node ID with clients: \(nodeId)")
	}

	/// Stop the transport (async version)
	private func stopAsync() async {
		lock.lock()
		let sender = self.gossipSender
		let node = self.node
		self.gossipSender = nil
		self.node = nil
		self.isRunning = false
		lock.unlock()

		if let sender = sender {
			try? await sender.cancel()
		}

		if let node = node {
			try? await node.node().shutdown()
		}

		print("🛑 Iroh transport stopped")
	}

	// MARK: - Request Handling

	/// Handle an incoming request message
	func handleRequest(_ data: Data, from peer: String) {
		guard let handler = requestHandler else {
			print("[Iroh] No request handler configured")
			return
		}

		// Parse the request
		guard let (request, requestId) = IrohMessage.parseRequest(from: data) else {
			print("[Iroh] Failed to parse request from \(String(peer.prefix(8)))...")
			return
		}

		print("[Iroh] Request from \(String(peer.prefix(8)))...: \(request.path)")

		// Handle the request (runs on main thread for UI access via RequestHandler)
		let response = handler.handle(request)

		// Send response back
		Task {
			await self.sendResponse(response, requestId: requestId, to: peer)
		}
	}

	/// Send a response back to the peer
	private func sendResponse(_ response: Response, requestId: String, to peer: String) async {
		lock.lock()
		let sender = self.gossipSender
		lock.unlock()

		guard let sender = sender else { return }

		let message = IrohMessage.encodeResponse(response, requestId: requestId)

		do {
			try await sender.broadcast(msg: message)
		} catch {
			print("[Iroh] Failed to send response: \(error)")
		}
	}

	// MARK: - Helpers

	private static func hexToData(_ hex: String) -> Data {
		var data = Data(capacity: hex.count / 2)
		var index = hex.startIndex
		while index < hex.endIndex {
			let nextIndex = hex.index(index, offsetBy: 2)
			if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
				data.append(byte)
			}
			index = nextIndex
		}
		return data
	}
}

// MARK: - IrohRequestCallback

/// Callback handler for incoming gossip messages
private class IrohRequestCallback: GossipMessageCallback {
	weak var adapter: IrohTransportAdapter?

	init(adapter: IrohTransportAdapter) {
		self.adapter = adapter
	}

	func onMessage(msg: Message) async throws {
		switch msg.type() {
		case .neighborUp:
			let peer = msg.asNeighborUp()
			print("[Iroh] Peer connected: \(String(peer.prefix(16)))...")

		case .neighborDown:
			let peer = msg.asNeighborDown()
			print("[Iroh] Peer disconnected: \(String(peer.prefix(16)))...")

		case .received:
			let received = msg.asReceived()
			let data = Data(received.content)

			// Only handle request messages (not our own responses)
			if IrohMessage.isRequest(data) {
				adapter?.handleRequest(data, from: received.deliveredFrom)
			}

		case .lagged:
			print("[Iroh] Warning: message queue lagged")

		case .error:
			let err = msg.asError()
			print("[Iroh] Error: \(err)")
		}
	}
}

// MARK: - IrohMessage

/// Message encoding/decoding for Iroh transport
///
/// Message format:
/// - First byte: message type (0 = request, 1 = response)
/// - Remaining bytes: JSON payload
public enum IrohMessage {
	private static let requestType: UInt8 = 0
	private static let responseType: UInt8 = 1

	/// Check if data is a request message
	public static func isRequest(_ data: Data) -> Bool {
		guard let first = data.first else { return false }
		return first == requestType
	}

	/// Check if data is a response message
	public static func isResponse(_ data: Data) -> Bool {
		guard let first = data.first else { return false }
		return first == responseType
	}

	/// Parse a request from data
	/// Returns the Request and the request ID
	public static func parseRequest(from data: Data) -> (Request, String)? {
		guard data.count > 1, data.first == requestType else { return nil }

		let jsonData = data.dropFirst()

		guard let json = try? JSONSerialization.jsonObject(with: Data(jsonData)) as? [String: Any],
			  let path = json["path"] as? String,
			  let requestId = json["request_id"] as? String
		else {
			return nil
		}

		let queryParams = json["query"] as? [String: String] ?? [:]
		let metadata = json["metadata"] as? [String: String] ?? [:]

		// Decode body if present
		var body: Data? = nil
		if let bodyBase64 = json["body"] as? String {
			body = Data(base64Encoded: bodyBase64)
		}

		let request = Request(
			path: path,
			queryParams: queryParams,
			body: body,
			metadata: metadata
		)

		return (request, requestId)
	}

	/// Encode a request to data
	public static func encodeRequest(_ request: Request, requestId: String) -> Data {
		var json: [String: Any] = [
			"path": request.path,
			"request_id": requestId
		]

		if !request.queryParams.isEmpty {
			json["query"] = request.queryParams
		}

		if !request.metadata.isEmpty {
			json["metadata"] = request.metadata
		}

		if let body = request.body {
			json["body"] = body.base64EncodedString()
		}

		var data = Data([requestType])
		if let jsonData = try? JSONSerialization.data(withJSONObject: json) {
			data.append(jsonData)
		}

		return data
	}

	/// Encode a response to data
	public static func encodeResponse(_ response: Response, requestId: String) -> Data {
		let json: [String: Any] = [
			"request_id": requestId,
			"status": response.status.rawValue,
			"content_type": response.contentType.rawValue,
			"body": response.body.base64EncodedString()
		]

		var data = Data([responseType])
		if let jsonData = try? JSONSerialization.data(withJSONObject: json) {
			data.append(jsonData)
		}

		return data
	}

	/// Parse a response from data
	/// Returns the Response and the request ID
	public static func parseResponse(from data: Data) -> (Response, String)? {
		guard data.count > 1, data.first == responseType else { return nil }

		let jsonData = data.dropFirst()

		guard let json = try? JSONSerialization.jsonObject(with: Data(jsonData)) as? [String: Any],
			  let requestId = json["request_id"] as? String,
			  let statusCode = json["status"] as? Int,
			  let contentTypeStr = json["content_type"] as? String,
			  let bodyBase64 = json["body"] as? String,
			  let body = Data(base64Encoded: bodyBase64)
		else {
			return nil
		}

		let status = ResponseStatus(rawValue: statusCode) ?? .internalError
		let contentType = ContentType(rawValue: contentTypeStr) ?? .binary

		let response = Response(status: status, contentType: contentType, body: body)
		return (response, requestId)
	}
}
