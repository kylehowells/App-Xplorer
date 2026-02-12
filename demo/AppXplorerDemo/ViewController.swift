import UIKit
import AppXplorerServer

class ViewController: UIViewController {
	// MARK: - Properties

	private var server: AppXplorerServer?

	private let titleLabel: UILabel = {
		let label: UILabel = .init()
		label.text = "App-Xplorer Demo"
		label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
		label.textAlignment = .center
		return label
	}()

	private let statusLabel: UILabel = {
		let label: UILabel = .init()
		label.text = "Server: Starting..."
		label.font = UIFont.systemFont(ofSize: 18, weight: .medium)
		label.textAlignment = .center
		label.textColor = .systemOrange
		return label
	}()

	private let urlLabel: UILabel = {
		let label: UILabel = .init()
		label.text = ""
		label.font = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
		label.textAlignment = .center
		label.numberOfLines = 0
		return label
	}()

	private let instructionsLabel: UILabel = {
		let label: UILabel = .init()
		label.text = """
		Use the CLI to interact with this app:

		xplorer <ip>:8080
		xplorer <ip>:8080 info
		xplorer <ip>:8080 hierarchy/views
		xplorer <ip>:8080 files/list?path=/
		"""
		label.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
		label.textAlignment = .left
		label.numberOfLines = 0
		label.textColor = .secondaryLabel
		return label
	}()

	private let copyButton: UIButton = {
		let button: UIButton = .init(type: .system)
		button.setTitle("Copy URL", for: .normal)
		button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
		return button
	}()

	// MARK: - Lifecycle

