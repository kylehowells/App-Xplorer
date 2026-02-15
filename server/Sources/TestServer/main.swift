import Foundation
import AppXplorerServer

print("Starting test server...")

let server = AppXplorerServer()
let httpTransport = HTTPTransportAdapter(port: 8080)
server.addTransport(httpTransport)

do {
	try server.start()
	print("Server running on http://localhost:8080")
	print("")
	print("Test FPS endpoints:")
	print("  curl http://localhost:8080/fps/status")
	print("  curl http://localhost:8080/fps/enable")
	print("  curl http://localhost:8080/fps/recent")
	print("  curl http://localhost:8080/fps/history")
	print("")
	print("Press Ctrl+C to stop")
	RunLoop.main.run()
}
catch {
	print("Failed to start: \(error)")
	exit(1)
}
