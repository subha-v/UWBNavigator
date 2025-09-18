/*
See LICENSE folder for this sample's licensing information.

Abstract:
View controller for selecting an anchor to navigate to.
*/

import UIKit

class AnchorSelectionViewController: UIViewController {
    
    // MARK: - UI Components
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Select Anchor"
        label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Choose an anchor point to navigate to"
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = .systemGray
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private let refreshControl = UIRefreshControl()
    
    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "No anchors available\n\nPull to refresh"
        label.font = UIFont.systemFont(ofSize: 18)
        label.textColor = .systemGray
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private let logoutButton: UIBarButtonItem = {
        return UIBarButtonItem(title: "Logout", style: .plain, target: nil, action: nil)
    }()
    
    // MARK: - Data
    private var availableAnchors: [(id: String, name: String)] = []
    private var isLoading = false
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()

        // Set navigator online and publish data on initial load
        updateNavigatorPresence(isOnline: true)
        publishIdleNavigatorData()

        loadAvailableAnchors()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)

        // Update navigator presence to show as online with lastActive
        updateNavigatorPresence(isOnline: true)

        // Publish idle navigator data to API server
        publishIdleNavigatorData()

        loadAvailableAnchors()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        navigationItem.title = "Navigator"
        navigationItem.rightBarButtonItem = logoutButton
        logoutButton.target = self
        logoutButton.action = #selector(logoutTapped)
        
        // Prevent going back to login
        navigationItem.hidesBackButton = true
        
        view.addSubview(titleLabel)
        view.addSubview(descriptionLabel)
        view.addSubview(tableView)
        view.addSubview(emptyStateLabel)
        view.addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            descriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            tableView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 20),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(AnchorTableViewCell.self, forCellReuseIdentifier: "AnchorCell")
        
        // Setup refresh control
        refreshControl.addTarget(self, action: #selector(refreshAnchors), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    // MARK: - Data Loading
    private func loadAvailableAnchors() {
        guard !isLoading else { return }
        
        isLoading = true
        activityIndicator.startAnimating()
        emptyStateLabel.isHidden = true
        
        FirebaseManager.shared.fetchAvailableAnchors { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                self?.activityIndicator.stopAnimating()
                self?.refreshControl.endRefreshing()
                
                switch result {
                case .success(let anchors):
                    self?.availableAnchors = anchors
                    self?.tableView.reloadData()
                    self?.emptyStateLabel.isHidden = !anchors.isEmpty
                case .failure(let error):
                    self?.showError("Failed to load anchors: \(error.localizedDescription)")
                    self?.emptyStateLabel.isHidden = false
                }
            }
        }
    }
    
    // MARK: - Actions
    @objc private func refreshAnchors() {
        loadAvailableAnchors()
    }
    
    @objc private func logoutTapped() {
        let alert = UIAlertController(title: "Logout", message: "Are you sure you want to logout?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Logout", style: .destructive) { [weak self] _ in
            self?.performLogout()
        })
        present(alert, animated: true)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Only clear if we're not navigating to NavigatorViewController
        if !isMovingToNavigator {
            // Set navigator offline
            updateNavigatorPresence(isOnline: false)

            // Clear API data
            APIServer.shared.clearNavigatorData()
        }
    }

    private var isMovingToNavigator = false

    private func performLogout() {
        // Set navigator offline before logout
        updateNavigatorPresence(isOnline: false)

        // Clear API data
        APIServer.shared.clearNavigatorData()

        FirebaseManager.shared.signOut { [weak self] _ in
            DispatchQueue.main.async {
                self?.dismiss(animated: true)
            }
        }
    }
    
    private func navigateToAnchor(anchorId: String, anchorName: String) {
        UserSession.shared.selectedAnchorId = anchorId

        // Mark that we're moving to navigator
        isMovingToNavigator = true

        let navigatorVC = NavigatorViewController()
        navigatorVC.selectedAnchorId = anchorId
        navigatorVC.selectedAnchorName = anchorName
        navigationController?.pushViewController(navigatorVC, animated: true)
    }
    
    // MARK: - Helper Methods
    private func updateNavigatorPresence(isOnline: Bool) {
        if let userId = UserSession.shared.userId {
            // Use the new method that updates both lastSeen and lastActive
            FirebaseManager.shared.updateNavigatorPresence(userId: userId, isOnline: isOnline)
        }
    }

    private func publishIdleNavigatorData() {
        // Only publish if user is actually in navigator role
        guard UserSession.shared.userRole == .navigator else {
            APIServer.shared.clearNavigatorData()
            return
        }

        // Use NavigatorAPIDataBuilder for consistent idle data
        let navigatorData = NavigatorAPIDataBuilder.buildIdleNavigatorData()
        APIServer.shared.updateNavigatorData(navigatorData)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension AnchorSelectionViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return availableAnchors.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "AnchorCell", for: indexPath) as! AnchorTableViewCell
        let anchor = availableAnchors[indexPath.row]
        cell.configure(name: anchor.name, isAvailable: true)
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return availableAnchors.isEmpty ? nil : "Available Anchors"
    }
}

// MARK: - UITableViewDelegate
extension AnchorSelectionViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let anchor = availableAnchors[indexPath.row]
        navigateToAnchor(anchorId: anchor.id, anchorName: anchor.name)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }
}

// MARK: - AnchorTableViewCell
class AnchorTableViewCell: UITableViewCell {
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .systemGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemBlue
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let chevronImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "chevron.right"))
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCell()
    }
    
    private func setupCell() {
        contentView.addSubview(iconImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(statusLabel)
        contentView.addSubview(chevronImageView)
        
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 30),
            iconImageView.heightAnchor.constraint(equalToConstant: 30),
            
            nameLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 15),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 15),
            nameLabel.trailingAnchor.constraint(equalTo: chevronImageView.leadingAnchor, constant: -10),
            
            statusLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 5),
            statusLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            
            chevronImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            chevronImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: 15),
            chevronImageView.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    func configure(name: String, isAvailable: Bool) {
        nameLabel.text = name
        
        if isAvailable {
            iconImageView.image = UIImage(systemName: "location.fill")
            iconImageView.tintColor = .systemGreen
            statusLabel.text = "Available"
            statusLabel.textColor = .systemGreen
            selectionStyle = .default
            isUserInteractionEnabled = true
            contentView.alpha = 1.0
        } else {
            iconImageView.image = UIImage(systemName: "location.slash")
            iconImageView.tintColor = .systemGray
            statusLabel.text = "Unavailable"
            statusLabel.textColor = .systemGray
            selectionStyle = .none
            isUserInteractionEnabled = false
            contentView.alpha = 0.6
        }
    }
}