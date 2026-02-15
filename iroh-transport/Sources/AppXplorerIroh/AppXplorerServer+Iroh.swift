import AppXplorerServer
import Foundation

// MARK: - AppXplorerServer + Iroh

public extension AppXplorerServer {
    /// Create a server with Iroh transport for P2P connections
    ///
    /// Example:
    /// ```swift
    /// let server = try await AppXplorerServer.withIroh()
    /// print("Connect using Node ID: \(server.irohNodeId ?? "")")
    /// try server.start()
    /// ```
    static func withIroh(storagePath: String? = nil) async throws -> (AppXplorerServer, IrohTransportAdapter) {
        let server = AppXplorerServer()
        let irohTransport = IrohTransportAdapter(storagePath: storagePath)
        server.addTransport(irohTransport)
        return (server, irohTransport)
    }

    /// Create a server with both HTTP and Iroh transports
    ///
    /// This allows both local network access via HTTP and remote P2P access via Iroh.
    ///
    /// Example:
    /// ```swift
    /// let (server, iroh) = try await AppXplorerServer.withHTTPAndIroh(httpPort: 8080)
    /// print("HTTP: http://\(server.getWiFiAddress() ?? "localhost"):8080")
    /// print("Iroh: \(iroh.nodeId)")
    /// try server.start()
    /// ```
    static func withHTTPAndIroh(
        httpPort: UInt16 = 8080,
        irohStoragePath: String? = nil
    ) async throws -> (AppXplorerServer, IrohTransportAdapter) {
        let server = AppXplorerServer()

        // Add HTTP transport
        let httpTransport = HTTPTransportAdapter(port: httpPort)
        server.addTransport(httpTransport)

        // Add Iroh transport
        let irohTransport = IrohTransportAdapter(storagePath: irohStoragePath)
        server.addTransport(irohTransport)

        return (server, irohTransport)
    }
}
