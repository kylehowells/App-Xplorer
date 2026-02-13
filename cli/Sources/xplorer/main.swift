import Foundation
import XplorerLib

#if IROH_ENABLED
import IrohLib
#endif

// MARK: - Transport Protocol

/// Protocol for transport implementations (HTTP, Iroh, WebSocket, etc.)
protocol Transport {
	func request(path: String) async throws -> (Data, Int)
}

// MARK: - HTTP Transport

/// HTTP transport implementation
struct HTTPTransport: Transport {
	let baseURL: String

	init(host: String) {
		// Ensure http:// prefix
		if host.hasPrefix("http://") || host.hasPrefix("https://") {
			baseURL = host
		} else {
			baseURL = "http://\(host)"
		}
	}

	func request(path: String) async throws -> (Data, Int) {
		// Build URL
		var urlString: String = baseURL
		if !path.hasPrefix("/") {
			urlString += "/"
		}
		urlString += path

		guard let url = URL(string: urlString)
		else {
			throw CLIError.invalidURL(urlString)
		}

		// Make request
		let (data, response) = try await URLSession.shared.data(from: url)

		guard let httpResponse = response as? HTTPURLResponse
		else {
			throw CLIError.invalidResponse
		}

		return (data, httpResponse.statusCode)
	}
}

// MARK: - Iroh Transport

#if IROH_ENABLED

/// Iroh P2P transport implementation
class IrohTransport: Transport {
	/// The Iroh node
	private var node: Iroh?

	/// The gossip sender
	private var sender: Sender?

	/// Pending response continuations by request ID
	private var pendingRequests: [String: CheckedContinuation<(Data, Int), Error>] = [:]

	/// Lock for thread safety
	private let lock = NSLock()

	/// The peer's node ID
	let peerNodeId: String

	/// The peer's relay URL (optional, for faster connection)
	let peerRelayUrl: String?

	/// The RPC topic (must match server)
	private static let topicHex = "a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd"

	init(nodeId: String, relayUrl: String? = nil) {
		self.peerNodeId = nodeId
		self.peerRelayUrl = relayUrl
	}

	/// Connect to the peer
	func connect() async throws {
		// Create temporary node for CLI
		let tempDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("xplorer-cli-\(ProcessInfo.processInfo.processIdentifier)")
		try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

		fputs("Connecting via Iroh...\n", stderr)

		let node = try await Iroh.persistent(path: tempDir.path)
		self.node = node

		// Wait for network
		try await node.net().waitOnline()

		// Add peer info if relay URL is provided
		if let relayUrl = peerRelayUrl {
			let peerPubkey = try PublicKey.fromString(s: peerNodeId)
			let peerAddr = NodeAddr(nodeId: peerPubkey, derpUrl: relayUrl, addresses: [])
			try node.net().addNodeAddr(nodeAddr: peerAddr)
		}

		// Subscribe to the RPC topic with peer as bootstrap
		let topic = Self.hexToData(Self.topicHex)
		let callback = IrohResponseCallback(transport: self)

		let sender = try await node.gossip().subscribe(
			topic: topic,
			bootstrap: [peerNodeId],
			cb: callback
		)

		self.sender = sender

		// Wait for peer connection
		fputs("Waiting for peer connection...\n", stderr)
		try await waitForPeer(timeout: 30.0)

		fputs("Connected!\n", stderr)
	}

	/// Wait for peer to connect
	private func waitForPeer(timeout: TimeInterval) async throws {
		let start = Date()
		while Date().timeIntervalSince(start) < timeout {
			// Check if we have neighbors
			// For now, just wait a bit and assume connection
			try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
			// In a real implementation, we'd track neighborUp events
			return
		}
		throw CLIError.networkError("Timeout waiting for peer connection")
	}

	/// Disconnect
	func disconnect() async {
		if let sender = sender {
			try? await sender.cancel()
		}
		if let node = node {
			try? await node.node().shutdown()
		}
	}

