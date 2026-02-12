import UIKit
import AppXplorerServer

// MARK: - Main Tab Bar Controller

class MainTabBarController: UITabBarController {
	private var server: AppXplorerServer?

	override func viewDidLoad() {
		super.viewDidLoad()

		// Create tab view controllers
		let homeVC = HomeViewController()
		homeVC.tabBarItem = UITabBarItem(title: "Home", image: UIImage(systemName: "house"), tag: 0)

		let controlsVC = ControlsViewController()
		controlsVC.tabBarItem = UITabBarItem(title: "Controls", image: UIImage(systemName: "slider.horizontal.3"), tag: 1)

		let formsVC = FormsViewController()
		formsVC.tabBarItem = UITabBarItem(title: "Forms", image: UIImage(systemName: "text.cursor"), tag: 2)

		let listVC = ListViewController()
		let listNav = UINavigationController(rootViewController: listVC)
		listNav.tabBarItem = UITabBarItem(title: "List", image: UIImage(systemName: "list.bullet"), tag: 3)

		self.viewControllers = [homeVC, controlsVC, formsVC, listNav]

		// Set up test UserDefaults
		self.setupTestUserDefaults()

		// Start server
		self.startServer()
	}

	private func setupTestUserDefaults() {
		let defaults: UserDefaults = .standard

		defaults.set("John Doe", forKey: "demo.userName")
		defaults.set("john@example.com", forKey: "demo.userEmail")
		defaults.set(42, forKey: "demo.launchCount")
		defaults.set(true, forKey: "demo.darkModeEnabled")
		defaults.set(Date(), forKey: "demo.lastLoginDate")
		defaults.set(["Apple", "Banana", "Cherry"], forKey: "demo.favoriteFruits")
		defaults.set(["theme": "dark", "fontSize": 14], forKey: "demo.editorSettings")

		defaults.synchronize()
	}

	private func startServer() {
		self.server = AppXplorerServer.withHTTP(port: 8080)

		do {
			try self.server?.start()
			print("Server started on port 8080")
		}
		catch {
			print("Failed to start server: \(error)")
		}
	}
}

// MARK: - Home View Controller

class HomeViewController: UIViewController {
	private let titleLabel: UILabel = {
		let label: UILabel = .init()
		label.text = "App-Xplorer Demo"
		label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
		label.textAlignment = .center
		return label
	}()

	private let statusLabel: UILabel = {
		let label: UILabel = .init()
		label.text = "Server: Running on port 8080"
		label.font = UIFont.systemFont(ofSize: 18, weight: .medium)
		label.textAlignment = .center
		label.textColor = .systemGreen
		return label
	}()

	private let instructionsLabel: UILabel = {
		let label: UILabel = .init()
		label.text = """
		Use the CLI to interact with this app:

		xplorer <ip>:8080
		xplorer <ip>:8080 info
		xplorer <ip>:8080 hierarchy/views
		xplorer <ip>:8080 interact/tap?address=<addr>

		Navigate to different tabs to test
		various UI interactions!
		"""
		label.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
		label.textAlignment = .left
		label.numberOfLines = 0
		label.textColor = .secondaryLabel
		return label
	}()

	override func viewDidLoad() {
		super.viewDidLoad()
		self.view.backgroundColor = .systemBackground

		self.view.addSubview(self.titleLabel)
		self.view.addSubview(self.statusLabel)
		self.view.addSubview(self.instructionsLabel)
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()

		let padding: CGFloat = 20
		let contentWidth = self.view.bounds.width - (padding * 2)

		let titleSize = self.titleLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
		self.titleLabel.frame = CGRect(x: padding, y: self.view.safeAreaInsets.top + 40, width: contentWidth, height: titleSize.height)

		let statusSize = self.statusLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
		self.statusLabel.frame = CGRect(x: padding, y: self.titleLabel.frame.maxY + 20, width: contentWidth, height: statusSize.height)

		let instructionsSize = self.instructionsLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
		self.instructionsLabel.frame = CGRect(x: padding, y: self.statusLabel.frame.maxY + 30, width: contentWidth, height: instructionsSize.height)
	}
}

