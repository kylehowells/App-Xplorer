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

/// Iroh P2P transport implementation using QUIC streams
class IrohTransport: Transport {
	/// The Iroh node
	private var node: Iroh?

	/// The connection to the server
	private var connection: Connection?

	/// The peer's node ID
	let peerNodeId: String

	/// The peer's relay URL (optional, for faster connection)
	let peerRelayUrl: String?

	/// The peer's direct addresses (optional, for faster connection)
	let peerDirectAddresses: [String]

	/// ALPN protocol identifier (must match server)
	private static let alpn: Data = "app-xplorer/1".data(using: .utf8)!

	init(nodeId: String, relayUrl: String? = nil, directAddresses: [String] = []) {
		self.peerNodeId = nodeId
		self.peerRelayUrl = relayUrl
		self.peerDirectAddresses = directAddresses
	}

	/// Connect to the peer
	func connect() async throws {
		// Create temporary node for CLI
		let tempDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("xplorer-cli-\(ProcessInfo.processInfo.processIdentifier)")
		try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

		fputs("Connecting via Iroh...\n", stderr)
		fputs("Creating node at \(tempDir.path)...\n", stderr)

		let node = try await Iroh.persistent(path: tempDir.path)
		self.node = node

		// Wait for network
		fputs("Waiting for network...\n", stderr)
		try await node.net().waitOnline()

		let myId = node.net().nodeId()
		fputs("Local node ID: \(myId.prefix(16))...\n", stderr)

		// Build peer address
		let peerPubkey = try PublicKey.fromString(s: peerNodeId)
		let peerAddr = NodeAddr(nodeId: peerPubkey, derpUrl: peerRelayUrl, addresses: peerDirectAddresses)

		fputs("Peer relay URL: \(peerRelayUrl ?? "none")\n", stderr)
		fputs("Peer direct addresses: \(peerDirectAddresses)\n", stderr)

		// Add peer to discovery
		try node.net().addNodeAddr(nodeAddr: peerAddr)
		fputs("Added peer to discovery\n", stderr)

		// Get endpoint and connect
		let endpoint = node.node().endpoint()
		fputs("Connecting to peer \(peerNodeId.prefix(16))...\n", stderr)
		fputs("ALPN: \(Array(Self.alpn))\n", stderr)

		let conn = try await endpoint.connect(nodeAddr: peerAddr, alpn: Self.alpn)
		self.connection = conn

		fputs("Connected!\n", stderr)
	}

	/// Disconnect
	func disconnect() async {
		if let conn = connection {
			try? conn.close(errorCode: 0, reason: Data())
		}
		if let node = node {
			try? await node.node().shutdown()
		}
	}

	func request(path: String) async throws -> (Data, Int) {
		guard let conn = connection else {
			throw CLIError.networkError("Not connected")
		}

		// Parse path and query params
		let (cleanPath, queryParams) = Self.parsePathAndQuery(path)

		// Build request
		let requestData = IrohMessage.encodeRequest(path: cleanPath, queryParams: queryParams)

		// Open bidirectional stream
		let stream = try await conn.openBi()

		// Send request (length-prefixed: 4 bytes big-endian length + data)
		var lengthData = Data(count: 4)
		let requestLength = UInt32(requestData.count).bigEndian
		lengthData.withUnsafeMutableBytes { $0.storeBytes(of: requestLength, as: UInt32.self) }

		try await stream.send().writeAll(buf: lengthData)
		try await stream.send().writeAll(buf: requestData)
		try await stream.send().finish()

		// Read response (length-prefixed)
		let responseLengthBytes = try await stream.recv().readExact(size: 4)
		let responseLength = UInt32(bigEndian: Data(responseLengthBytes).withUnsafeBytes { $0.load(as: UInt32.self) })

		guard responseLength > 0 && responseLength < 100_000_000 else { // Max 100MB
			throw CLIError.networkError("Invalid response length: \(responseLength)")
		}

		let responseBytes = try await stream.recv().readExact(size: UInt32(responseLength))
		let responseData = Data(responseBytes)

		// Parse response
		guard let response = IrohMessage.parseResponse(from: responseData) else {
			throw CLIError.networkError("Failed to parse response")
		}

		return (response.body, response.statusCode)
	}

	/// Parse path and query parameters from a URL-like path string
	/// e.g. "/userdefaults/get?key=demo.userName" -> ("/userdefaults/get", ["key": "demo.userName"])
	private static func parsePathAndQuery(_ pathWithQuery: String) -> (String, [String: String]) {
		guard let questionMarkIndex = pathWithQuery.firstIndex(of: "?") else {
			return (pathWithQuery, [:])
		}

		let path = String(pathWithQuery[..<questionMarkIndex])
		let queryString = String(pathWithQuery[pathWithQuery.index(after: questionMarkIndex)...])

		var queryParams: [String: String] = [:]
		let pairs = queryString.split(separator: "&")
		for pair in pairs {
			let parts = pair.split(separator: "=", maxSplits: 1)
			if parts.count == 2 {
				let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
				let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
				queryParams[key] = value
			} else if parts.count == 1 {
				let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
				queryParams[key] = ""
			}
		}

		return (path, queryParams)
	}
}

// MARK: - Iroh Message

/// Message encoding/decoding for Iroh transport (QUIC stream version)
enum IrohMessage {
	struct ParsedResponse {
		let body: Data
		let statusCode: Int
		let contentType: String
	}

	/// Encode a request to JSON
	static func encodeRequest(path: String, queryParams: [String: String] = [:]) -> Data {
		var json: [String: Any] = [
			"path": path
		]

		if !queryParams.isEmpty {
			json["query"] = queryParams
		}

		return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
	}

	/// Parse a response from JSON
	static func parseResponse(from data: Data) -> ParsedResponse? {
		guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let statusCode = json["status"] as? Int,
			  let contentTypeStr = json["content_type"] as? String,
			  let bodyBase64 = json["body"] as? String,
			  let body = Data(base64Encoded: bodyBase64)
		else {
			return nil
		}

		return ParsedResponse(body: body, statusCode: statusCode, contentType: contentTypeStr)
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
	var directAddresses: [String] = []

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
		} else if arg == "--addr" {
			if i + 1 < args.count {
				result.directAddresses.append(args[i + 1])
				i += 2
			} else {
				fputs("Error: --addr requires a socket address\n", stderr)
				exit(1)
			}
		} else if arg.hasPrefix("--addr=") {
			result.directAddresses.append(String(arg.dropFirst(7)))
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

		let iroh = IrohTransport(nodeId: nodeId, relayUrl: parsed.relayUrl, directAddresses: parsed.directAddresses)
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