	func request(path: String) async throws -> (Data, Int) {
		guard let sender = sender else {
			throw CLIError.networkError("Not connected")
		}

		// Generate unique request ID
		let requestId = UUID().uuidString

		// Build request message
		let requestData = IrohMessage.encodeRequest(path: path, requestId: requestId)

		// Set up continuation for response
		return try await withCheckedThrowingContinuation { continuation in
			lock.lock()
			pendingRequests[requestId] = continuation
			lock.unlock()

			// Send request
			Task {
				do {
					try await sender.broadcast(msg: requestData)
				} catch {
					self.lock.lock()
					if let cont = self.pendingRequests.removeValue(forKey: requestId) {
						self.lock.unlock()
						cont.resume(throwing: error)
					} else {
						self.lock.unlock()
					}
				}
			}

			// Set up timeout
			Task {
				try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
				self.lock.lock()
				if let cont = self.pendingRequests.removeValue(forKey: requestId) {
					self.lock.unlock()
					cont.resume(throwing: CLIError.networkError("Request timeout"))
				} else {
					self.lock.unlock()
				}
			}
		}
	}

	/// Handle incoming response
	func handleResponse(_ data: Data, requestId: String, statusCode: Int) {
		lock.lock()
		if let continuation = pendingRequests.removeValue(forKey: requestId) {
			lock.unlock()
			continuation.resume(returning: (data, statusCode))
		} else {
			lock.unlock()
		}
	}

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

// MARK: - Iroh Response Callback

private class IrohResponseCallback: GossipMessageCallback {
	weak var transport: IrohTransport?

	init(transport: IrohTransport) {
		self.transport = transport
	}

	func onMessage(msg: Message) async throws {
		switch msg.type() {
		case .neighborUp:
			let peer = msg.asNeighborUp()
			fputs("[Iroh] Peer connected: \(String(peer.prefix(16)))...\n", stderr)

		case .neighborDown:
			let peer = msg.asNeighborDown()
			fputs("[Iroh] Peer disconnected: \(String(peer.prefix(16)))...\n", stderr)

		case .received:
			let received = msg.asReceived()
			let data = Data(received.content)

			// Only handle response messages (not requests)
			if IrohMessage.isResponse(data) {
				if let (responseData, statusCode, requestId) = IrohMessage.parseResponse(from: data) {
					transport?.handleResponse(responseData, requestId: requestId, statusCode: statusCode)
				}
			}

		case .lagged:
			fputs("[Iroh] Warning: message queue lagged\n", stderr)

		case .error:
			let err = msg.asError()
			fputs("[Iroh] Error: \(err)\n", stderr)
		}
	}
}

// MARK: - Iroh Message

/// Message encoding/decoding for Iroh transport (CLI client side)
enum IrohMessage {
	private static let requestType: UInt8 = 0
	private static let responseType: UInt8 = 1

	/// Check if data is a response message
	static func isResponse(_ data: Data) -> Bool {
		guard let first = data.first else { return false }
		return first == responseType
	}

	/// Encode a request
	static func encodeRequest(path: String, requestId: String, queryParams: [String: String] = [:]) -> Data {
		var json: [String: Any] = [
			"path": path,
			"request_id": requestId
		]

		if !queryParams.isEmpty {
			json["query"] = queryParams
		}

		var data = Data([requestType])
		if let jsonData = try? JSONSerialization.data(withJSONObject: json) {
			data.append(jsonData)
		}

		return data
	}

	/// Parse a response
	/// Returns (body data, status code, request ID)
	static func parseResponse(from data: Data) -> (Data, Int, String)? {
		guard data.count > 1, data.first == responseType else { return nil }

		let jsonData = data.dropFirst()

		guard let json = try? JSONSerialization.jsonObject(with: Data(jsonData)) as? [String: Any],
			  let requestId = json["request_id"] as? String,
			  let statusCode = json["status"] as? Int,
			  let bodyBase64 = json["body"] as? String,
			  let body = Data(base64Encoded: bodyBase64)
		else {
			return nil
		}

		return (body, statusCode, requestId)
	}
}

#endif // IROH_ENABLED

// MARK: - CLI Error

enum CLIError: Error, CustomStringConvertible {
	case invalidURL(String)
	case invalidResponse
	case httpError(Int, String)
	case networkError(String)
	case invalidNodeId(String)

