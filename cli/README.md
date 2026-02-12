# xplorer CLI

A command-line interface for interacting with the App-Xplorer debugging server.

## Installation

```bash
cd cli
swift build -c release
# Binary will be at .build/release/xplorer
```

Or install to `/usr/local/bin`:

```bash
swift build -c release
cp .build/release/xplorer /usr/local/bin/
```

## Usage

```bash
xplorer <host> [command]
```

### Arguments

- `host` - Server host and port (e.g., `192.168.1.100:8080` or `localhost:8080`)
- `command` - API path with optional query string (default: `/` for API index)

### Examples

```bash
# Get API index (list all endpoints)
xplorer 192.168.1.100:8080

# Get app and device info
xplorer 192.168.1.100:8080 info

# Capture screenshot (returns binary PNG data)
xplorer 192.168.1.100:8080 screenshot

# View hierarchy
xplorer 192.168.1.100:8080 hierarchy/views
xplorer 192.168.1.100:8080 hierarchy/windows
xplorer 192.168.1.100:8080 hierarchy/view-controllers

# List files in a directory
xplorer 192.168.1.100:8080 files/list?path=/tmp

# Read file contents
xplorer 192.168.1.100:8080 files/read?path=/tmp/test.txt

# View UserDefaults
xplorer 192.168.1.100:8080 userdefaults
```

## Output

The CLI automatically pretty-prints JSON responses. For binary responses (like screenshots), raw data is output.

## Architecture

The CLI is designed to be transport-agnostic. Currently it uses HTTP, but the `Transport` protocol allows for future implementations:

- **HTTP** (current) - Standard REST API calls
- **Iroh** (planned) - Peer-to-peer networking for direct device connections without network infrastructure
- **WebSocket** (planned) - Real-time bidirectional communication
- **Bluetooth** (planned) - Local debugging without network

## Future Plans

We're exploring [Iroh](https://iroh.computer/) for peer-to-peer connectivity. This would allow:
- Direct device-to-device connections without a shared network
- NAT traversal for debugging across networks
- Relay servers for when direct connections aren't possible

The CLI will support selecting transport via a flag:

```bash
# Future syntax
xplorer --transport iroh <node-id> info
xplorer --transport ws 192.168.1.100:8081 info
```
