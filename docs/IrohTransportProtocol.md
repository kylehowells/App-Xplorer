# Iroh P2P Transport Protocol

This document describes how App-Xplorer uses the Iroh P2P networking library to enable remote debugging across different networks without requiring direct IP connectivity.

## Overview

App-Xplorer's Iroh transport allows CLI tools to connect to iOS/macOS apps using just a node ID, even when the devices are on different networks or behind NAT. The transport uses Iroh's QUIC-based networking with a custom application protocol.

## Architecture

```
┌─────────────────┐                              ┌─────────────────┐
│   CLI Client    │                              │  iOS/macOS App  │
│                 │                              │                 │
│  ┌───────────┐  │         QUIC Stream          │  ┌───────────┐  │
│  │  Iroh     │◄─┼──────────────────────────────┼─►│  Iroh     │  │
│  │  Endpoint │  │    (via relay or direct)     │  │  Router   │  │
│  └───────────┘  │                              │  └───────────┘  │
│                 │                              │        │        │
│  IrohTransport  │                              │  IrohTransport  │
│                 │                              │     Adapter     │
└─────────────────┘                              └─────────────────┘
```

## What We Use from Iroh

### 1. Endpoint & Networking Layer

We use Iroh's full networking stack:

- **QUIC transport** - Reliable, multiplexed, encrypted connections
- **NAT traversal** - Automatic hole punching for direct connections
- **Relay fallback** - Uses n0's relay servers when direct connection fails
- **Node discovery** - DNS-based discovery via `iroh.link` domain

### 2. Identity & Cryptography

- **Ed25519 key pairs** - Each node has a unique cryptographic identity
- **Node ID** - 64-character hex string (public key) used to identify and connect to nodes
- **TLS 1.3** - All connections are encrypted using the node's keys

### 3. Router & Protocol Handler

We use Iroh's `Router` for protocol multiplexing:

```swift
// Server registers custom protocol
let options = NodeOptions(
    protocols: [alpn: XplorerProtocolCreator()]
)
let node = try await Iroh.persistentWithOptions(path: path, options: options)
```

The Router:
- Accepts incoming connections on the endpoint
- Dispatches connections to the appropriate `ProtocolHandler` based on ALPN
- Manages connection lifecycle

## What We Replace / Customize

### 1. Custom ALPN Protocol (instead of Gossip/Blobs)

Iroh provides built-in protocols:
- `iroh-gossip` - Pub/sub messaging (4KB message limit)
- `iroh-blobs` - Content-addressed blob storage

We **don't use these** because:
- Gossip has a 4KB message size limit (screenshots can be 4MB+)
- Blobs is designed for content-addressed storage, not RPC

Instead, we define a custom ALPN protocol:

```
ALPN: "app-xplorer/1"
```

### 2. Custom Request/Response Protocol

Our protocol uses length-prefixed JSON messages over bidirectional QUIC streams:

```
┌────────────────────────────────────────────────────────┐
│                    Message Format                       │
├────────────┬───────────────────────────────────────────┤
│  4 bytes   │              N bytes                       │
│  (length)  │              (JSON payload)                │
│  big-endian│                                            │
└────────────┴───────────────────────────────────────────┘
```

#### Request Format

```json
{
  "path": "/info",
  "query": {
    "key": "value"
  },
  "metadata": {},
  "body": "<base64-encoded-data>"
}
```

#### Response Format

```json
{
  "status": 200,
  "content_type": "application/json",
  "body": "<base64-encoded-response-data>"
}
```

### 3. Stream-per-Request Model

Unlike HTTP/2 which multiplexes on a single connection, we use:

- **One bidirectional QUIC stream per request**
- Client opens stream, sends request, reads response, stream closes
- Connection persists for multiple requests

```swift
// Client side
let stream = try await conn.openBi()
try await stream.send().writeAll(buf: lengthPrefix + requestData)
try await stream.send().finish()
let response = try await stream.recv().readExact(size: responseLength)

// Server side
let stream = try await conn.acceptBi()
let request = try await stream.recv().readExact(size: requestLength)
// ... process request ...
try await stream.send().writeAll(buf: lengthPrefix + responseData)
try await stream.send().finish()
```

## Connection Flow

### Server Startup

1. Create Iroh node with persistent storage
2. Register custom protocol handler for `app-xplorer/1` ALPN
3. Wait for network (relay connection established)
4. Node ID is published to n0 DNS via PkarrPublisher
5. Print node ID for users to share

