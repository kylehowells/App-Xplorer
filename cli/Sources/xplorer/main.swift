import Foundation
import XplorerLib

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

// MARK: - CLI Error

enum CLIError: Error, CustomStringConvertible {
    case invalidURL(String)
    case invalidResponse
    case httpError(Int, String)
    case networkError(String)

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
        }
    }
}

// MARK: - Main

func printUsage() {
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
    print(usage)
}

/// Parse command line arguments
struct ParsedArgs {
    var host: String = ""
    var command: String = "/"
    var outputFile: String? = nil
    var showHelp: Bool = false
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
        result.host = positionalArgs[0]
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

    // Validate host
    if parsed.host.isEmpty {
        fputs("Error: host is required\n", stderr)
        printUsage()
        exit(1)
    }

    // Ensure command starts with /
    let path: String = parsed.command.hasPrefix("/") ? parsed.command : "/\(parsed.command)"

    // Create transport
    let transport: Transport = HTTPTransport(host: parsed.host)

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
            fputs("Could not connect to \(parsed.host). Is the server running?\n", stderr)
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