	var description: String {
		switch self {
		case let .invalidURL(url):
			return "Invalid URL: \(url)"
		case .invalidResponse:
			return "Invalid response from server"
		case let .httpError(code, message):
			return "HTTP \(code): \(message)"
		case let .networkError(message):
			return "Network error: \(message)"
		case let .invalidNodeId(id):
			return "Invalid Iroh node ID: \(id)"
		}
	}
}

// MARK: - Main

func printUsage() {
	#if IROH_ENABLED
	let usage = """
	xplorer - CLI for App-Xplorer debugging server

	Usage:
	  xplorer <target> [command] [options]

	Target:
	  HTTP:  host:port          e.g., 192.168.1.100:8080, localhost:8080
	  Iroh:  iroh:<node_id>     e.g., iroh:abc123...def456

	Arguments:
	  target    Server address (HTTP host:port or Iroh node ID)
	  command   API path with optional query string (e.g., info, files/list?path=/tmp)

	Options:
	  -o, --output <file>   Write response to specified file (any type: json, text, binary)
	                        If omitted, binary data auto-saves to /tmp with timestamp
	  --relay <url>         Iroh relay URL for faster P2P connection (optional)

	HTTP Examples:
	  xplorer 192.168.1.100:8080                     # Get API index
	  xplorer 192.168.1.100:8080 info                # Get app/device info
	  xplorer 192.168.1.100:8080 screenshot          # Save screenshot to /tmp
	  xplorer localhost:8080 hierarchy/views         # View hierarchy

	Iroh Examples:
	  xplorer iroh:abc123...def456 info              # Get info via P2P
	  xplorer iroh:abc123...def456 screenshot        # Screenshot via P2P
	  xplorer iroh:abc123... --relay https://relay.example.com info

	The command is appended to the base URL as a path. Include query parameters
	directly in the command string (e.g., files/list?path=/tmp&sort=name).

	Binary responses (like screenshots) are automatically detected and saved to files.
	Use -o to save any response type (JSON, text, or binary) to a file.
	"""
	#else
	let usage = """
	xplorer - CLI for App-Xplorer debugging server

	Usage:
	  xplorer <host> [command] [options]

	Arguments:
	  host      Server host and port (e.g., 192.168.1.100:8080 or localhost:8080)
	  command   API path with optional query string (e.g., info, files/list?path=/tmp)

	Options:
	  -o, --output <file>   Write response to specified file (any type: json, text, binary)
	                        If omitted, binary data auto-saves to /tmp with timestamp

	Examples:
	  xplorer 192.168.1.100:8080                     # Get API index
	  xplorer 192.168.1.100:8080 info                # Get app/device info
	  xplorer 192.168.1.100:8080 info -o info.json   # Save info to file
	  xplorer 192.168.1.100:8080 screenshot          # Save screenshot to /tmp
	  xplorer 192.168.1.100:8080 screenshot -o s.png # Save screenshot to s.png
	  xplorer 192.168.1.100:8080 hierarchy/views     # View hierarchy
	  xplorer 192.168.1.100:8080 files/list?path=/   # List files
	  xplorer localhost:8080 userdefaults            # View UserDefaults

	The command is appended to the base URL as a path. Include query parameters
	directly in the command string (e.g., files/list?path=/tmp&sort=name).

	Binary responses (like screenshots) are automatically detected and saved to files.
	Use -o to save any response type (JSON, text, or binary) to a file.
	"""
	#endif
	print(usage)
}

/// Parse command line arguments
struct ParsedArgs {
	var target: String = ""
	var command: String = "/"
	var outputFile: String? = nil
	var showHelp: Bool = false
	var relayUrl: String? = nil

	/// Whether target is an Iroh node ID
	var isIroh: Bool {
		return target.hasPrefix("iroh:")
	}

