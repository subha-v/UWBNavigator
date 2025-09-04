/*
See LICENSE folder for this sample's licensing information.

Abstract:
View controller for anchor phones showing connected navigators.
*/

import UIKit
import NearbyInteraction
import MultipeerConnectivity
import Firebase
import FirebaseFirestore

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
    private var connectedAnchors: [AnchorInfo] = []
    private var mpc: MPCSession?
    private var anchorDestination: AnchorDestination?
    private var measurementTimer: Timer?
    
    // Required anchor configurations
    private let requiredAnchors: [String: AnchorDestination] = [
        "subhavee1@gmail.com": .window,
        "akshata@valuenex.com": .kitchen,
        "elena@valuenex.com": .meetingRoom
    ]
    private var connectedAnchorEmails: Set<String> = []
    
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
    
    struct AnchorInfo {
        let peerId: MCPeerID
        let displayName: String
        let destination: AnchorDestination?
        var distance: Float?
        var direction: simd_float3?
        var lastUpdate: Date
        var connectionState: NavigatorInfo.ConnectionState
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
        loadAnchorDestination()
        startAnchorMode()
        
        // One-time update for existing anchor accounts
        checkAndUpdateDestinations()
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
    private func loadAnchorDestination() {
        guard let userId = UserSession.shared.userId else { return }
        
        FirebaseManager.shared.fetchUserDestination(userId: userId) { [weak self] result in
            switch result {
            case .success(let destinationString):
                if let destStr = destinationString,
                   let dest = AnchorDestination(rawValue: destStr) {
                    self?.anchorDestination = dest
                    
                    // Register with DistanceErrorTracker
                    DistanceErrorTracker.shared.registerDevice(userId, destination: dest)
                    
                    // Update status now that we know our destination
                    self?.updateStatus()
                    
                    // Start tracking session if other anchors are connected
                    self?.startTrackingSessionIfNeeded()
                } else {
                    print("No destination found for user \(userId). May need to run destination update.")
                }
            case .failure(let error):
                print("Error loading destination: \(error)")
            }
        }
    }
    
    private func checkAndUpdateDestinations() {
        // Always run the update for existing anchor accounts to ensure destinations are set
        print("Checking and updating destinations for anchor accounts...")
        FirebaseManager.shared.updateExistingAnchorDestinations()
    }
    
    private func startAnchorMode() {
        // Initialize MultipeerConnectivity with anchor role
        #if targetEnvironment(simulator)
        mpc = MPCSession(service: "nisample", identity: "anchor-simulator", maxPeers: 20)
        #else
        mpc = MPCSession(service: "nisample", identity: "anchor-\(UserSession.shared.userId ?? "unknown")", maxPeers: 20)
        #endif
        
        mpc?.peerConnectedHandler = { [weak self] peer in
            self?.handlePeerConnected(peer)
        }
        
        mpc?.peerDataHandler = { [weak self] data, peer in
            self?.handleDataReceived(data: data, from: peer)
        }
        
        mpc?.peerDisconnectedHandler = { [weak self] peer in
            self?.handlePeerDisconnected(peer)
        }
        
        mpc?.start()
        updateStatus()
    }
    
    // MARK: - Peer Management
    private func handlePeerConnected(_ peer: MCPeerID) {
        // Determine if peer is anchor or navigator
        let peerComponents = peer.displayName.components(separatedBy: "-")
        guard peerComponents.count >= 2 else { return }
        
        let peerRole = peerComponents[0]
        
        if peerRole == "anchor" {
            handleAnchorConnected(peer)
        } else if peerRole == "navigator" {
            handleNavigatorConnected(peer)
        }
    }
    
    private func handleAnchorConnected(_ peer: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            // Create new NISession for this anchor
            let session = NISession()
            session.delegate = self
            self?.sessions[peer] = session
            
            // Extract anchor info
            let displayComponents = peer.displayName.components(separatedBy: "-")
            let anchorName = displayComponents.count >= 2 ? "Anchor (\(displayComponents[1]))" : peer.displayName
            
            // Fetch destination for this anchor
            let anchorUserId = displayComponents.count >= 2 ? displayComponents[1] : ""
            FirebaseManager.shared.fetchUserDestination(userId: anchorUserId) { [weak self] result in
                var destination: AnchorDestination? = nil
                if case .success(let destStr) = result,
                   let destString = destStr {
                    destination = AnchorDestination(rawValue: destString)
                }
                
                let anchor = AnchorInfo(
                    peerId: peer,
                    displayName: anchorName,
                    destination: destination,
                    distance: nil,
                    direction: nil,
                    lastUpdate: Date(),
                    connectionState: .connected
                )
                
                DispatchQueue.main.async {
                    self?.connectedAnchors.append(anchor)
                    
                    // Share discovery token
                    if let discoveryToken = session.discoveryToken {
                        self?.shareDiscoveryToken(discoveryToken, with: peer)
                    }
                    
                    self?.updateStatus()
                    self?.tableView.reloadData()
                    // Update status will rebuild connectedAnchorEmails set
                    self?.startTrackingSessionIfNeeded()
                }
            }
        }
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
    
    private func handlePeerDisconnected(_ peer: MCPeerID) {
        // Determine if peer is anchor or navigator
        let peerComponents = peer.displayName.components(separatedBy: "-")
        guard peerComponents.count >= 2 else { return }
        
        let peerRole = peerComponents[0]
        
        if peerRole == "anchor" {
            handleAnchorDisconnected(peer)
        } else if peerRole == "navigator" {
            handleNavigatorDisconnected(peer)
        }
    }
    
    private func handleAnchorDisconnected(_ peer: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            // Clean up session
            self?.sessions[peer]?.invalidate()
            self?.sessions.removeValue(forKey: peer)
            self?.peerTokens.removeValue(forKey: peer)
            
            // Update anchor list
            if let index = self?.connectedAnchors.firstIndex(where: { $0.peerId == peer }) {
                self?.connectedAnchors[index].connectionState = .disconnected
                self?.tableView.reloadData()
                
                // Remove after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if let currentIndex = self?.connectedAnchors.firstIndex(where: { $0.peerId == peer }) {
                        self?.connectedAnchors.remove(at: currentIndex)
                        self?.tableView.reloadData()
                    }
                }
            }
            
            self?.updateStatus()
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
        // Build set of connected anchor emails
        connectedAnchorEmails.removeAll()
        
        // Add self if we're one of the required anchors
        if let destination = anchorDestination {
            // Find which email corresponds to our destination
            for (email, dest) in requiredAnchors {
                if dest == destination {
                    connectedAnchorEmails.insert(email)
                    print("Current user recognized as: \(email) with destination: \(destination.displayName)")
                    break
                }
            }
        }
        
        // Add connected anchors
        for anchor in connectedAnchors {
            if let destination = anchor.destination {
                // Find the email for this destination
                for (email, dest) in requiredAnchors {
                    if dest == destination {
                        connectedAnchorEmails.insert(email)
                        break
                    }
                }
            }
        }
        
        // Check which anchors are missing
        var missingAnchors: [String] = []
        for (email, destination) in requiredAnchors {
            if !connectedAnchorEmails.contains(email) {
                missingAnchors.append(destination.displayName)
            }
        }
        
        var statusText = ""
        
        if !missingAnchors.isEmpty {
            statusText = "Waiting for: \(missingAnchors.joined(separator: ", "))"
        } else {
            // All required anchors are connected
            statusText = "✅ All anchors connected - Tracking active"
        }
        
        // Add navigator count if any
        if connectedNavigators.count > 0 {
            statusText += " | \(connectedNavigators.count) navigator\(connectedNavigators.count == 1 ? "" : "s")"
        }
        
        statusLabel.text = statusText
    }
    
    private func startTrackingSessionIfNeeded() {
        // Only start tracking when ALL 3 required anchors are connected
        guard anchorDestination != nil,
              measurementTimer == nil else { return }
        
        // Check if all required anchors are connected
        if connectedAnchorEmails.count != requiredAnchors.count {
            print("Not all required anchors connected. Have \(connectedAnchorEmails.count) of \(requiredAnchors.count)")
            return
        }
        
        // Build participants map with actual user IDs
        var participants: [String: AnchorDestination] = [:]
        
        // Add self
        if let userId = UserSession.shared.userId,
           let dest = anchorDestination {
            participants[userId] = dest
        }
        
        // Add connected anchors
        for anchor in connectedAnchors {
            let components = anchor.peerId.displayName.components(separatedBy: "-")
            if components.count >= 2,
               let dest = anchor.destination {
                participants[components[1]] = dest
            }
        }
        
        // Verify we have all 3 destinations
        let destinations = Set(participants.values.map { $0 })
        guard destinations.contains(.window),
              destinations.contains(.kitchen),
              destinations.contains(.meetingRoom) else {
            print("Missing required destinations. Have: \(destinations)")
            return
        }
        
        print("All 3 anchors connected! Starting tracking session...")
        DistanceErrorTracker.shared.startSession(participants: participants)
        startMeasurementTimer()
    }
    
    private func startMeasurementTimer() {
        measurementTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateDistanceTracking()
        }
    }
    
    private func updateDistanceTracking() {
        guard let userId = UserSession.shared.userId else { return }
        
        // Update distances for all connected peers
        for (peer, _) in sessions {
            if let index = connectedAnchors.firstIndex(where: { $0.peerId == peer }),
               let distance = connectedAnchors[index].distance {
                
                let components = peer.displayName.components(separatedBy: "-")
                if components.count >= 2 {
                    DistanceErrorTracker.shared.updateDistance(from: userId, to: components[1], distance: distance)
                }
            } else if let index = connectedNavigators.firstIndex(where: { $0.peerId == peer }),
                      let distance = connectedNavigators[index].distance {
                
                let components = peer.displayName.components(separatedBy: "-")
                if components.count >= 2 {
                    DistanceErrorTracker.shared.updateDistance(from: userId, to: components[1], distance: distance)
                }
            }
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
        // Stop measurement timer
        measurementTimer?.invalidate()
        measurementTimer = nil
        
        // End tracking session
        DistanceErrorTracker.shared.endSession()
        
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
            // Check if it's an anchor or navigator
            if let index = self?.connectedAnchors.firstIndex(where: { $0.peerId == peer }) {
                // Update anchor info
                self?.connectedAnchors[index].distance = nearbyObject.distance
                self?.connectedAnchors[index].direction = nearbyObject.direction
                self?.connectedAnchors[index].lastUpdate = Date()
                
                // Update table view
                self?.tableView.reloadData()
            } else if let index = self?.connectedNavigators.firstIndex(where: { $0.peerId == peer }) {
                // Update navigator info
                self?.connectedNavigators[index].distance = nearbyObject.distance
                self?.connectedNavigators[index].direction = nearbyObject.direction
                self?.connectedNavigators[index].lastUpdate = Date()
                
                // Update table view cell
                self?.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
            }
            
            // Update API server with current data
            self?.updateAPIData()
        }
    }
    
    // MARK: - API Data Update
    private func updateAPIData() {
        // Get current distance measurements for error tracking
        var measuredDistance: Float?
        var groundTruthDistance: Float?
        var distanceError: Float?
        
        // If we have distance data, calculate error
        if let firstNavigator = connectedNavigators.first,
           let distance = firstNavigator.distance {
            measuredDistance = distance
            
            // Get ground truth based on anchor destination
            if anchorDestination != nil {
                // This would need to be calculated based on actual ground truth data
                // For now, using placeholder values
                groundTruthDistance = nil  // Would come from DistanceErrorTracker
                if let groundTruth = groundTruthDistance {
                    distanceError = measuredDistance! - groundTruth
                }
            }
        }
        
        let anchorData = [[
            "id": UserSession.shared.userId ?? "unknown",
            "name": UserSession.shared.displayName ?? UIDevice.current.name,
            "destination": anchorDestination?.rawValue ?? "unknown",
            "battery": Int(UIDevice.current.batteryLevel * 100),
            "status": connectedNavigators.isEmpty ? "disconnected" : "connected",
            "connectedNavigators": connectedNavigators.count,
            "measuredDistance": measuredDistance as Any,
            "groundTruthDistance": groundTruthDistance as Any,
            "distanceError": distanceError as Any
        ] as [String : Any]]
        
        APIServer.shared.updateAnchorData(anchorData)
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
    func numberOfSections(in tableView: UITableView) -> Int {
        var sections = 0
        if !connectedAnchors.isEmpty { sections += 1 }
        if !connectedNavigators.isEmpty { sections += 1 }
        return max(1, sections) // At least 1 section for empty state
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if !connectedAnchors.isEmpty && section == 0 {
            return connectedAnchors.count
        } else if !connectedNavigators.isEmpty {
            let navigatorSection = connectedAnchors.isEmpty ? 0 : 1
            if section == navigatorSection {
                return connectedNavigators.count
            }
        }
        return 0
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if !connectedAnchors.isEmpty && section == 0 {
            return "Connected Anchors"
        } else if !connectedNavigators.isEmpty {
            let navigatorSection = connectedAnchors.isEmpty ? 0 : 1
            if section == navigatorSection {
                return "Connected Navigators"
            }
        }
        return nil
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "NavigatorCell", for: indexPath) as! NavigatorTableViewCell
        
        if !connectedAnchors.isEmpty && indexPath.section == 0 {
            let anchor = connectedAnchors[indexPath.row]
            cell.configureForAnchor(with: anchor)
        } else if !connectedNavigators.isEmpty {
            let navigatorSection = connectedAnchors.isEmpty ? 0 : 1
            if indexPath.section == navigatorSection {
                let navigator = connectedNavigators[indexPath.row]
                cell.configure(with: navigator)
            }
        }
        
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
    
    func configureForAnchor(with anchor: AnchorViewController.AnchorInfo) {
        var displayName = anchor.displayName
        if let destination = anchor.destination {
            displayName += " (\(destination.displayName))"
        }
        nameLabel.text = displayName
        
        switch anchor.connectionState {
        case .connected:
            statusIndicator.backgroundColor = .systemOrange
            distanceLabel.text = "Connected - Waiting for tracking..."
        case .tracking:
            statusIndicator.backgroundColor = .systemGreen
            if let distance = anchor.distance {
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