import UIKit
import AppXplorerServer

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
	var window: UIWindow?

	func scene(
		_ scene: UIScene,
		willConnectTo session: UISceneSession,
		options connectionOptions: UIScene.ConnectionOptions
	) {
		AppXplorerServer.log("Scene willConnectTo session", type: "lifecycle")

		guard let windowScene = (scene as? UIWindowScene)
		else {
			return
		}

		self.window = UIWindow(windowScene: windowScene)
		self.window?.rootViewController = MainTabBarController()
		self.window?.makeKeyAndVisible()

		AppXplorerServer.log("Window created and made visible", type: "lifecycle")
	}
}
