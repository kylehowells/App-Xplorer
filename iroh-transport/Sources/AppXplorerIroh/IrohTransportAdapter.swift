import AppXplorerServer
import Foundation
import IrohLib
import Security

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
	private var node: Iroh? = nil

	/// The request handler
	public var requestHandler: RequestHandler? = nil

	/// Whether the adapter is running
	public private(set) var isRunning: Bool = false

	/// The node ID (share this with clients to connect)
	public var nodeId: String? {
		return self.node?.net().nodeId()
	}

	/// The relay URL (helps with NAT traversal)
	public var relayUrl: String? {
		return self.node?.net().nodeAddr().relayUrl()
	}

	/// ALPN protocol identifier for App-Xplorer RPC
	public static let alpn: Data = "app-xplorer/1".data(using: .utf8)!

	/// Storage path for the Iroh node
	private let storagePath: String

	/// Whether to force a new identity on next start
	private let forceNewIdentity: Bool

	/// Lock for thread safety
	private let lock = NSLock()

	/// Path to the stored secret key file
	private var keyFilePath: String {
		return self.storagePath + "/xplorer-identity.key"
	}

	/// Initialize with optional storage path and identity options
	/// - Parameters:
	///   - storagePath: Path for persistent storage (defaults to app's Library/Xplorer/iroh)
	///   - forceNewIdentity: When true, deletes existing key and storage before starting
	public init(storagePath: String? = nil, forceNewIdentity: Bool = false) {
		if let path = storagePath {
			self.storagePath = path
		}
		else {
			// Default to Library/Xplorer/iroh
			let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
			self.storagePath = libraryDir.appendingPathComponent("Xplorer/iroh").path
		}
		self.forceNewIdentity = forceNewIdentity
	}

	// MARK: - TransportAdapter

	public func start() throws {
		guard !self.isRunning else { return }

		// Create storage directory if needed
		try? FileManager.default.createDirectory(
			atPath: self.storagePath,
			withIntermediateDirectories: true,
			attributes: nil
		)

		print("🌐 Iroh transport starting...")
		print("📁 Storage: \(self.storagePath)")

		// Use semaphore to bridge async startup
		// Run on a detached task to avoid actor isolation issues
		let semaphore = DispatchSemaphore(value: 0)
		var startError: Error?

		Task.detached { [self] in
			do {
				try await self.startAsync()
			}
			catch {
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
		guard self.isRunning else { return }

		Task {
			await self.stopAsync()
		}
	}

	// MARK: - Key Management

	/// Export the node's secret key (32 bytes)
	public func exportSecretKey() -> Data? {
		let path = self.keyFilePath
		guard FileManager.default.fileExists(atPath: path) else { return nil }

		return FileManager.default.contents(atPath: path)
	}

	/// Import a secret key (32 bytes). Must be called before start().
	/// Clears existing Iroh storage to force re-initialization with the new key.
	public func importSecretKey(_ key: Data) throws {
		guard key.count == 32 else {
			throw IrohIdentityError.invalidKeyLength(key.count)
		}

		guard !self.isRunning else {
			throw IrohIdentityError.nodeAlreadyRunning
		}

		// Create storage directory if needed
		try FileManager.default.createDirectory(
			atPath: self.storagePath,
			withIntermediateDirectories: true,
			attributes: nil
		)

		// Save the new key
		try self.saveSecretKey(key)

		// Clear existing Iroh state so the node re-initializes with the new key
		try self.clearIrohStorage()
	}

	/// Delete stored identity and Iroh state. Next start() will generate a new identity.
	public func resetIdentity() throws {
		guard !self.isRunning else {
			throw IrohIdentityError.nodeAlreadyRunning
		}

		// Remove key file
		let path = self.keyFilePath
		if FileManager.default.fileExists(atPath: path) {
			try FileManager.default.removeItem(atPath: path)
		}

		// Clear Iroh storage
		try self.clearIrohStorage()
	}

	/// Load an existing secret key from disk, or generate and save a new one
	private func loadOrCreateSecretKey() throws -> Data {
		let path = self.keyFilePath

		// Try to load existing key
		if let existingKey = FileManager.default.contents(atPath: path), existingKey.count == 32 {
			print("[Iroh] Loaded existing identity from \(path)")
			return existingKey
		}

		// Generate new 32-byte Ed25519 secret key
		var key = Data(count: 32)
		let result = key.withUnsafeMutableBytes { ptr in
			SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
		}
		guard result == errSecSuccess else {
			throw IrohIdentityError.keyGenerationFailed
		}

		// Save to disk
		try self.saveSecretKey(key)
		print("[Iroh] Generated new identity, saved to \(path)")
		return key
	}

	/// Save a secret key to the key file
	private func saveSecretKey(_ key: Data) throws {
		let path = self.keyFilePath
		let url = URL(fileURLWithPath: path)
		try key.write(to: url, options: [.atomic, .completeFileProtection])
	}

	/// Clear Iroh's internal storage (but not the key file)
	private func clearIrohStorage() throws {
		let fm = FileManager.default
		guard let contents = try? fm.contentsOfDirectory(atPath: storagePath) else { return }

		let keyFileName = URL(fileURLWithPath: keyFilePath).lastPathComponent
		for item in contents where item != keyFileName {
			let itemPath = (self.storagePath as NSString).appendingPathComponent(item)
			try fm.removeItem(atPath: itemPath)
		}
	}

	// MARK: - Async Implementation

	/// Start the transport (async version)
	private func startAsync() async throws {
		// Handle forceNewIdentity
		if self.forceNewIdentity {
			try? self.resetIdentity()
		}

		// Load or create persistent secret key
		let secretKey = try loadOrCreateSecretKey()

		// Create protocol handler for accepting connections
		let protocolCreator = XplorerProtocolCreator(adapter: self)

		print("[Iroh] ALPN bytes: \(Array(Self.alpn))")
		print("[Iroh] Registering protocol with ALPN: \(String(data: Self.alpn, encoding: .utf8) ?? "unknown")")

		// Create node options with our custom protocol and persistent key
		let options = NodeOptions(
			gcIntervalMillis: nil,
			blobEvents: nil,
			enableDocs: false,
			ipv4Addr: nil,
			ipv6Addr: nil,
			nodeDiscovery: nil,
			secretKey: secretKey,
			protocols: [Self.alpn: protocolCreator]
		)

		print("[Iroh] Creating node with protocols: \(options.protocols?.keys.map { Array($0) } ?? [])")

		// Create persistent node with our protocol
		let node = try await Iroh.persistentWithOptions(path: self.storagePath, options: options)

		self.lock.lock()
		self.node = node
		self.lock.unlock()

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

		self.lock.lock()
		self.isRunning = true
		self.lock.unlock()

		print("✅ Iroh transport ready (QUIC streams)")
		print("📱 Share this node ID with clients: \(nodeId)")
	}

	/// Stop the transport (async version)
	private func stopAsync() async {
		self.lock.lock()
		let node = self.node
		self.node = nil
		self.isRunning = false
		self.lock.unlock()

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
		}
		catch {
			print("[Iroh] Connection closed: \(error)")
		}
	}

	/// Handle a single request/response stream
	private func handleStream(_ stream: BiStream, from peer: String) async {
		do {
			// Read request (length-prefixed: 4 bytes big-endian length + data)
			let lengthBytes = try await stream.recv().readExact(size: 4)
			let length = UInt32(bigEndian: lengthBytes.withUnsafeBytes { $0.load(as: UInt32.self) })

			guard length > 0, length < 100_000_000 else { // Max 100MB
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
		}
		catch {
			print("[Iroh] Stream error: \(error)")
		}
	}
}

// MARK: - XplorerProtocolCreator

/// Creates protocol handlers for incoming connections
private class XplorerProtocolCreator: ProtocolCreator {
	weak var adapter: IrohTransportAdapter? = nil

	init(adapter: IrohTransportAdapter) {
		self.adapter = adapter
	}

	func create(endpoint _: Endpoint) -> ProtocolHandler {
		print("[Iroh] ProtocolCreator.create called!")
		return XplorerProtocolHandler(adapter: self.adapter)
	}
}

// MARK: - XplorerProtocolHandler

/// Handles incoming connections for the App-Xplorer protocol
private class XplorerProtocolHandler: ProtocolHandler {
	weak var adapter: IrohTransportAdapter? = nil

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
			"path": request.path,
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
			"body": response.body.base64EncodedString(),
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

// MARK: - IrohIdentityError

/// Errors related to identity key management
public enum IrohIdentityError: Error, LocalizedError {
	case invalidKeyLength(Int)
	case nodeAlreadyRunning
	case keyGenerationFailed

	public var errorDescription: String? {
		switch self {
			case let .invalidKeyLength(length):
				return "Secret key must be exactly 32 bytes, got \(length)"

			case .nodeAlreadyRunning:
				return "Cannot modify identity while the node is running"

			case .keyGenerationFailed:
				return "Failed to generate cryptographic random key"
		}
	}
}
