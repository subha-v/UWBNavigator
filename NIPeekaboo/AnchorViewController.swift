/*
See LICENSE folder for this sample's licensing information.

Abstract:
View controller for anchor phones showing connected navigators.
*/

import UIKit
import NearbyInteraction
import MultipeerConnectivity

class AnchorViewController: UIViewController {
    
    // MARK: - UI Components
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Anchor Mode"
        label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Waiting for navigators..."
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = .systemGray
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private let logoutButton: UIBarButtonItem = {
        return UIBarButtonItem(title: "Logout", style: .plain, target: nil, action: nil)
    }()
    
    // MARK: - NearbyInteraction Properties
    private var sessions: [MCPeerID: NISession] = [:]
    private var peerTokens: [MCPeerID: NIDiscoveryToken] = [:]
    private var connectedNavigators: [NavigatorInfo] = []
    private var mpc: MPCSession?
    
    // MARK: - Data Model
    struct NavigatorInfo {
        let peerId: MCPeerID
        let displayName: String
        var distance: Float?
        var direction: simd_float3?
        var lastUpdate: Date
        var connectionState: ConnectionState
        
        enum ConnectionState {
            case connected
            case tracking
            case disconnected
        }
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
        startAnchorMode()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePresence(isOnline: true)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        updatePresence(isOnline: false)
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        navigationItem.title = "Anchor"
        navigationItem.rightBarButtonItem = logoutButton
        logoutButton.target = self
        logoutButton.action = #selector(logoutTapped)
        
        view.addSubview(titleLabel)
        view.addSubview(statusLabel)
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            tableView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(NavigatorTableViewCell.self, forCellReuseIdentifier: "NavigatorCell")
    }
    
    // MARK: - Anchor Mode
    private func startAnchorMode() {
        // Initialize MultipeerConnectivity with anchor role
        #if targetEnvironment(simulator)
        mpc = MPCSession(service: "nisample", identity: "anchor-simulator", maxPeers: 10)
        #else
        mpc = MPCSession(service: "nisample", identity: "anchor-\(UserSession.shared.userId ?? "unknown")", maxPeers: 10)
        #endif
        
        mpc?.peerConnectedHandler = { [weak self] peer in
            self?.handleNavigatorConnected(peer)
        }
        
        mpc?.peerDataHandler = { [weak self] data, peer in
            self?.handleDataReceived(data: data, from: peer)
        }
        
        mpc?.peerDisconnectedHandler = { [weak self] peer in
            self?.handleNavigatorDisconnected(peer)
        }
        
        mpc?.start()
        updateStatus()
    }
    
    // MARK: - Navigator Management
    private func handleNavigatorConnected(_ peer: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            // Create new NISession for this navigator
            let session = NISession()
            session.delegate = self
            self?.sessions[peer] = session
            
            // Add to connected navigators
            // Extract navigator name from displayName format "navigator-userId"
            let displayComponents = peer.displayName.components(separatedBy: "-")
            let navigatorName = displayComponents.count >= 2 ? "Navigator (\(displayComponents[1]))" : peer.displayName
            
            let navigator = NavigatorInfo(
                peerId: peer,
                displayName: navigatorName,
                distance: nil,
                direction: nil,
                lastUpdate: Date(),
                connectionState: .connected
            )
            self?.connectedNavigators.append(navigator)
            
            // Share discovery token
            if let discoveryToken = session.discoveryToken {
                self?.shareDiscoveryToken(discoveryToken, with: peer)
            }
            
            self?.updateStatus()
            self?.tableView.reloadData()
            
            // Update Firebase
            if let userId = UserSession.shared.userId {
                FirebaseManager.shared.updateAnchorConnection(anchorId: userId, navigatorId: peer.displayName, isConnecting: true) { _ in }
            }
        }
    }
    
    private func handleNavigatorDisconnected(_ peer: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            // Clean up session
            self?.sessions[peer]?.invalidate()
            self?.sessions.removeValue(forKey: peer)
            self?.peerTokens.removeValue(forKey: peer)
            
            // Update navigator list
            if let index = self?.connectedNavigators.firstIndex(where: { $0.peerId == peer }) {
                self?.connectedNavigators[index].connectionState = .disconnected
                self?.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .fade)
                
                // Remove after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if let currentIndex = self?.connectedNavigators.firstIndex(where: { $0.peerId == peer }) {
                        self?.connectedNavigators.remove(at: currentIndex)
                        self?.tableView.deleteRows(at: [IndexPath(row: currentIndex, section: 0)], with: .fade)
                    }
                }
            }
            
            self?.updateStatus()
            
            // Update Firebase
            if let userId = UserSession.shared.userId {
                FirebaseManager.shared.updateAnchorConnection(anchorId: userId, navigatorId: peer.displayName, isConnecting: false) { _ in }
            }
        }
    }
    
    private func handleDataReceived(data: Data, from peer: MCPeerID) {
        guard let discoveryToken = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.peerTokens[peer] = discoveryToken
            
            // Start tracking with this navigator
            if let session = self?.sessions[peer] {
                let config = NINearbyPeerConfiguration(peerToken: discoveryToken)
                session.run(config)
                
                // Update navigator state
                if let index = self?.connectedNavigators.firstIndex(where: { $0.peerId == peer }) {
                    self?.connectedNavigators[index].connectionState = .tracking
                    self?.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
                }
            }
        }
    }
    
    private func shareDiscoveryToken(_ token: NIDiscoveryToken, with peer: MCPeerID) {
        guard let encodedData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            return
        }
        mpc?.sendData(data: encodedData, peers: [peer], mode: .reliable)
    }
    
    // MARK: - Helper Methods
    private func updateStatus() {
        let count = connectedNavigators.count
        if count == 0 {
            statusLabel.text = "Waiting for navigators..."
        } else if count == 1 {
            statusLabel.text = "1 navigator connected"
        } else {
            statusLabel.text = "\(count) navigators connected"
        }
    }
    
    private func updatePresence(isOnline: Bool) {
        if let userId = UserSession.shared.userId {
            FirebaseManager.shared.updateUserPresence(userId: userId, isOnline: isOnline)
        }
    }
    
    // MARK: - Actions
    @objc private func logoutTapped() {
        let alert = UIAlertController(title: "Logout", message: "Are you sure you want to logout?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Logout", style: .destructive) { [weak self] _ in
            self?.performLogout()
        })
        present(alert, animated: true)
    }
    
    private func performLogout() {
        // Clean up sessions
        sessions.values.forEach { $0.invalidate() }
        sessions.removeAll()
        mpc?.invalidate()
        
        // Update presence
        updatePresence(isOnline: false)
        
        // Logout
        FirebaseManager.shared.signOut { [weak self] _ in
            DispatchQueue.main.async {
                self?.dismiss(animated: true)
            }
        }
    }
}

