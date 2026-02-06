//
//  MainViewController.swift
//  App Xplorer
//
//  Created by Kyle Howells on 25/05/2022.
//

import UIKit

class MainViewController: UIViewController, UISplitViewControllerDelegate {
	
	let rootSplitViewController: UISplitViewController = UISplitViewController(style: .doubleColumn)
	
	let mainMenuViewController:MainMenuViewController = MainMenuViewController()
	
	init() {
		super.init(nibName: nil, bundle: nil)
		
		self.rootSplitViewController.primaryBackgroundStyle = .sidebar
		
		self.rootSplitViewController.preferredPrimaryColumnWidth = UIFloat(260)
		self.rootSplitViewController.minimumPrimaryColumnWidth = UIFloat(200)
		
		self.rootSplitViewController.delegate = self
		self.rootSplitViewController.preferredDisplayMode = .twoBesideSecondary
		self.rootSplitViewController.modalPresentationStyle = .overFullScreen
		
#if targetEnvironment(macCatalyst)
		self.rootSplitViewController.presentsWithGesture = false
#endif
		
		self.buildThreeColumnUI()
		
		self.addChild(self.rootSplitViewController)
		self.view.addSubview(self.rootSplitViewController.view)
	}
	
	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	func buildThreeColumnUI() {
		let sidebarNC = UINavigationController(rootViewController: self.mainMenuViewController)
		
#if targetEnvironment(macCatalyst)
		sidebarNC.isNavigationBarHidden = true
#else
		sidebarNC.navigationBar.prefersLargeTitles = true
#endif
		
		/*let listNC = UINavigationController(rootViewController: listViewController!)
#if targetEnvironment(macCatalyst)
		listNC.isNavigationBarHidden = true
		listNC.navigationBar.setBackgroundImage(UIImage(), for: .default)
		listNC.navigationBar.shadowImage = UIImage()
#else
		listNC.navigationBar.prefersLargeTitles = true
#endif*/
		
		/*
		let detailViewNC = UINavigationController(rootViewController: detailViewController)
#if targetEnvironment(macCatalyst)
		detailViewNC.isNavigationBarHidden = true
#else
		detailViewNC.navigationBar.setBackgroundImage(UIImage(), for: .default)
		detailViewNC.navigationBar.shadowImage = UIImage()
#endif
		detailViewNC.isToolbarHidden = true
		 */
		
		let contentVC = UINavigationController(rootViewController: FileListContentViewController())
		
#if targetEnvironment(macCatalyst)
		contentVC.isNavigationBarHidden = true
#else
		contentVC.navigationBar.prefersLargeTitles = true
#endif
		
		self.rootSplitViewController.viewControllers = [sidebarNC, contentVC]
	}
	
	
	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view.
		//self.view.backgroundColor = UIColor.red
	}
	
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		
		self.rootSplitViewController.view.frame = self.view.bounds
	}
	
	
	// MARK: - Disallow rotation on iPhone
	
	override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
		return UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .all
	}

}
