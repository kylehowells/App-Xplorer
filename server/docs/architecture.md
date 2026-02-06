# AppXplorerServer Architecture

## Transport-Agnostic Design

The server is designed to be transport-agnostic, allowing the same endpoint logic to work over HTTP, WebSocket, Iroh, Bluetooth, or any other transport mechanism.

## Architecture Overview

```
┌─────────────────────────────────────────┐
│           RequestHandler                │
│  (routes: "/info", "/screenshot", etc)  │
│  Input: Request → Output: Response      │
└────────────────┬────────────────────────┘
                 │
     ┌───────────┴───────────┐
     │   TransportAdapter    │
     │      (protocol)       │
     └───────────┬───────────┘
                 │
    ┌────────────┼────────────┬─────────────┐
    │            │            │             │
┌───┴───┐  ┌─────┴────┐  ┌────┴───┐  ┌──────┴─────┐
│ HTTP  │  │WebSocket │  │  Iroh  │  │ Bluetooth  │
│Adapter│  │ Adapter  │  │Adapter │  │  Adapter   │
└───────┘  └──────────┘  └────────┘  └────────────┘
```

## Core Types

### Request

A transport-agnostic request containing:
- `path`: The endpoint path (e.g., "/info", "/screenshot")
- `queryParams`: Key-value parameters
- `body`: Optional request body data

### Response

A transport-agnostic response containing:
- `status`: Success/error status
- `contentType`: MIME type of the response
- `body`: Response data (JSON, binary, HTML, etc.)

### TransportAdapter Protocol

Each transport implements this protocol to:
1. Receive incoming data and convert to `Request`
2. Pass `Request` to the `RequestHandler`
3. Convert `Response` back to transport-specific format
4. Send response to the client

### RequestHandler

The central router/dispatcher that:
1. Registers endpoint handlers
2. Matches incoming requests to handlers by path
3. Executes the handler and returns the response
4. Is completely transport-agnostic

## Request/Response Pattern

All endpoints follow a simple GET-style request/response pattern:
- Client sends a request with a path and optional parameters
- Server processes the request and returns a response
- No long-lived connections required (though transports like WebSocket can maintain them)

## Adding a New Transport

To add a new transport:

1. Create a new class implementing `TransportAdapter`
2. Implement the transport-specific connection/listening logic
3. Convert incoming messages to `Request` objects
4. Pass requests to the shared `RequestHandler`
5. Convert `Response` objects back to transport format
6. Send responses to clients

## Adding a New Endpoint

To add a new endpoint:

1. Register a handler with the `RequestHandler`
2. The handler receives a `Request` and returns a `Response`
3. The endpoint automatically works on all transports

```swift
handler.register("/myendpoint") { request in
    let data = ["key": "value"]
    return Response.json(data)
}
```