	override func viewDidLoad() {
		super.viewDidLoad()

		self.view.backgroundColor = .systemBackground

		self.view.addSubview(self.titleLabel)
		self.view.addSubview(self.statusLabel)
		self.view.addSubview(self.urlLabel)
		self.view.addSubview(self.instructionsLabel)
		self.view.addSubview(self.copyButton)

		self.copyButton.addTarget(self, action: #selector(self.copyURLTapped), for: .touchUpInside)

		// Set up test UserDefaults for API testing
		self.setupTestUserDefaults()

		self.startServer()
	}

	// MARK: - Test Data

	private func setupTestUserDefaults() {
		let defaults: UserDefaults = .standard

		// String values
		defaults.set("John Doe", forKey: "demo.userName")
		defaults.set("john@example.com", forKey: "demo.userEmail")
		defaults.set("en-US", forKey: "demo.preferredLanguage")

		// Numeric values
		defaults.set(42, forKey: "demo.launchCount")
		defaults.set(3.14159, forKey: "demo.piValue")
		defaults.set(9999, forKey: "demo.highScore")

		// Boolean values
		defaults.set(true, forKey: "demo.darkModeEnabled")
		defaults.set(false, forKey: "demo.notificationsEnabled")
		defaults.set(true, forKey: "demo.hasCompletedOnboarding")

		// Date value
		defaults.set(Date(), forKey: "demo.lastLoginDate")
		defaults.set(Date(timeIntervalSince1970: 0), forKey: "demo.accountCreatedDate")

		// Array values
		defaults.set(["Apple", "Banana", "Cherry"], forKey: "demo.favoriteFruits")
		defaults.set([1, 2, 3, 4, 5], forKey: "demo.recentScores")
		defaults.set(["home", "work", "favorites"], forKey: "demo.tabOrder")

		// Dictionary value
		defaults.set([
			"theme": "dark",
			"fontSize": 14,
			"showLineNumbers": true,
		], forKey: "demo.editorSettings")

		// Data value (small binary blob)
		let testData: Data = "Hello, UserDefaults!".data(using: .utf8) ?? Data()
		defaults.set(testData, forKey: "demo.customData")

		// Some app-prefixed keys for testing filtering
		defaults.set("v1.0.0", forKey: "appxplorer.version")
		defaults.set(true, forKey: "appxplorer.debug.enabled")
		defaults.set("production", forKey: "appxplorer.environment")

		defaults.synchronize()
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()

		let bounds: CGRect = self.view.bounds
		let safeArea: UIEdgeInsets = self.view.safeAreaInsets
		let padding: CGFloat = 20

		let contentWidth: CGFloat = bounds.width - (padding * 2)

		// Title at top
		let titleSize: CGSize = self.titleLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
		self.titleLabel.frame = CGRect(
			x: padding,
			y: safeArea.top + 40,
			width: contentWidth,
			height: titleSize.height
		)

		// Status below title
		let statusSize: CGSize = self.statusLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
		self.statusLabel.frame = CGRect(
			x: padding,
			y: self.titleLabel.frame.maxY + 20,
			width: contentWidth,
			height: statusSize.height
		)

		// URL below status
		let urlSize: CGSize = self.urlLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
		self.urlLabel.frame = CGRect(
			x: padding,
			y: self.statusLabel.frame.maxY + 10,
			width: contentWidth,
			height: urlSize.height
		)

		// Copy button below URL
		let buttonSize: CGSize = self.copyButton.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
		self.copyButton.frame = CGRect(
			x: (bounds.width - buttonSize.width) / 2,
			y: self.urlLabel.frame.maxY + 15,
			width: buttonSize.width,
			height: buttonSize.height
		)

		// Instructions at bottom
		let instructionsSize: CGSize = self.instructionsLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
		self.instructionsLabel.frame = CGRect(
			x: padding,
			y: self.copyButton.frame.maxY + 40,
			width: contentWidth,
			height: instructionsSize.height
		)
	}

	// MARK: - Server

	private func startServer() {
		// Create server with HTTP on port 8080
		self.server = AppXplorerServer.withHTTP(port: 8080)

		do {
			try self.server?.start()

			self.statusLabel.text = "Server: Running"
			self.statusLabel.textColor = .systemGreen

			// Get device IP
			let ip: String = self.getWiFiAddress() ?? "localhost"
			self.urlLabel.text = "http://\(ip):8080"

			self.view.setNeedsLayout()

		}
		catch {
			self.statusLabel.text = "Server: Failed to start"
			self.statusLabel.textColor = .systemRed
			self.urlLabel.text = "Error: \(error.localizedDescription)"
		}
	}

	// MARK: - Actions

	@objc private func copyURLTapped() {
		guard let url = self.urlLabel.text, !url.isEmpty
		else {
			return
		}

		UIPasteboard.general.string = url

		// Show feedback
		let originalTitle: String? = self.copyButton.title(for: .normal)
		self.copyButton.setTitle("Copied!", for: .normal)

		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
			self.copyButton.setTitle(originalTitle, for: .normal)
		}
	}

	// MARK: - Helpers

	private func getWiFiAddress() -> String? {
		var address: String?
		var ifaddr: UnsafeMutablePointer<ifaddrs>?

		guard getifaddrs(&ifaddr) == 0
		else {
			return nil
		}

		defer { freeifaddrs(ifaddr) }

		var ptr: UnsafeMutablePointer<ifaddrs>? = ifaddr
		while ptr != nil {
			defer { ptr = ptr?.pointee.ifa_next }

			guard let interface = ptr?.pointee
			else {
				continue
			}

			let addrFamily: sa_family_t = interface.ifa_addr.pointee.sa_family
			if addrFamily == UInt8(AF_INET) {
				let name: String = String(cString: interface.ifa_name)
				if name == "en0" {
					var hostname: [CChar] = .init(repeating: 0, count: Int(NI_MAXHOST))
					getnameinfo(
						interface.ifa_addr,
						socklen_t(interface.ifa_addr.pointee.sa_len),
						&hostname,
						socklen_t(hostname.count),
						nil,
						socklen_t(0),
						NI_NUMERICHOST
					)
					address = String(cString: hostname)
				}
			}
		}

		return address
	}
}
