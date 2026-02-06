# AppXplorerServer

A transport-agnostic debugging server that runs inside iOS apps, providing remote access to app internals for debugging and inspection.

## Features

- **Remote Debugging** — Connect to your iOS app from any device on the network
- **Transport Agnostic** — Works over HTTP, WebSocket, Iroh, Bluetooth, or custom transports
- **Built-in Endpoints** — App info, file browser, UserDefaults viewer, and more
- **Extensible** — Add custom endpoints with a simple API
- **Lightweight** — Minimal footprint, runs in the background

## Built-in Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /` | Server status and endpoint list |
| `GET /info` | App, device, and screen information |
| `GET /screenshot` | Capture current screen |
| `GET /hierarchy` | View hierarchy inspection |
| `GET /files?path=` | Browse the app's file system |
| `GET /userdefaults` | View UserDefaults contents |

## Installation

Add the package to your Xcode project:

1. File → Add Package Dependencies
2. Enter the repository URL
3. Add `AppXplorerServer` to your target

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(path: "../server")  // or remote URL
]
```

## Quick Start

```swift
import AppXplorerServer

// Create and start server with HTTP on port 8080
let server = AppXplorerServer.withHTTP(port: 8080)
try server.start()

// Server prints connection URL:
// 🚀 AppXplorerServer starting...
// 🌐 HTTP transport started on port 8080
// 📱 Device IP: 192.168.1.100
```

Then open `http://192.168.1.100:8080` in your browser.

## Custom Endpoints

```swift
// Add a custom endpoint
server["/api/custom"] = { request in
    let name = request.queryParams["name"] ?? "World"
    return .json(["message": "Hello, \(name)!"])
}

// Access at: http://device-ip:8080/api/custom?name=Kyle
```

## Multiple Transports

```swift
let server = AppXplorerServer()

// Add HTTP
server.addTransport(HTTPTransportAdapter(port: 8080))

// Add WebSocket (future)
// server.addTransport(WebSocketTransportAdapter(port: 8081))

// Add Iroh p2p (future)
// server.addTransport(IrohTransportAdapter())

try server.start()
```

All endpoints work identically across all transports.

## Response Types

```swift
// JSON
return .json(["key": "value"])
return .json(myEncodableObject)

// HTML
return .html("<h1>Hello</h1>")

// Plain text
return .text("Hello, World!")

// Images
return .png(imageData)
return .jpeg(imageData)

// Binary
return .binary(data)

// Errors
return .notFound("Resource not found")
return .error("Something went wrong", status: .internalError)
```

## Use Cases

- **Development** — Inspect app state without Xcode debugger
- **QA Testing** — View logs, UserDefaults, and file system on test devices
- **Remote Support** — Debug issues on user devices (with permission)
- **Automated Testing** — Query app state from test scripts

## Architecture

The server is designed to be transport-agnostic:

```
┌─────────────────────────────┐
│      RequestHandler         │
│   (routes & endpoints)      │
└──────────────┬──────────────┘
               │
    ┌──────────┴──────────┐
    │   TransportAdapter  │
    │     (protocol)      │
    └──────────┬──────────┘
               │
   ┌───────────┼───────────┐
   │           │           │
┌──┴──┐   ┌────┴───┐   ┌───┴───┐
│HTTP │   │WebSocket│   │ Iroh  │
└─────┘   └────────┘   └───────┘
```

See `docs/architecture.md` for details.

## Requirements

- iOS 15.0+ / macOS 12.0+
- Swift 6.0+

## License

[Your license here]
