# AppXplorerServer

A transport-agnostic debugging server that runs inside iOS apps, providing remote access to app internals for debugging and inspection.

## Features

- **Remote Debugging** — Connect to your iOS app from any device on the network
- **Transport Agnostic** — Works over HTTP, WebSocket, Iroh, Bluetooth, or custom transports
- **Self-Documenting API** — Every endpoint describes itself with parameters, defaults, and examples
- **Built-in Endpoints** — App info, file browser, UserDefaults viewer, and more
- **Extensible** — Add custom endpoints with a simple API
- **Lightweight** — Minimal footprint, runs in the background

## API Discovery

The API is self-documenting. Visit the root endpoint (`/`) to see all available endpoints with their descriptions and parameters:

```bash
curl http://device-ip:8080/
```

Returns a JSON tree of all endpoints, their descriptions, parameters (with defaults and examples), and sub-routers.

Use `?depth=shallow` to get a summary view showing only sub-router counts instead of full endpoint details.

## Built-in Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /` | API index with full endpoint documentation |
| `GET /info` | App, device, and screen information |
| `GET /screenshot` | Capture current screen as PNG |
| `GET /hierarchy` | View hierarchy inspection |
| `GET /userdefaults` | View UserDefaults contents |
| `GET /files/` | File system browser (sub-router with its own index) |
| `GET /files/list` | List directory contents |
| `GET /files/read` | Read file contents |
| `GET /files/metadata` | Get file/directory metadata |
| `GET /files/head` | Read first N lines of a text file |
| `GET /files/tail` | Read last N lines of a text file |

Each endpoint documents its own parameters. For example, `/files/list` accepts `path`, `sort`, `order`, `limit`, and `offset` parameters—all described in the API response.

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

Then query the API at `http://192.168.1.100:8080/`.

## Custom Endpoints

Host apps can register custom endpoints using the same API that built-in endpoints use. Custom endpoints integrate seamlessly with API discovery.

### Simple Registration

```swift
// Quick endpoint using subscript syntax
server["/api/custom"] = { request in
    let name = request.queryParams["name"] ?? "World"
    return .json(["message": "Hello, \(name)!"])
}

// Access at: http://device-ip:8080/api/custom?name=Kyle
```

### Full Registration with Metadata

Register endpoints with descriptions and parameters that appear in API discovery:

```swift
server.register(
    "/api/user",
    description: "Get current user information",
    parameters: [
        ParameterInfo(
            name: "include_avatar",
            description: "Include base64-encoded avatar image",
            required: false,
            defaultValue: "false"
        ),
        ParameterInfo(
            name: "fields",
            description: "Comma-separated list of fields to include",
            required: false,
            examples: ["name,email", "name,email,created_at"]
        )
    ]
) { request in
    let includeAvatar = request.queryParams["include_avatar"] == "true"
    var user: [String: Any] = [
        "id": 123,
        "name": "John Doe",
        "email": "john@example.com"
    ]
    if includeAvatar {
        user["avatar"] = "data:image/png;base64,..."
    }
    return .json(user)
}
```

### Custom Sub-Routers

For modular organization, create a `RequestHandler` and mount it at a path prefix:

```swift
// Create a router for account-related endpoints
let accountRouter = RequestHandler(description: "User account management")

accountRouter.register("/profile", description: "Get user profile") { request in
    return .json([
        "name": "John Doe",
        "email": "john@example.com",
        "plan": "premium"
    ])
}

accountRouter.register("/settings", description: "Get user settings") { request in
    return .json([
        "theme": "dark",
        "notifications": true,
        "language": "en"
    ])
}

accountRouter.register(
    "/update",
    description: "Update user settings",
    parameters: [
        ParameterInfo(name: "theme", description: "UI theme", examples: ["light", "dark"]),
        ParameterInfo(name: "notifications", description: "Enable notifications", examples: ["true", "false"])
    ]
) { request in
    // Handle update...
    return .json(["success": true])
}

// Mount at /account - endpoints become /account/profile, /account/settings, /account/update
server.mount("/account", router: accountRouter)
```

The mounted router will appear in API discovery with its description and endpoint count.

### Background Thread Handlers

By default, handlers run on the main thread for UIKit access. For file I/O or other non-UI work, set `runsOnMainThread: false`:

```swift
server.register(
    "/api/export",
    description: "Export data to file",
    runsOnMainThread: false  // Runs on background thread
) { request in
    // Safe to do file I/O here without blocking main thread
    let data = generateExportData()
    try? data.write(to: exportURL)
    return .json(["exported": true, "path": exportURL.path])
}
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

MIT License - see [LICENSE](../LICENSE) for details.
