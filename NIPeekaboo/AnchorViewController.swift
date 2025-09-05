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
        label.text = "Initializing..."
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = .systemGray
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Ground truth comparison view
    private let groundTruthView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGray6
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private let groundTruthLabel: UILabel = {
        let label = UILabel()
        label.text = "Ground Truth Comparison"
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let measuredDistanceLabel: UILabel = {
        let label = UILabel()
        label.text = "Measured: --"
        label.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let expectedDistanceLabel: UILabel = {
        let label = UILabel()
        label.text = "Expected: --"
        label.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let errorLabel: UILabel = {
        let label = UILabel()
        label.text = "Error: --"
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = .systemOrange
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
    // Separate sessions for anchors and navigators
    private var anchorSessions: [MCPeerID: NISession] = [:]  // Sessions for each anchor
    private var navigatorSessions: [MCPeerID: NISession] = [:]  // Sessions for each navigator
    
    // Ground truth distances (in meters)
    private let groundTruthDistances: [(dest1: AnchorDestination, dest2: AnchorDestination, distance: Float)] = [
        (.window, .kitchen, 10.287),  // 405 inches
        (.window, .meetingRoom, 5.587),  // 219.96 inches
        (.kitchen, .meetingRoom, 6.187)  // 243.588 inches
    ]
    
    // Token tracking
    private var anchorTokens: [MCPeerID: NIDiscoveryToken] = [:]  // Tokens from all anchors
    private var navigatorTokens: [MCPeerID: NIDiscoveryToken] = [:]
    
    // Connected devices
    private var connectedNavigators: [NavigatorInfo] = []
    private var connectedAnchors: [MCPeerID: AnchorInfo] = [:]  // Info about all connected anchors
    
    // Other properties
    private var batteryTimer: Timer?
    private var mpc: MPCSession?
    var anchorDestination: AnchorDestination?
    private var measurementTimer: Timer?
    
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
        let userId: String
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
        startBatteryMonitoring()
        
        // One-time update for existing anchor accounts
        checkAndUpdateDestinations()
        
        // Only initialize API data if actually in anchor role
        if UserSession.shared.userRole == .anchor {
            updateAPIData()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePresence(isOnline: true)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        updatePresence(isOnline: false)
        // Clear API data when leaving anchor mode
        APIServer.shared.clearAnchorData()
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
        view.addSubview(groundTruthView)
        view.addSubview(tableView)
        
        // Add subviews to ground truth view
        groundTruthView.addSubview(groundTruthLabel)
        groundTruthView.addSubview(measuredDistanceLabel)
        groundTruthView.addSubview(expectedDistanceLabel)
        groundTruthView.addSubview(errorLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            groundTruthView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 15),
            groundTruthView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            groundTruthView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            groundTruthView.heightAnchor.constraint(equalToConstant: 120),
            
            groundTruthLabel.topAnchor.constraint(equalTo: groundTruthView.topAnchor, constant: 12),
            groundTruthLabel.leadingAnchor.constraint(equalTo: groundTruthView.leadingAnchor, constant: 16),
            
            measuredDistanceLabel.topAnchor.constraint(equalTo: groundTruthLabel.bottomAnchor, constant: 8),
            measuredDistanceLabel.leadingAnchor.constraint(equalTo: groundTruthView.leadingAnchor, constant: 16),
            
            expectedDistanceLabel.topAnchor.constraint(equalTo: measuredDistanceLabel.bottomAnchor, constant: 4),
            expectedDistanceLabel.leadingAnchor.constraint(equalTo: groundTruthView.leadingAnchor, constant: 16),
            
            errorLabel.topAnchor.constraint(equalTo: expectedDistanceLabel.bottomAnchor, constant: 4),
            errorLabel.leadingAnchor.constraint(equalTo: groundTruthView.leadingAnchor, constant: 16),
            
            tableView.topAnchor.constraint(equalTo: groundTruthView.bottomAnchor, constant: 15),
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
        // Determine if peer is anchor or navigator based on displayName format
        let peerComponents = peer.displayName.components(separatedBy: "-")
        guard peerComponents.count >= 2 else { return }
        
        let peerRole = peerComponents[0]
        
        if peerRole == "anchor" {
            // Only maintain one anchor-to-anchor connection
            handleAnchorConnected(peer)
        } else if peerRole == "navigator" {
            handleNavigatorConnected(peer)
        }
    }
    
    private func handleAnchorConnected(_ peer: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Support multiple anchor connections
            if self.anchorSessions[peer] != nil {
                print("Already connected to anchor: \(peer.displayName)")
                return
            }
            
            print("✅ Connecting to anchor: \(peer.displayName)")
            
            // Create NISession for this anchor
            let session = NISession()
            session.delegate = self
            self.anchorSessions[peer] = session
            
            // Extract anchor info
            let displayComponents = peer.displayName.components(separatedBy: "-")
            let anchorUserId = displayComponents.count >= 2 ? displayComponents[1] : ""
            let anchorName = "Anchor: \(anchorUserId.prefix(8))"
            
            // Fetch destination for this anchor
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
                    userId: anchorUserId,
                    distance: nil,
                    direction: nil,
                    lastUpdate: Date(),
                    connectionState: .connected
                )
                
                DispatchQueue.main.async {
                    self?.connectedAnchors[peer] = anchor
                    
                    // Share discovery token with this anchor
                    if let discoveryToken = session.discoveryToken {
                        self?.shareDiscoveryToken(discoveryToken, with: peer)
                    }
                    
                    // Restart tracking session to include new anchor
                    self?.startAnchorTrackingSession()
                    
                    self?.updateStatus()
                    self?.tableView.reloadData()
                    
                    print("📍 Connected anchors count: \(self?.connectedAnchors.count ?? 0)")
                }
            }
        }
    }
    
    // MARK: - Navigator Management
    private func handleNavigatorConnected(_ peer: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Create separate NISession for each navigator
            let session = NISession()
            session.delegate = self
            self.navigatorSessions[peer] = session
            
            // Extract navigator info
            let displayComponents = peer.displayName.components(separatedBy: "-")
            let navigatorName = displayComponents.count >= 2 ? "Navigator" : peer.displayName
            
            let navigator = NavigatorInfo(
                peerId: peer,
                displayName: navigatorName,
                distance: nil,
                direction: nil,
                lastUpdate: Date(),
                connectionState: .connected
            )
            self.connectedNavigators.append(navigator)
            
            // Share discovery token with this navigator
            if let discoveryToken = session.discoveryToken {
                self.shareDiscoveryToken(discoveryToken, with: peer)
            }
            
            self.updateStatus()
            self.tableView.reloadData()
            
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
            guard let self = self else { return }
            
            // Clean up this anchor's session
            if let session = self.anchorSessions[peer] {
                session.invalidate()
                self.anchorSessions.removeValue(forKey: peer)
                self.anchorTokens.removeValue(forKey: peer)
                self.connectedAnchors.removeValue(forKey: peer)
                
                print("📴 Anchor disconnected: \(peer.displayName)")
                print("📍 Remaining anchors: \(self.anchorSessions.count)")
                
                self.updateStatus()
                self.tableView.reloadData()
            }
        }
    }
    
    private func handleNavigatorDisconnected(_ peer: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Clean up navigator session
            self.navigatorSessions[peer]?.invalidate()
            self.navigatorSessions.removeValue(forKey: peer)
            self.navigatorTokens.removeValue(forKey: peer)
            
            // Remove from connected navigators
            if let index = self.connectedNavigators.firstIndex(where: { $0.peerId == peer }) {
                self.connectedNavigators.remove(at: index)
                self.tableView.reloadData()
            }
            
            self.updateStatus()
            
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
            guard let self = self else { return }
            
            // Determine if this is from an anchor or navigator
            let peerComponents = peer.displayName.components(separatedBy: "-")
            guard peerComponents.count >= 2 else { return }
            
            let peerRole = peerComponents[0]
            
            if peerRole == "anchor" {
                // Handle anchor token
                self.anchorTokens[peer] = discoveryToken
                
                // Start tracking with this anchor
                if let session = self.anchorSessions[peer] {
                    let config = NINearbyPeerConfiguration(peerToken: discoveryToken)
                    session.run(config)
                    
                    // Update anchor state
                    if var anchor = self.connectedAnchors[peer] {
                        anchor.connectionState = .tracking
                        self.connectedAnchors[peer] = anchor
                    }
                    self.tableView.reloadData()
                    
                    print("🎯 Started tracking anchor: \(peer.displayName)")
                }
            } else if peerRole == "navigator" {
                // Handle navigator token
                self.navigatorTokens[peer] = discoveryToken
                
                // Start tracking with this navigator
                if let session = self.navigatorSessions[peer] {
                    let config = NINearbyPeerConfiguration(peerToken: discoveryToken)
                    session.run(config)
                    
                    // Update navigator state
                    if let index = self.connectedNavigators.firstIndex(where: { $0.peerId == peer }) {
                        self.connectedNavigators[index].connectionState = .tracking
                        self.tableView.reloadData()
                    }
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
    
    // MARK: - Anchor Tracking Session
    private func startAnchorTrackingSession() {
        guard let myDestination = anchorDestination,
              let myUserId = UserSession.shared.userId else {
            return
        }
        
        // Build participants map for ALL connected anchors
        var participants: [String: AnchorDestination] = [:]
        participants[myUserId] = myDestination
        
        // Add all connected anchors with destinations to the session
        for (_, anchor) in connectedAnchors {
            if let destination = anchor.destination {
                participants[anchor.userId] = destination
            }
        }
        
        // Only start session if we have at least 2 participants (self + at least one other anchor)
        if participants.count >= 2 {
            DistanceErrorTracker.shared.startSession(participants: participants)
            
            // Start measurement timer if not already running
            if measurementTimer == nil {
                measurementTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    self?.updateAnchorDistanceTracking()
                }
            }
            
            print("📍 Started anchor tracking session with \(participants.count) participants")
        }
    }
    
    private func updateAnchorDistanceTracking() {
        guard let myUserId = UserSession.shared.userId else { return }
        
        // Update distance tracker for ALL connected anchors
        for (_, anchor) in connectedAnchors {
            if let distance = anchor.distance {
                DistanceErrorTracker.shared.updateDistance(
                    from: myUserId,
                    to: anchor.userId,
                    distance: distance
                )
            }
        }
        
        // Update ground truth UI
        updateGroundTruthDisplay()
    }
    
    private func updateGroundTruthDisplay() {
        guard let myDestination = anchorDestination else {
            groundTruthView.isHidden = true
            return
        }
        
        // Calculate aggregate statistics for all connected anchors
        var totalMeasured = 0.0
        var totalExpected = 0.0
        var totalError = 0.0
        var anchorCount = 0
        
        for (_, anchor) in connectedAnchors {
            if let otherDestination = anchor.destination,
               let distance = anchor.distance,
               let expectedDistance = getGroundTruthDistance(from: myDestination, to: otherDestination) {
                totalMeasured += Double(distance)
                totalExpected += Double(expectedDistance)
                totalError += Double(abs(distance - expectedDistance))
                anchorCount += 1
            }
        }
        
        if anchorCount > 0 {
            // Show the ground truth view with aggregate stats
            groundTruthView.isHidden = false
            
            let avgMeasured = totalMeasured / Double(anchorCount)
            let avgExpected = totalExpected / Double(anchorCount)
            let avgError = totalError / Double(anchorCount)
            let avgPercentError = (avgError / avgExpected) * 100
            
            measuredDistanceLabel.text = String(format: "Avg Measured: %.2f m (\(anchorCount) anchors)", avgMeasured)
            expectedDistanceLabel.text = String(format: "Avg Expected: %.2f m", avgExpected)
            errorLabel.text = String(format: "Avg Error: %.2f m (%.1f%%)", avgError, avgPercentError)
            
            // Color code based on average error magnitude
            if avgPercentError < 5 {
                errorLabel.textColor = .systemGreen
            } else if avgPercentError < 10 {
                errorLabel.textColor = .systemOrange
            } else {
                errorLabel.textColor = .systemRed
            }
        } else {
            groundTruthView.isHidden = true
        }
    }
    
    func getGroundTruthDistance(from dest1: AnchorDestination, to dest2: AnchorDestination) -> Float? {
        for entry in groundTruthDistances {
            if (entry.dest1 == dest1 && entry.dest2 == dest2) ||
               (entry.dest1 == dest2 && entry.dest2 == dest1) {
                return entry.distance
            }
        }
        return nil
    }
    
    // MARK: - Helper Methods
    private func updateStatus() {
        var statusText = ""
        
        // Show anchor connection status
        if !connectedAnchors.isEmpty {
            let anchorCount = connectedAnchors.count
            let trackingCount = connectedAnchors.values.filter { $0.connectionState == .tracking }.count
            
            if trackingCount > 0 {
                statusText = "Connected to \(anchorCount) anchor\(anchorCount > 1 ? "s" : "")"
            } else {
                statusText = "Connecting to \(anchorCount) anchor\(anchorCount > 1 ? "s" : "")..."
            }
        } else {
            statusText = "No other anchor connected"
        }
        
        // Add navigator count
        if connectedNavigators.count > 0 {
            statusText += " | \(connectedNavigators.count) navigator\(connectedNavigators.count == 1 ? "" : "s")"
        }
        
        statusLabel.text = statusText
        
        // Update ground truth display
        updateGroundTruthDisplay()
    }
    
    // Old tracking methods removed - replaced with dual-session architecture
    
    private func updatePresence(isOnline: Bool) {
        if let userId = UserSession.shared.userId {
            FirebaseManager.shared.updateUserPresence(userId: userId, isOnline: isOnline)
        }
    }
    
    // MARK: - Battery Monitoring
    private func startBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        // Update immediately
        updateBatteryLevel()
        
        // Update every 30 seconds
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.updateBatteryLevel()
        }
    }
    
    private func updateBatteryLevel() {
        guard let userId = UserSession.shared.userId else { return }
        let batteryLevel = UIDevice.current.batteryLevel
        
        // Only update if battery level is valid (>= 0)
        if batteryLevel >= 0 {
            FirebaseManager.shared.updateBatteryLevel(userId: userId, batteryLevel: batteryLevel)
        }
        
        // Update QoD score if tracking session is active
        if measurementTimer != nil && !connectedAnchors.isEmpty {
            // QoD score when actively tracking another anchor
            FirebaseManager.shared.updateQoDScore(userId: userId, score: 85)
        } else {
            FirebaseManager.shared.updateQoDScore(userId: userId, score: nil)
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
        
        // Stop battery timer
        batteryTimer?.invalidate()
        batteryTimer = nil
        
        // End tracking session
        DistanceErrorTracker.shared.endSession()
        
        // Clean up sessions
        for (_, session) in anchorSessions {
            session.invalidate()
        }
        anchorSessions.removeAll()
        navigatorSessions.values.forEach { $0.invalidate() }
        navigatorSessions.removeAll()
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Check if this is an anchor session
            if let anchorPeer = self.anchorSessions.first(where: { $0.value === session })?.key {
                // Handle anchor-to-anchor distance update
                if let anchorToken = self.anchorTokens[anchorPeer],
                   let nearbyObject = nearbyObjects.first(where: { $0.discoveryToken == anchorToken }) {
                    
                    // Update anchor distance
                    if var anchor = self.connectedAnchors[anchorPeer] {
                        anchor.distance = nearbyObject.distance
                        anchor.direction = nearbyObject.direction
                        anchor.lastUpdate = Date()
                        self.connectedAnchors[anchorPeer] = anchor
                    }
                    
                    self.updateStatus()
                    self.tableView.reloadData()
                }
            } else {
                // Handle navigator session update
                if let navigatorPeer = self.navigatorSessions.first(where: { $0.value === session })?.key,
                   let navigatorToken = self.navigatorTokens[navigatorPeer],
                   let nearbyObject = nearbyObjects.first(where: { $0.discoveryToken == navigatorToken }) {
                    
                    // Update navigator info
                    if let index = self.connectedNavigators.firstIndex(where: { $0.peerId == navigatorPeer }) {
                        self.connectedNavigators[index].distance = nearbyObject.distance
                        self.connectedNavigators[index].direction = nearbyObject.direction
                        self.connectedNavigators[index].lastUpdate = Date()
                        
                        self.tableView.reloadData()
                    }
                }
            }
            
            // Update API server with current data
            self.updateAPIData()
        }
    }
    
    // MARK: - API Data Update
    private func updateAPIData() {
        // Only update if user is actually in anchor role
        guard UserSession.shared.userRole == .anchor else { 
            APIServer.shared.clearAnchorData()
            return 
        }
        
        // Prepare anchor-to-anchor data for all connected anchors
        var anchorConnections: [[String: Any]] = []
        
        if let myDestination = anchorDestination {
            for (_, anchor) in connectedAnchors {
                if let otherDestination = anchor.destination {
                    var connectionData: [String: Any] = [
                        "connectedTo": otherDestination.displayName,
                        "connectedToId": anchor.userId,
                        "peerId": anchor.peerId.displayName
                    ]
                    
                    if let distance = anchor.distance {
                        connectionData["measuredDistance"] = distance
                        
                        if let expectedDistance = getGroundTruthDistance(from: myDestination, to: otherDestination) {
                            connectionData["expectedDistance"] = expectedDistance
                            connectionData["distanceError"] = distance - expectedDistance
                            connectionData["percentError"] = ((distance - expectedDistance) / expectedDistance) * 100
                        }
                    }
                    
                    anchorConnections.append(connectionData)
                }
            }
        }
        
        // Navigator distances
        var navigatorDistances: [[String: Any]] = []
        for navigator in connectedNavigators {
            var navData: [String: Any] = [
                "id": navigator.peerId.displayName,
                "name": navigator.displayName
            ]
            if let distance = navigator.distance {
                navData["distance"] = distance
            }
            navigatorDistances.append(navData)
        }
        
        let anchorData = [[
            "id": UserSession.shared.userId ?? "unknown",
            "name": UserSession.shared.displayName ?? UIDevice.current.name,
            "destination": anchorDestination?.displayName ?? "unknown",
            "battery": Int(UIDevice.current.batteryLevel * 100),
            "status": connectedNavigators.isEmpty && connectedAnchors.isEmpty ? "idle" : "active",
            "connectedNavigators": connectedNavigators.count,
            "connectedAnchors": connectedAnchors.count,
            "navigatorDistances": navigatorDistances,
            "anchorConnections": anchorConnections
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
            return connectedAnchors.count  // Show ALL connected anchors
        } else if !connectedNavigators.isEmpty {
            let navigatorSection = (!connectedAnchors.isEmpty) ? 1 : 0
            if section == navigatorSection {
                return connectedNavigators.count
            }
        }
        return 0
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if !connectedAnchors.isEmpty && section == 0 {
            return "Connected Anchors (\(connectedAnchors.count))"
        } else if !connectedNavigators.isEmpty {
            let navigatorSection = (!connectedAnchors.isEmpty) ? 1 : 0
            if section == navigatorSection {
                return "Connected Navigators (\(connectedNavigators.count))"
            }
        }
        return nil
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "NavigatorCell", for: indexPath) as! NavigatorTableViewCell
        
        if !connectedAnchors.isEmpty && indexPath.section == 0 {
            // Show anchor at this index
            let anchorArray = Array(connectedAnchors.values)
            let anchor = anchorArray[indexPath.row]
            cell.configureForAnchor(with: anchor)
        } else if !connectedNavigators.isEmpty {
            let navigatorSection = (!connectedAnchors.isEmpty) ? 1 : 0
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
                var distanceText = String(format: "Distance: %.2f m", distance)
                
                // Add error information if we have ground truth data
                if let myVC = self.superview?.superview as? UITableView,
                   let anchorVC = myVC.dataSource as? AnchorViewController,
                   let myDestination = anchorVC.anchorDestination,
                   let otherDestination = anchor.destination,
                   let expectedDistance = anchorVC.getGroundTruthDistance(from: myDestination, to: otherDestination) {
                    let error = distance - expectedDistance
                    let percentError = (error / expectedDistance) * 100
                    distanceText += String(format: " (Error: %.1f%%)", percentError)
                    
                    // Color code based on error
                    if abs(percentError) < 5 {
                        distanceLabel.textColor = .systemGreen
                    } else if abs(percentError) < 10 {
                        distanceLabel.textColor = .systemOrange
                    } else {
                        distanceLabel.textColor = .systemRed
                    }
                } else {
                    distanceLabel.textColor = .systemGray
                }
                
                distanceLabel.text = distanceText
            } else {
                distanceLabel.text = "Tracking..."
                distanceLabel.textColor = .systemGray
            }
        case .disconnected:
            statusIndicator.backgroundColor = .systemRed
            distanceLabel.text = "Disconnected"
            distanceLabel.textColor = .systemGray
        }
    }
}