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
    private var anchorSession: NISession?  // Single session for the other anchor
    private var navigatorSessions: [MCPeerID: NISession] = [:]  // Sessions for each navigator
    
    // Token tracking
    private var anchorToken: NIDiscoveryToken?  // Token from the other anchor
    private var anchorPeer: MCPeerID?  // The other anchor's peer ID
    private var navigatorTokens: [MCPeerID: NIDiscoveryToken] = [:]
    
    // Connected devices
    private var connectedNavigators: [NavigatorInfo] = []
    private var connectedAnchor: AnchorInfo?  // Info about the other anchor (if connected)
    
    // Other properties
    private var batteryTimer: Timer?
    private var mpc: MPCSession?
    private var anchorDestination: AnchorDestination?
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
            
            // Only maintain one anchor-to-anchor connection at a time
            if self.anchorPeer != nil {
                print("Already connected to another anchor, ignoring: \(peer.displayName)")
                return
            }
            
            // Create single NISession for anchor-to-anchor communication
            let session = NISession()
            session.delegate = self
            self.anchorSession = session
            self.anchorPeer = peer
            
            // Extract anchor info
            let displayComponents = peer.displayName.components(separatedBy: "-")
            let anchorUserId = displayComponents.count >= 2 ? displayComponents[1] : ""
            let anchorName = "Other Anchor"
            
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
                    self?.connectedAnchor = anchor
                    
                    // Share discovery token with the other anchor
                    if let discoveryToken = session.discoveryToken {
                        self?.shareDiscoveryToken(discoveryToken, with: peer)
                    }
                    
                    self?.updateStatus()
                    self?.tableView.reloadData()
                    
                    // Start distance tracking session for ground truth
                    self?.startAnchorTrackingSession()
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
            
            // Only handle if this was our connected anchor
            if self.anchorPeer == peer {
                // Clean up anchor session
                self.anchorSession?.invalidate()
                self.anchorSession = nil
                self.anchorPeer = nil
                self.anchorToken = nil
                self.connectedAnchor = nil
                
                // Stop anchor tracking session
                DistanceErrorTracker.shared.endSession()
                
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
                if self.anchorPeer == peer {
                    self.anchorToken = discoveryToken
                    
                    // Start tracking with the other anchor
                    if let session = self.anchorSession {
                        let config = NINearbyPeerConfiguration(peerToken: discoveryToken)
                        session.run(config)
                        
                        // Update anchor state
                        self.connectedAnchor?.connectionState = .tracking
                        self.tableView.reloadData()
                    }
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
              let otherAnchor = connectedAnchor,
              let otherDestination = otherAnchor.destination,
              let myUserId = UserSession.shared.userId else {
            return
        }
        
        // Start distance tracking session between the two anchors
        var participants: [String: AnchorDestination] = [:]
        participants[myUserId] = myDestination
        participants[otherAnchor.userId] = otherDestination
        
        DistanceErrorTracker.shared.startSession(participants: participants)
        
        // Start measurement timer if not already running
        if measurementTimer == nil {
            measurementTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.updateAnchorDistanceTracking()
            }
        }
    }
    
    private func updateAnchorDistanceTracking() {
        guard let otherAnchor = connectedAnchor,
              let distance = otherAnchor.distance,
              let myUserId = UserSession.shared.userId else {
            return
        }
        
        // Update distance tracker with anchor-to-anchor distance
        DistanceErrorTracker.shared.updateDistance(
            from: myUserId,
            to: otherAnchor.userId,
            distance: distance
        )
    }
    
    // MARK: - Helper Methods
    private func updateStatus() {
        var statusText = ""
        
        // Show anchor connection status
        if let otherAnchor = connectedAnchor {
            if otherAnchor.connectionState == .tracking {
                let destName = otherAnchor.destination?.displayName ?? "Unknown"
                if let distance = otherAnchor.distance {
                    statusText = "Connected to \(destName) anchor: \(String(format: "%.2f", distance))m"
                } else {
                    statusText = "Connected to \(destName) anchor"
                }
            } else {
                statusText = "Connecting to other anchor..."
            }
        } else {
            statusText = "No other anchor connected"
        }
        
        // Add navigator count
        if connectedNavigators.count > 0 {
            statusText += " | \(connectedNavigators.count) navigator\(connectedNavigators.count == 1 ? "" : "s")"
        }
        
        statusLabel.text = statusText
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
        if measurementTimer != nil && connectedAnchor != nil {
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
        anchorSession?.invalidate()
        anchorSession = nil
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
            
            // Check if this is the anchor session
            if session === self.anchorSession {
                // Handle anchor-to-anchor distance update
                if let anchorToken = self.anchorToken,
                   let nearbyObject = nearbyObjects.first(where: { $0.discoveryToken == anchorToken }) {
                    
                    // Update anchor distance
                    self.connectedAnchor?.distance = nearbyObject.distance
                    self.connectedAnchor?.direction = nearbyObject.direction
                    self.connectedAnchor?.lastUpdate = Date()
                    
                    // Update distance tracking for ground truth
                    self.updateAnchorDistanceTracking()
                    
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
        if connectedAnchor != nil { sections += 1 }
        if !connectedNavigators.isEmpty { sections += 1 }
        return max(1, sections) // At least 1 section for empty state
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if connectedAnchor != nil && section == 0 {
            return 1  // Only one anchor connection at a time
        } else if !connectedNavigators.isEmpty {
            let navigatorSection = (connectedAnchor != nil) ? 1 : 0
            if section == navigatorSection {
                return connectedNavigators.count
            }
        }
        return 0
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if connectedAnchor != nil && section == 0 {
            return "Connected Anchor"
        } else if !connectedNavigators.isEmpty {
            let navigatorSection = (connectedAnchor != nil) ? 1 : 0
            if section == navigatorSection {
                return "Connected Navigators"
            }
        }
        return nil
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "NavigatorCell", for: indexPath) as! NavigatorTableViewCell
        
        if let anchor = connectedAnchor, indexPath.section == 0 {
            cell.configureForAnchor(with: anchor)
        } else if !connectedNavigators.isEmpty {
            let navigatorSection = (connectedAnchor != nil) ? 1 : 0
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