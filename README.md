# App-Xplorer

A debugging toolkit for iOS apps that provides remote access to app internals via a self-documenting API.

## Components

| Component | Description |
|-----------|-------------|
| **[server/](server/)** | Swift package that runs inside iOS apps, exposing a debugging API |
| **[cli/](cli/)** | Command-line tool for interacting with the server |
| **[demo/](demo/)** | Sample iOS app for testing and demonstration |
| **[client/](client/)** | iOS/macOS client app (WIP) |

## Features

- **Remote Debugging** - Connect to your iOS app from any device on the network
- **Self-Documenting API** - Every endpoint describes itself with parameters, defaults, and examples
- **View Hierarchy Inspection** - Explore the complete UIKit view tree (JSON or XML format)
- **UI Interaction** - Tap buttons, type text, scroll views, and more via API
- **File System Access** - Browse, read, and write files in the app sandbox
- **UserDefaults Viewer** - Inspect and modify UserDefaults
- **Permission Inspector** - Check status of all system permissions
- **Log Ingestion** - Pipe your app's logs for remote viewing
- **Screenshots** - Capture the current screen state
- **Transport Agnostic** - HTTP now, WebSocket/Iroh/Bluetooth planned

## Quick Start

### 1. Add the Server to Your App

Add the Swift package to your iOS project:

```swift
dependencies: [
    .package(url: "https://github.com/kylehowells/App-Xplorer.git", from: "1.0.0")
]
```

Then start the server in your app:

```swift
import AppXplorerServer

let server = AppXplorerServer.withHTTP(port: 8080)
try server.start()
```

### 2. Query the API

Use the CLI or curl to interact with your app:

```bash
# Build the CLI
cd cli && swift build -c release

# Get API index (lists all endpoints)
.build/release/xplorer localhost:8080

# Capture screenshot
.build/release/xplorer localhost:8080 screenshot -o screen.png

# View hierarchy as XML
.build/release/xplorer localhost:8080 "hierarchy/views?format=xml"

# Tap a button
.build/release/xplorer localhost:8080 "interact/tap?address=0x12345678"
```

## API Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /` | API index with full documentation |
| `GET /info` | App and device information |
| `GET /screenshot` | Capture screen as PNG |
| `/hierarchy/*` | View hierarchy, windows, view controllers, responder chain |
| `/interact/*` | Tap, type, scroll, swipe, focus/resign |
| `/files/*` | File system browser |
| `/userdefaults/*` | UserDefaults read/write |
| `/permissions/*` | System permission states |
| `/logs/*` | Log ingestion and retrieval |

Visit `GET /` for complete API documentation with parameters and examples.

## Log Ingestion

Apps can pipe their logs to App-Xplorer for remote viewing:

```swift
// In your app
AppXplorerServer.log.log("User logged in", type: "auth")
AppXplorerServer.log.log("API request failed", type: "network")

// Then query via API
// GET /logs/?type=network&match=%25error%25&limit=50
```

## Custom Endpoints

Register your own endpoints that integrate with API discovery:

```swift
server.register(
    "/api/user",
    description: "Get current user info",
    parameters: [
        ParameterInfo(name: "fields", description: "Fields to include", examples: ["name,email"])
    ]
) { request in
    return .json(["name": "John", "email": "john@example.com"])
}
```

## Requirements

- iOS 15.0+ / macOS 12.0+
- Swift 6.0+

## License

MIT License - see [LICENSE](LICENSE) for details.