```
🔑 Iroh Node ID: 500e2241ff9c7abef458954db706d8d10525a0a1df043caeef7afc8bf13bd723
🌐 Relay URL: https://euc1-1.relay.n0.iroh-canary.iroh.link./
```

### Client Connection

1. Create ephemeral Iroh node (temporary storage)
2. Wait for network
3. Add peer's node address to discovery (node ID + optional relay URL)
4. Connect to peer using ALPN `app-xplorer/1`
5. Connection established via:
   - **Direct UDP** if both peers can reach each other
   - **Relay** if NAT/firewall prevents direct connection

```
Connecting via Iroh...
Local node ID: 5d4b2207a0bae3bf...
Peer relay URL: https://euc1-1.relay.n0.iroh-canary.iroh.link./
Connecting to peer 500e2241ff9c7abe...
Connected!
```

## Protocol Details

### ALPN Negotiation

ALPN (Application-Layer Protocol Negotiation) is used during TLS handshake:

```
Client                                 Server
  │                                      │
  │──── TLS ClientHello ────────────────►│
  │     ALPN: ["app-xplorer/1"]          │
  │                                      │
  │◄─── TLS ServerHello ─────────────────│
  │     ALPN: "app-xplorer/1"            │
  │                                      │
  │     (connection established)         │
```

If ALPNs don't match, connection fails with:
```
error 120: peer doesn't support any known protocol
```

### Message Size Limits

| Component | Limit |
|-----------|-------|
| Request length field | 4 bytes (max 4GB theoretical) |
| Enforced request limit | 100 MB |
| Response limit | 100 MB |
| QUIC stream | Unlimited (flow controlled) |

### Error Handling

Errors are returned as JSON responses with appropriate status codes:

```json
{
  "status": 404,
  "content_type": "application/json",
  "body": "eyJlcnJvciI6IkVuZHBvaW50IG5vdCBmb3VuZCJ9"
}
```

## Comparison with Alternatives

| Approach | Pros | Cons |
|----------|------|------|
| **iroh-gossip** | Built-in, simple pub/sub | 4KB limit, no request/response |
| **iroh-blobs** | Content-addressed, efficient | Not designed for RPC |
| **Custom QUIC streams** | Unlimited size, full control | Must implement protocol |
| **Raw TCP** | Simple | No NAT traversal, no encryption |

We chose **custom QUIC streams** because:
1. No message size limits (screenshots can be megabytes)
2. Request/response semantics match HTTP-like API
3. Still get all Iroh benefits (NAT traversal, encryption, discovery)

## File Locations

| File | Purpose |
|------|---------|
| `server/Sources/AppXplorerIroh/IrohTransportAdapter.swift` | Server-side transport adapter |
| `cli/Sources/xplorer/main.swift` | CLI client with `IrohTransport` class |
| `server/Sources/IrohTestServer/main.swift` | Test server for development |

## Usage Examples

### Server (iOS App)

```swift
import AppXplorerServer
import AppXplorerIroh

let server = AppXplorerServer()
let irohTransport = IrohTransportAdapter()
server.addTransport(irohTransport)
try server.start()

print("Connect with: xplorer iroh:\(irohTransport.nodeId ?? "")")
```

### Client (CLI)

```bash
# Connect using just node ID (uses DNS discovery)
xplorer iroh:500e2241ff9c7abef458954db706d8d10525a0a1df043caeef7afc8bf13bd723 info

# With relay URL for faster initial connection
xplorer iroh:500e2241... --relay https://euc1-1.relay.n0.iroh-canary.iroh.link./ info

# Download a file
xplorer iroh:500e2241... files/read?path=/tmp/screenshot.png -o screenshot.png
```

## Performance Characteristics

- **Connection setup**: 1-5 seconds (includes DNS lookup, relay connection)
- **Request latency**: ~50-200ms depending on network path
- **Throughput**: Limited by network, not protocol (tested with 4MB+ files)
- **Relay overhead**: ~20-50ms additional latency when relayed

## Security Considerations

1. **All traffic encrypted** - TLS 1.3 with node's Ed25519 keys
2. **Node ID = public key** - Cannot be spoofed
3. **No authentication** - Anyone with node ID can connect
4. **Localhost only recommended** - For production, add authentication layer

## Future Improvements

- [ ] Add authentication/authorization layer
- [ ] Support for streaming responses (live logs, etc.)
- [ ] Connection pooling for multiple requests
- [ ] Custom relay server support