	/// Get the Iroh node ID (without prefix)
	var irohNodeId: String? {
		guard isIroh else { return nil }
		return String(target.dropFirst(5)) // Remove "iroh:" prefix
	}
}

func parseArguments(_ args: [String]) -> ParsedArgs {
	var result = ParsedArgs()
	var positionalArgs: [String] = []
	var i = 0

	while i < args.count {
		let arg: String = args[i]

		if arg == "-h" || arg == "--help" {
			result.showHelp = true
			i += 1
		} else if arg == "-o" || arg == "--output" {
			// Next argument is the output file
			if i + 1 < args.count {
				result.outputFile = args[i + 1]
				i += 2
			} else {
				fputs("Error: -o/--output requires a file path\n", stderr)
				exit(1)
			}
		} else if arg.hasPrefix("-o=") {
			result.outputFile = String(arg.dropFirst(3))
			i += 1
		} else if arg.hasPrefix("--output=") {
			result.outputFile = String(arg.dropFirst(9))
			i += 1
		} else if arg == "--relay" {
			if i + 1 < args.count {
				result.relayUrl = args[i + 1]
				i += 2
			} else {
				fputs("Error: --relay requires a URL\n", stderr)
				exit(1)
			}
		} else if arg.hasPrefix("--relay=") {
			result.relayUrl = String(arg.dropFirst(8))
			i += 1
		} else if arg.hasPrefix("-") {
			fputs("Error: Unknown option '\(arg)'\n", stderr)
			exit(1)
		} else {
			positionalArgs.append(arg)
			i += 1
		}
	}

	// Assign positional arguments
	if positionalArgs.count >= 1 {
		result.target = positionalArgs[0]
	}
	if positionalArgs.count >= 2 {
		result.command = positionalArgs[1]
	}

	return result
}

func main() async {
	let args: [String] = Array(CommandLine.arguments.dropFirst())
	let parsed: ParsedArgs = parseArguments(args)

	// Check for help
	if args.isEmpty || parsed.showHelp {
		printUsage()
		exit(args.isEmpty ? 1 : 0)
	}

	// Validate target
	if parsed.target.isEmpty {
		fputs("Error: target is required\n", stderr)
		printUsage()
		exit(1)
	}

	// Ensure command starts with /
	let path: String = parsed.command.hasPrefix("/") ? parsed.command : "/\(parsed.command)"

	// Create appropriate transport
	let transport: Transport

	#if IROH_ENABLED
	var irohTransport: IrohTransport? = nil

	if parsed.isIroh {
		guard let nodeId = parsed.irohNodeId, nodeId.count >= 32 else {
			fputs("Error: Invalid Iroh node ID\n", stderr)
			exit(1)
		}

		let iroh = IrohTransport(nodeId: nodeId, relayUrl: parsed.relayUrl)
		do {
			try await iroh.connect()
		} catch {
			fputs("Error connecting via Iroh: \(error)\n", stderr)
			exit(1)
		}
		transport = iroh
		irohTransport = iroh
	} else {
		transport = HTTPTransport(host: parsed.target)
	}

	defer {
		if let iroh = irohTransport {
			let semaphore = DispatchSemaphore(value: 0)
			Task {
				await iroh.disconnect()
				semaphore.signal()
			}
			semaphore.wait()
		}
	}
	#else
	// Iroh not enabled - only HTTP transport available
	if parsed.isIroh {
		fputs("Error: Iroh transport not available. Rebuild CLI with IROH_ENABLED.\n", stderr)
		exit(1)
	}
	transport = HTTPTransport(host: parsed.target)
	#endif

	do {
		// Make request
		let (data, statusCode) = try await transport.request(path: path)

		// Check status
		if statusCode >= 400 {
			let response: ResponseType = classifyResponse(data)
			switch response {
			case let .json(text), let .text(text):
				fputs("Error: HTTP \(statusCode)\n\(text)\n", stderr)
			case .binary:
				fputs("Error: HTTP \(statusCode)\n", stderr)
			}
			exit(1)
		}

		// Classify response and handle accordingly
		let response: ResponseType = classifyResponse(data)

		// If -o is specified, write any response type to file
		if let outputPath = parsed.outputFile {
			do {
				try data.write(to: URL(fileURLWithPath: outputPath))
				print("Saved \(data.count) bytes to: \(outputPath)")
			} catch {
				fputs("Error writing file: \(error.localizedDescription)\n", stderr)
				exit(1)
			}
		} else {
			// No -o specified: print text/json to stdout, auto-save binary to /tmp
			switch response {
			case let .json(text):
				print(text)

			case let .text(text):
				print(text)

			case let .binary(binaryData):
				// Auto-save binary to /tmp with timestamp
				let ext: String = detectFileExtension(from: binaryData)
				let outputPath: String = generateTimestampFilename(extension: ext)

				do {
					try binaryData.write(to: URL(fileURLWithPath: outputPath))
					print("Saved \(binaryData.count) bytes to: \(outputPath)")
				} catch {
					fputs("Error writing file: \(error.localizedDescription)\n", stderr)
					exit(1)
				}
			}
		}
	} catch let error as CLIError {
		fputs("Error: \(error.description)\n", stderr)
		exit(1)
	} catch let error as URLError {
		fputs("Error: \(error.localizedDescription)\n", stderr)
		if error.code == .cannotConnectToHost {
			fputs("Could not connect to \(parsed.target). Is the server running?\n", stderr)
		}
		exit(1)
	} catch {
		fputs("Error: \(error)\n", stderr)
		exit(1)
	}
}

/// Run async main
let semaphore = DispatchSemaphore(value: 0)
Task {
	await main()
	semaphore.signal()
}

semaphore.wait()
