//
//  FileListContentViewController.swift
//  App Xplorer
//
//  Created by Kyle Howells on 26/05/2022.
//

import UIKit

class FileListContentViewController: UIViewController {

	// MARK: - Setup View
	
	override func loadView() {
		self.view = FileListContentView()
	}
	var _view: FileListContentView {
		return self.view as! FileListContentView
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		// Do any additional setup after loading the view.
	}
	
	var fileLists:[ [String] ] = [["file.txt", "Hello World.png", "test.jpg"]]
	
	
	
}


// MARK: - FileListContentView

class FileListContentView: UIView {
	
	let navView:UIView = {
		let view = UIView()
		view.backgroundColor = UIColor(red: 70.0/255.0, green: 178.0/255.0, blue: 222.0/255.0, alpha: 1.0)
		return view
	}()
	
	let listView:UIView = {
		let view = UIView()
		view.backgroundColor = UIColor(white: 0.98, alpha: 1)
		return view
	}()
	
	
	// MARK: - Setup
	
	override init(frame: CGRect) {
		super.init(frame: frame)
		self.commonInit()
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
		self.commonInit()
	}
	
	func commonInit() {
		self.addSubview(self.navView)
		self.addSubview(self.listView)
	}
	
	
	// MARK: - Layout
	
	override func layoutSubviews() {
		super.layoutSubviews()
		let size = self.bounds.size
		let safeArea = self.safeAreaInsets
		
		print("safeArea: \(safeArea)")
		
		self.navView.frame = {
			var frame = CGRect()
			frame.origin.x = 0
			frame.size.width = size.width
			
			frame.origin.y = safeArea.top
			frame.size.height = 40
			return frame
		}()
		
		self.listView.frame = {
			var frame = CGRect()
			frame.origin.x = 0
			frame.origin.y = self.navView.frame.maxY
			frame.size.width = size.width
			
			frame.size.height = size.height - frame.origin.y
			return frame
		}()
	}
	
}


