//
//  MainMenuViewController.swift
//  App Xplorer
//
//  Created by Kyle Howells on 25/05/2022.
//

import UIKit

class MainMenuViewController: UICollectionViewController {
	
	init() {
		var listConfiguration = UICollectionLayoutListConfiguration(appearance: .sidebar)
		listConfiguration.showsSeparators = false
		
		let layout = UICollectionViewCompositionalLayout.list(using: listConfiguration)
		
		super.init(collectionViewLayout: layout)
		
		// Configure DataSource
		
		let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, HIOutlineItem>(handler: { cell, indexPath, menuItem in
			
			var contentConfiguration = cell.defaultContentConfiguration()
			
			if indexPath.item == 0 {
				contentConfiguration = UIListContentConfiguration.sidebarHeader()
			}
			else {
				contentConfiguration.textProperties.font = .preferredFont(forTextStyle: .body)
				contentConfiguration.imageProperties.reservedLayoutSize = CGSize(width: UIFloat(22), height: 0)
			}
			
			contentConfiguration.text = menuItem.title
			contentConfiguration.image = menuItem.image
			
			cell.contentConfiguration = contentConfiguration
		})
		
		self.dataSource = UICollectionViewDiffableDataSource<HIOutlineSection, HIOutlineItem>(collectionView: collectionView, cellProvider: {
			(collectionView: UICollectionView, indexPath: IndexPath, item: HIOutlineItem) -> UICollectionViewCell? in
			
			return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
		})
		
		self.collectionView.dataSource = self.dataSource
		
		self.refresh()
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	
	// MARK: - Menu Items
	
	enum HIOutlineSection {
		case tools
	}
	
	struct HIOutlineItem: Hashable {
		private let identifier = UUID()
		
		var title: String = ""
		var image: UIImage? = nil
		var indentation: Int = 0
		var subitems: [HIOutlineItem] = []
		
		var action: ( ()->() )? = nil
		
		
		// MARK: - Hashable
		
		func hash(into hasher: inout Hasher) {
			hasher.combine(self.identifier)
		}
		static func == (lhs: HIOutlineItem, rhs: HIOutlineItem) -> Bool {
			return lhs.identifier == rhs.identifier
		}
	}
	
	var dataSource: UICollectionViewDiffableDataSource<HIOutlineSection, HIOutlineItem>! = nil
	
	private lazy var toolItems: [HIOutlineItem] = {
		return [
			HIOutlineItem(title: "Tools", subitems: [
				HIOutlineItem(title: "Files", image: UIImage(systemName: "folder.fill"), action: { [weak self] in
					self?.openFileViewers()
				}),
				
				HIOutlineItem(title: "NSUserDefaults", image: UIImage(systemName: "line.3.horizontal"), action: { [weak self] in
					self?.openUserDefaultsViewers()
				}),
			]),
			
		]
	}()
	
	func refresh() {
		guard let dataSource = self.collectionView.dataSource as? UICollectionViewDiffableDataSource<HIOutlineSection, HIOutlineItem> else { return }
		
		func initialSnapshot(forItems:[HIOutlineItem]) -> NSDiffableDataSourceSectionSnapshot<HIOutlineItem>
		{
			var snapshot = NSDiffableDataSourceSectionSnapshot<HIOutlineItem>()
			
			func addItems(_ menuItems: [HIOutlineItem], to parent: HIOutlineItem?) {
				snapshot.append(menuItems, to: parent)
				snapshot.expand(menuItems)
				
				for menuItem in menuItems where !menuItem.subitems.isEmpty {
					addItems(menuItem.subitems, to: menuItem)
				}
			}
			
			addItems(forItems, to: nil)
			
			return snapshot
		}
		
		dataSource.apply(initialSnapshot(forItems: self.toolItems), to: .tools, animatingDifferences: false)
		// dataSource.apply(self.initialSnapshot(forItems: self.menuItems), to: .folders, animatingDifferences: false)
		
		DispatchQueue.main.async {
			self.collectionView.selectItem(at: IndexPath(item: 1, section: 0), animated: false, scrollPosition: [])
		}
	}
	
	
	override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		let sectionIndex = indexPath.section
		let itemIndex = indexPath.item - 1
		
		let items = self.toolItems[sectionIndex]
		let item = items.subitems[itemIndex]
		
		item.action?()
	}
	
	
	
	// MARK: - Select Support
	
	override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
		/* Don't focus the favorites group header */
		if indexPath.section == 0 && indexPath.row == 0 {
			return false
		}
		
		return true
	}
	
	
	// MARK: - Highlight Support
	
	override func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
		/* Don't focus the favorites group header */
		if indexPath.section == 0 && indexPath.row == 0 {
			return false
		}
		
		return true
	}
	
	
	// MARK: - Focus Support
	
	override func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
		
		/* Don't focus the favorites group header */
		if indexPath.section == 0 && indexPath.row == 0 {
			return false
		}
		
		return true
	}
	
	
	// MARK: - Open Content Views
	
	private func openFileViewers() {
		let fileViewer = FileListContentViewController()
		self.showDetailViewController(fileViewer, sender: self)
	}
	
	private func openUserDefaultsViewers() {
		let fileViewer = UserDefaultsBrowserViewController()
		self.showDetailViewController(fileViewer, sender: self)
	}
}
