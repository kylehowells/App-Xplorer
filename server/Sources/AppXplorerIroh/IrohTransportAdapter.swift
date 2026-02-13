import Foundation
import AppXplorerServer
import IrohLib

// MARK: - IrohTransportAdapter

/// Iroh transport adapter for P2P connections using QUIC streams
///
/// This adapter allows App-Xplorer to accept connections over the Iroh P2P network,
/// enabling debugging across different networks without requiring direct IP connectivity.
/// Uses direct QUIC streams instead of gossip for unlimited message sizes.
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

	/// ALPN protocol identifier for App-Xplorer RPC
	public static let alpn: Data = "app-xplorer/1".data(using: .utf8)!

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
		// Run on a detached task to avoid actor isolation issues
		let semaphore = DispatchSemaphore(value: 0)
		var startError: Error?

		Task.detached { [self] in
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
		// Create protocol handler for accepting connections
		let protocolCreator = XplorerProtocolCreator(adapter: self)

		print("[Iroh] ALPN bytes: \(Array(Self.alpn))")
		print("[Iroh] Registering protocol with ALPN: \(String(data: Self.alpn, encoding: .utf8) ?? "unknown")")

		// Create node options with our custom protocol
		let options = NodeOptions(
			gcIntervalMillis: nil,
			blobEvents: nil,
			enableDocs: false,
			ipv4Addr: nil,
			ipv6Addr: nil,
			nodeDiscovery: nil,
			secretKey: nil,
			protocols: [Self.alpn: protocolCreator]
		)

		print("[Iroh] Creating node with protocols: \(options.protocols?.keys.map { Array($0) } ?? [])")

		// Create persistent node with our protocol
		let node = try await Iroh.persistentWithOptions(path: storagePath, options: options)

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
		print("📍 Getting direct addresses...")
		let directAddrs = nodeAddr.directAddresses()
		print("📍 Direct addresses count: \(directAddrs.count)")
		for addr in directAddrs {
			print("  - \(addr)")
		}
		print("📍 Done with addresses")

		lock.lock()
		self.isRunning = true
		lock.unlock()

		print("✅ Iroh transport ready (QUIC streams)")
		print("📱 Share this node ID with clients: \(nodeId)")
	}

	/// Stop the transport (async version)
	private func stopAsync() async {
		lock.lock()
		let node = self.node
		self.node = nil
		self.isRunning = false
		lock.unlock()

		if let node = node {
			try? await node.node().shutdown()
		}

		print("🛑 Iroh transport stopped")
	}

	// MARK: - Connection Handling

	/// Handle an incoming connection
	func handleConnection(_ conn: Connection) async {
		print("[Iroh] New connection from: \(conn.remoteNodeId().prefix(16))...")

		// Accept bidirectional streams from this connection
		do {
			while true {
				let biStream = try await conn.acceptBi()

				// Handle each stream in its own task
				Task {
					await self.handleStream(biStream, from: conn.remoteNodeId())
				}
			}
		} catch {
			print("[Iroh] Connection closed: \(error)")
		}
	}

	/// Handle a single request/response stream
	private func handleStream(_ stream: BiStream, from peer: String) async {
		do {
			// Read request (length-prefixed: 4 bytes big-endian length + data)
			let lengthBytes = try await stream.recv().readExact(size: 4)
			let length = UInt32(bigEndian: lengthBytes.withUnsafeBytes { $0.load(as: UInt32.self) })

			guard length > 0 && length < 100_000_000 else { // Max 100MB
				print("[Iroh] Invalid request length: \(length)")
				return
			}

			let requestData = try await stream.recv().readExact(size: UInt32(length))

			// Parse and handle request
			guard let handler = requestHandler else {
				print("[Iroh] No request handler configured")
				return
			}

			guard let request = IrohMessage.parseRequest(from: Data(requestData)) else {
				print("[Iroh] Failed to parse request")
				return
			}

			print("[Iroh] Request from \(peer.prefix(8))...: \(request.path)")

			// Handle the request
			let response = handler.handle(request)

			// Encode response
			let responseData = IrohMessage.encodeResponse(response)

			// Send response (length-prefixed)
			var lengthData = Data(count: 4)
			let responseLength = UInt32(responseData.count).bigEndian
			lengthData.withUnsafeMutableBytes { $0.storeBytes(of: responseLength, as: UInt32.self) }

			try await stream.send().writeAll(buf: lengthData)
			try await stream.send().writeAll(buf: responseData)
			try await stream.send().finish()

			print("[Iroh] Response sent: \(responseData.count) bytes")

		} catch {
			print("[Iroh] Stream error: \(error)")
		}
	}
}

// MARK: - XplorerProtocolCreator

/// Creates protocol handlers for incoming connections
private class XplorerProtocolCreator: ProtocolCreator {
	weak var adapter: IrohTransportAdapter?

	init(adapter: IrohTransportAdapter) {
		self.adapter = adapter
	}

	func create(endpoint: Endpoint) -> ProtocolHandler {
		print("[Iroh] ProtocolCreator.create called!")
		return XplorerProtocolHandler(adapter: adapter)
	}
}

// MARK: - XplorerProtocolHandler

/// Handles incoming connections for the App-Xplorer protocol
private class XplorerProtocolHandler: ProtocolHandler {
	weak var adapter: IrohTransportAdapter?

	init(adapter: IrohTransportAdapter?) {
		self.adapter = adapter
		print("[Iroh] ProtocolHandler created")
	}

	func accept(conn: Connection) async throws {
		print("[Iroh] ProtocolHandler.accept called!")
		guard let adapter = adapter else {
			print("[Iroh] ERROR: adapter is nil in accept")
			return
		}
		await adapter.handleConnection(conn)
	}

	func shutdown() async {
		print("[Iroh] ProtocolHandler.shutdown called")
	}
}

// MARK: - IrohMessage

/// Message encoding/decoding for Iroh transport (QUIC stream version)
///
/// Simplified format for streams (no message type byte needed):
/// Request: JSON with path, query, metadata, body
/// Response: JSON with status, content_type, body
public enum IrohMessage {

	/// Parse a request from data
	public static func parseRequest(from data: Data) -> Request? {
		guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let path = json["path"] as? String
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

		return Request(
			path: path,
			queryParams: queryParams,
			body: body,
			metadata: metadata
		)
	}

	/// Encode a request to data
	public static func encodeRequest(_ request: Request) -> Data {
		var json: [String: Any] = [
			"path": request.path
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

		return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
	}

	/// Encode a response to data
	public static func encodeResponse(_ response: Response) -> Data {
		let json: [String: Any] = [
			"status": response.status.rawValue,
			"content_type": response.contentType.rawValue,
			"body": response.body.base64EncodedString()
		]

		return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
	}

	/// Parse a response from data
	public static func parseResponse(from data: Data) -> Response? {
		guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let statusCode = json["status"] as? Int,
			  let contentTypeStr = json["content_type"] as? String,
			  let bodyBase64 = json["body"] as? String,
			  let body = Data(base64Encoded: bodyBase64)
		else {
			return nil
		}

		let status = ResponseStatus(rawValue: statusCode) ?? .internalError
		let contentType = ContentType(rawValue: contentTypeStr) ?? .binary

		return Response(status: status, contentType: contentType, body: body)
	}
}