// MARK: - Controls View Controller

class ControlsViewController: UIViewController {
	private let scrollView = UIScrollView()
	private let contentView = UIView()

	private var tapCountLabel: UILabel!
	private var tapCount = 0

	private var switchStatusLabel: UILabel!
	private var sliderValueLabel: UILabel!
	private var stepperValueLabel: UILabel!
	private var segmentedLabel: UILabel!

	override func viewDidLoad() {
		super.viewDidLoad()
		self.view.backgroundColor = .systemBackground

		self.view.addSubview(self.scrollView)
		self.scrollView.addSubview(self.contentView)

		self.setupControls()
	}

	private func setupControls() {
		var yOffset: CGFloat = 20
		let padding: CGFloat = 20
		let labelWidth: CGFloat = 200
		let controlWidth: CGFloat = 150

		// Section: Buttons
		let buttonsTitle = self.createSectionLabel("Buttons")
		buttonsTitle.frame = CGRect(x: padding, y: yOffset, width: 300, height: 25)
		self.contentView.addSubview(buttonsTitle)
		yOffset += 35

		// Primary Button
		let primaryButton = UIButton(type: .system)
		primaryButton.setTitle("Tap Me!", for: .normal)
		primaryButton.backgroundColor = .systemBlue
		primaryButton.setTitleColor(.white, for: .normal)
		primaryButton.layer.cornerRadius = 8
		primaryButton.frame = CGRect(x: padding, y: yOffset, width: 150, height: 44)
		primaryButton.accessibilityIdentifier = "primaryButton"
		primaryButton.addTarget(self, action: #selector(self.primaryButtonTapped), for: .touchUpInside)
		self.contentView.addSubview(primaryButton)

		self.tapCountLabel = UILabel()
		self.tapCountLabel.text = "Taps: 0"
		self.tapCountLabel.frame = CGRect(x: padding + 160, y: yOffset, width: 100, height: 44)
		self.contentView.addSubview(self.tapCountLabel)
		yOffset += 60

		// Destructive Button
		let destructiveButton = UIButton(type: .system)
		destructiveButton.setTitle("Delete", for: .normal)
		destructiveButton.setTitleColor(.systemRed, for: .normal)
		destructiveButton.frame = CGRect(x: padding, y: yOffset, width: 150, height: 44)
		destructiveButton.accessibilityIdentifier = "deleteButton"
		destructiveButton.addTarget(self, action: #selector(self.showAlert), for: .touchUpInside)
		self.contentView.addSubview(destructiveButton)
		yOffset += 70

		// Section: Switch
		let switchTitle = self.createSectionLabel("Switch")
		switchTitle.frame = CGRect(x: padding, y: yOffset, width: 300, height: 25)
		self.contentView.addSubview(switchTitle)
		yOffset += 35

		let toggleSwitch = UISwitch()
		toggleSwitch.isOn = true
		toggleSwitch.frame = CGRect(x: padding, y: yOffset, width: 60, height: 31)
		toggleSwitch.accessibilityIdentifier = "mainSwitch"
		toggleSwitch.addTarget(self, action: #selector(self.switchChanged(_:)), for: .valueChanged)
		self.contentView.addSubview(toggleSwitch)

		self.switchStatusLabel = UILabel()
		self.switchStatusLabel.text = "ON"
		self.switchStatusLabel.textColor = .systemGreen
		self.switchStatusLabel.frame = CGRect(x: padding + 70, y: yOffset, width: 100, height: 31)
		self.contentView.addSubview(self.switchStatusLabel)
		yOffset += 60

		// Section: Slider
		let sliderTitle = self.createSectionLabel("Slider")
		sliderTitle.frame = CGRect(x: padding, y: yOffset, width: 300, height: 25)
		self.contentView.addSubview(sliderTitle)
		yOffset += 35

		let slider = UISlider()
		slider.minimumValue = 0
		slider.maximumValue = 100
		slider.value = 50
		slider.frame = CGRect(x: padding, y: yOffset, width: 200, height: 31)
		slider.accessibilityIdentifier = "volumeSlider"
		slider.addTarget(self, action: #selector(self.sliderChanged(_:)), for: .valueChanged)
		self.contentView.addSubview(slider)

		self.sliderValueLabel = UILabel()
		self.sliderValueLabel.text = "50"
		self.sliderValueLabel.frame = CGRect(x: padding + 210, y: yOffset, width: 50, height: 31)
		self.contentView.addSubview(self.sliderValueLabel)
		yOffset += 60

		// Section: Stepper
		let stepperTitle = self.createSectionLabel("Stepper")
		stepperTitle.frame = CGRect(x: padding, y: yOffset, width: 300, height: 25)
		self.contentView.addSubview(stepperTitle)
		yOffset += 35

		let stepper = UIStepper()
		stepper.minimumValue = 0
		stepper.maximumValue = 10
		stepper.value = 5
		stepper.frame = CGRect(x: padding, y: yOffset, width: 94, height: 32)
		stepper.accessibilityIdentifier = "quantityStepper"
		stepper.addTarget(self, action: #selector(self.stepperChanged(_:)), for: .valueChanged)
		self.contentView.addSubview(stepper)

		self.stepperValueLabel = UILabel()
		self.stepperValueLabel.text = "5"
		self.stepperValueLabel.font = .systemFont(ofSize: 24, weight: .bold)
		self.stepperValueLabel.frame = CGRect(x: padding + 110, y: yOffset, width: 50, height: 32)
		self.contentView.addSubview(self.stepperValueLabel)
		yOffset += 60

		// Section: Segmented Control
		let segmentedTitle = self.createSectionLabel("Segmented Control")
		segmentedTitle.frame = CGRect(x: padding, y: yOffset, width: 300, height: 25)
		self.contentView.addSubview(segmentedTitle)
		yOffset += 35

		let segmented = UISegmentedControl(items: ["Small", "Medium", "Large"])
		segmented.selectedSegmentIndex = 1
		segmented.frame = CGRect(x: padding, y: yOffset, width: 250, height: 32)
		segmented.accessibilityIdentifier = "sizeSelector"
		segmented.addTarget(self, action: #selector(self.segmentChanged(_:)), for: .valueChanged)
		self.contentView.addSubview(segmented)

		self.segmentedLabel = UILabel()
		self.segmentedLabel.text = "Selected: Medium"
		self.segmentedLabel.frame = CGRect(x: padding, y: yOffset + 40, width: 300, height: 25)
		self.contentView.addSubview(self.segmentedLabel)
		yOffset += 90

		// Update content size
		self.contentView.frame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: yOffset + 50)
	}

	private func createSectionLabel(_ text: String) -> UILabel {
		let label = UILabel()
		label.text = text
		label.font = .systemFont(ofSize: 20, weight: .semibold)
		label.textColor = .label
		return label
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		self.scrollView.frame = self.view.bounds
		self.scrollView.contentSize = self.contentView.bounds.size
	}

	@objc private func primaryButtonTapped() {
		self.tapCount += 1
		self.tapCountLabel.text = "Taps: \(self.tapCount)"
	}

	@objc private func showAlert() {
		let alert = UIAlertController(title: "Delete?", message: "Are you sure?", preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
		alert.addAction(UIAlertAction(title: "Delete", style: .destructive))
		self.present(alert, animated: true)
	}

	@objc private func switchChanged(_ sender: UISwitch) {
		self.switchStatusLabel.text = sender.isOn ? "ON" : "OFF"
		self.switchStatusLabel.textColor = sender.isOn ? .systemGreen : .systemRed
	}

	@objc private func sliderChanged(_ sender: UISlider) {
		self.sliderValueLabel.text = "\(Int(sender.value))"
	}

	@objc private func stepperChanged(_ sender: UIStepper) {
		self.stepperValueLabel.text = "\(Int(sender.value))"
	}

	@objc private func segmentChanged(_ sender: UISegmentedControl) {
		let titles = ["Small", "Medium", "Large"]
		self.segmentedLabel.text = "Selected: \(titles[sender.selectedSegmentIndex])"
	}
}

// MARK: - Forms View Controller

class FormsViewController: UIViewController {
	private let scrollView = UIScrollView()
	private let contentView = UIView()

	private var nameField: UITextField!
	private var emailField: UITextField!
	private var passwordField: UITextField!
	private var bioTextView: UITextView!
	private var searchBar: UISearchBar!
	private var outputLabel: UILabel!

	override func viewDidLoad() {
		super.viewDidLoad()
		self.view.backgroundColor = .systemBackground

		self.view.addSubview(self.scrollView)
		self.scrollView.addSubview(self.contentView)

		// Dismiss keyboard on tap
		let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.dismissKeyboard))
		tapGesture.cancelsTouchesInView = false
		self.view.addGestureRecognizer(tapGesture)

		self.setupForm()
	}

	private func setupForm() {
		var yOffset: CGFloat = 20
		let padding: CGFloat = 20
		let fieldWidth: CGFloat = self.view.bounds.width - (padding * 2)

		// Title
		let title = UILabel()
		title.text = "Form Inputs"
		title.font = .systemFont(ofSize: 24, weight: .bold)
		title.frame = CGRect(x: padding, y: yOffset, width: fieldWidth, height: 30)
		self.contentView.addSubview(title)
		yOffset += 50

		// Name Field
		let nameLabel = self.createLabel("Name:")
		nameLabel.frame = CGRect(x: padding, y: yOffset, width: fieldWidth, height: 20)
		self.contentView.addSubview(nameLabel)
		yOffset += 25

		self.nameField = self.createTextField(placeholder: "Enter your name")
		self.nameField.frame = CGRect(x: padding, y: yOffset, width: fieldWidth, height: 44)
		self.nameField.accessibilityIdentifier = "nameField"
		self.contentView.addSubview(self.nameField)
		yOffset += 60

		// Email Field
		let emailLabel = self.createLabel("Email:")
		emailLabel.frame = CGRect(x: padding, y: yOffset, width: fieldWidth, height: 20)
		self.contentView.addSubview(emailLabel)
		yOffset += 25

		self.emailField = self.createTextField(placeholder: "Enter your email")
		self.emailField.keyboardType = .emailAddress
		self.emailField.autocapitalizationType = .none
		self.emailField.frame = CGRect(x: padding, y: yOffset, width: fieldWidth, height: 44)
		self.emailField.accessibilityIdentifier = "emailField"
		self.contentView.addSubview(self.emailField)
		yOffset += 60

		// Password Field
		let passwordLabel = self.createLabel("Password:")
		passwordLabel.frame = CGRect(x: padding, y: yOffset, width: fieldWidth, height: 20)
		self.contentView.addSubview(passwordLabel)
		yOffset += 25

		self.passwordField = self.createTextField(placeholder: "Enter password")
		self.passwordField.isSecureTextEntry = true
		self.passwordField.frame = CGRect(x: padding, y: yOffset, width: fieldWidth, height: 44)
		self.passwordField.accessibilityIdentifier = "passwordField"
		self.contentView.addSubview(self.passwordField)
		yOffset += 60

		// Bio Text View
		let bioLabel = self.createLabel("Bio:")
		bioLabel.frame = CGRect(x: padding, y: yOffset, width: fieldWidth, height: 20)
		self.contentView.addSubview(bioLabel)
		yOffset += 25

		self.bioTextView = UITextView()
		self.bioTextView.font = .systemFont(ofSize: 16)
		self.bioTextView.layer.borderColor = UIColor.systemGray4.cgColor
		self.bioTextView.layer.borderWidth = 1
		self.bioTextView.layer.cornerRadius = 8
		self.bioTextView.frame = CGRect(x: padding, y: yOffset, width: fieldWidth, height: 100)
		self.bioTextView.accessibilityIdentifier = "bioTextView"
		self.contentView.addSubview(self.bioTextView)
		yOffset += 120

		// Search Bar
		let searchLabel = self.createLabel("Search:")
		searchLabel.frame = CGRect(x: padding, y: yOffset, width: fieldWidth, height: 20)
		self.contentView.addSubview(searchLabel)
		yOffset += 25

		self.searchBar = UISearchBar()
		self.searchBar.placeholder = "Search..."
		self.searchBar.frame = CGRect(x: padding - 8, y: yOffset, width: fieldWidth + 16, height: 44)
		self.searchBar.accessibilityIdentifier = "mainSearchBar"
		self.contentView.addSubview(self.searchBar)
		yOffset += 60

		// Submit Button
		let submitButton = UIButton(type: .system)
		submitButton.setTitle("Submit Form", for: .normal)
		submitButton.backgroundColor = .systemBlue
		submitButton.setTitleColor(.white, for: .normal)
		submitButton.layer.cornerRadius = 8
		submitButton.frame = CGRect(x: padding, y: yOffset, width: fieldWidth, height: 50)
		submitButton.accessibilityIdentifier = "submitButton"
		submitButton.addTarget(self, action: #selector(self.submitForm), for: .touchUpInside)
		self.contentView.addSubview(submitButton)
		yOffset += 70

		// Output Label
		self.outputLabel = UILabel()
		self.outputLabel.text = "Form output will appear here"
		self.outputLabel.textColor = .secondaryLabel
		self.outputLabel.numberOfLines = 0
		self.outputLabel.frame = CGRect(x: padding, y: yOffset, width: fieldWidth, height: 100)
		self.contentView.addSubview(self.outputLabel)
		yOffset += 120

		self.contentView.frame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: yOffset)
	}

	private func createLabel(_ text: String) -> UILabel {
		let label = UILabel()
		label.text = text
		label.font = .systemFont(ofSize: 14, weight: .medium)
		label.textColor = .secondaryLabel
		return label
	}

	private func createTextField(placeholder: String) -> UITextField {
		let field = UITextField()
		field.placeholder = placeholder
		field.borderStyle = .roundedRect
		field.font = .systemFont(ofSize: 16)
		return field
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		self.scrollView.frame = self.view.bounds
		self.scrollView.contentSize = self.contentView.bounds.size
	}

	@objc private func dismissKeyboard() {
		self.view.endEditing(true)
	}

	@objc private func submitForm() {
		self.outputLabel.text = """
		Submitted:
		Name: \(self.nameField.text ?? "")
		Email: \(self.emailField.text ?? "")
		Bio: \(self.bioTextView.text ?? "")
		Search: \(self.searchBar.text ?? "")
		"""
		self.outputLabel.textColor = .systemGreen
	}
}

// MARK: - List View Controller

class ListViewController: UITableViewController {
	private let items = [
		"Apple", "Banana", "Cherry", "Date", "Elderberry",
		"Fig", "Grape", "Honeydew", "Jackfruit", "Kiwi",
		"Lemon", "Mango", "Nectarine", "Orange", "Papaya",
		"Quince", "Raspberry", "Strawberry", "Tangerine", "Watermelon",
	]

	override func viewDidLoad() {
		super.viewDidLoad()
		self.title = "Scrollable List"
		self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
		self.tableView.accessibilityIdentifier = "fruitsTableView"
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return self.items.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
		cell.textLabel?.text = self.items[indexPath.row]
		cell.accessibilityIdentifier = "fruit_\(indexPath.row)"
		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)

		let alert = UIAlertController(
			title: "Selected",
			message: "You selected: \(self.items[indexPath.row])",
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: "OK", style: .default))
		self.present(alert, animated: true)
	}
}

// MARK: - Legacy ViewController (kept for compatibility)

class ViewController: UIViewController {
	override func viewDidLoad() {
		super.viewDidLoad()
		// This class is kept for SceneDelegate compatibility
		// The actual UI is in MainTabBarController
	}
}