// MARK: - NISessionDelegate
extension AnchorViewController: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        // Find which peer this session belongs to
        guard let peer = sessions.first(where: { $0.value === session })?.key,
              let peerToken = peerTokens[peer] else {
            return
        }
        
        // Find the nearby object for this peer
        guard let nearbyObject = nearbyObjects.first(where: { $0.discoveryToken == peerToken }) else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            // Update navigator info
            if let index = self?.connectedNavigators.firstIndex(where: { $0.peerId == peer }) {
                self?.connectedNavigators[index].distance = nearbyObject.distance
                self?.connectedNavigators[index].direction = nearbyObject.direction
                self?.connectedNavigators[index].lastUpdate = Date()
                
                // Update table view cell
                self?.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
            }
        }
    }
    
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        // Handle removal if needed
    }
    
    func sessionWasSuspended(_ session: NISession) {
        // Handle suspension
    }
    
    func sessionSuspensionEnded(_ session: NISession) {
        // Resume session
        if let config = session.configuration {
            session.run(config)
        }
    }
    
    func session(_ session: NISession, didInvalidateWith error: Error) {
        // Handle invalidation
    }
}

// MARK: - UITableViewDataSource
extension AnchorViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return connectedNavigators.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "NavigatorCell", for: indexPath) as! NavigatorTableViewCell
        let navigator = connectedNavigators[indexPath.row]
        cell.configure(with: navigator)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension AnchorViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
}

// MARK: - NavigatorTableViewCell
class NavigatorTableViewCell: UITableViewCell {
    private let nameLabel = UILabel()
    private let distanceLabel = UILabel()
    private let statusIndicator = UIView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCell()
    }
    
    private func setupCell() {
        selectionStyle = .none
        
        nameLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        distanceLabel.font = UIFont.systemFont(ofSize: 14)
        distanceLabel.textColor = .systemGray
        distanceLabel.translatesAutoresizingMaskIntoConstraints = false
        
        statusIndicator.layer.cornerRadius = 5
        statusIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(statusIndicator)
        contentView.addSubview(nameLabel)
        contentView.addSubview(distanceLabel)
        
        NSLayoutConstraint.activate([
            statusIndicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            statusIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            statusIndicator.widthAnchor.constraint(equalToConstant: 10),
            statusIndicator.heightAnchor.constraint(equalToConstant: 10),
            
            nameLabel.leadingAnchor.constraint(equalTo: statusIndicator.trailingAnchor, constant: 15),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            distanceLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            distanceLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 5),
            distanceLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor)
        ])
    }
    
    func configure(with navigator: AnchorViewController.NavigatorInfo) {
        nameLabel.text = navigator.displayName
        
        switch navigator.connectionState {
        case .connected:
            statusIndicator.backgroundColor = .systemOrange
            distanceLabel.text = "Connected - Waiting for tracking..."
        case .tracking:
            statusIndicator.backgroundColor = .systemGreen
            if let distance = navigator.distance {
                distanceLabel.text = String(format: "Distance: %.2f m", distance)
            } else {
                distanceLabel.text = "Tracking..."
            }
        case .disconnected:
            statusIndicator.backgroundColor = .systemRed
            distanceLabel.text = "Disconnected"
        }
    }
}