//
//  AppDelegate.swift
//  App Xplorer
//
//  Created by Kyle Howells on 25/05/2022.
//

import UIKit

// - FPS graph
//
// - File manager
// * Browse all file locations
// * See all saved file bookmarks an app has active
//
// - NSUserDefaults viewer
// * See all app set values
// * Erase all app set values
// * See all values
// * See a specific Suite name (specified database name)
//
// - View file type database info
//
// - App UI viewer/editor
//
// - SQLite viewer
//
// - iCloud data viewer?
// - Check permissions state
//
// - List running threads/queues?
//
// - Multi-threaded log viewer
//


@main
class AppDelegate: UIResponder, UIApplicationDelegate {



	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
		// Override point for customization after application launch.
		return true
	}

	// MARK: UISceneSession Lifecycle

	func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
		// Called when a new scene session is being created.
		// Use this method to select a configuration to create the new scene with.
		return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
	}

	func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
		// Called when the user discards a scene session.
		// If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
		// Use this method to release any resources that were specific to the discarded scenes, as they will not return.
	}


}

