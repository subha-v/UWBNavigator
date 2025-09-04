/*
See LICENSE folder for this sample's licensing information.

Abstract:
View controller for navigator phones with arrow-based navigation display.
*/

import UIKit
import NearbyInteraction
import MultipeerConnectivity
import Firebase

class NavigatorViewController: UIViewController, NISessionDelegate {
    
    // MARK: - UI Components
    private let arrowView: ArrowView = {
        let view = ArrowView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let anchorNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 24, weight: .semibold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Connecting..."
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = .systemGray
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let detailContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemBackground
        view.layer.cornerRadius = 12
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowOpacity = 0.1
        view.layer.shadowRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let distanceLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 20, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let azimuthLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .regular)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let elevationLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .regular)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let directionIndicatorStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .equalSpacing
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let leftArrowImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "arrow.left"))
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let upArrowImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "arrow.up"))
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let downArrowImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "arrow.down"))
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let rightArrowImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "arrow.right"))
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let disconnectButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Disconnect", for: .normal)
        button.setTitleColor(.systemRed, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - NearbyInteraction Properties
    private var sessions: [MCPeerID: NISession] = [:]
    private var peerTokens: [MCPeerID: NIDiscoveryToken] = [:]
    private var mpc: MPCSession?
    private var connectedAnchors: [MCPeerID] = []
    private var anchorDistances: [MCPeerID: Float] = [:]
    private var primaryAnchor: MCPeerID?
    private let nearbyDistanceThreshold: Float = 0.3
    private var measurementTimer: Timer?
    private var batteryTimer: Timer?
    
    // MARK: - Navigation Properties
    var selectedAnchorId: String?
    var selectedAnchorName: String?
    
    // MARK: - Distance and Direction State
    enum DistanceDirectionState {
        case closeUpInFOV, notCloseUpInFOV, outOfFOV, unknown
    }
    private var currentDistanceDirectionState: DistanceDirectionState = .unknown
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
        startNavigatorMode()
        startBatteryMonitoring()
        
        // Only initialize API data if actually in navigator role
        if UserSession.shared.userRole == .navigator {
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
        
        // Perform thorough cleanup when leaving this view
        cleanupSession()
        
        // Clear API data when leaving navigator mode
        APIServer.shared.clearNavigatorData()
    }
    
    deinit {
        // Ensure cleanup happens even if view lifecycle methods aren't called properly
        cleanupSession()
        APIServer.shared.clearNavigatorData()
        print("NavigatorViewController deallocated")
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        navigationItem.title = "Navigator"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Back", style: .plain, target: self, action: #selector(backTapped))
        
        anchorNameLabel.text = selectedAnchorName ?? "Unknown Anchor"
        
        // Add subviews
        view.addSubview(anchorNameLabel)
        view.addSubview(statusLabel)
        view.addSubview(arrowView)
        view.addSubview(detailContainer)
        view.addSubview(disconnectButton)
        
        // Setup detail container subviews
        detailContainer.addSubview(distanceLabel)
        detailContainer.addSubview(azimuthLabel)
        detailContainer.addSubview(elevationLabel)
        detailContainer.addSubview(directionIndicatorStack)
        
        directionIndicatorStack.addArrangedSubview(leftArrowImageView)
        directionIndicatorStack.addArrangedSubview(upArrowImageView)
        directionIndicatorStack.addArrangedSubview(downArrowImageView)
        directionIndicatorStack.addArrangedSubview(rightArrowImageView)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Anchor name
            anchorNameLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            anchorNameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            anchorNameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Status
            statusLabel.topAnchor.constraint(equalTo: anchorNameLabel.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Arrow View
            arrowView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            arrowView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            arrowView.widthAnchor.constraint(equalToConstant: 200),
            arrowView.heightAnchor.constraint(equalToConstant: 200),
            
            // Detail Container
            detailContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            detailContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            detailContainer.topAnchor.constraint(equalTo: arrowView.bottomAnchor, constant: 40),
            detailContainer.heightAnchor.constraint(equalToConstant: 140),
            
            // Distance Label
            distanceLabel.topAnchor.constraint(equalTo: detailContainer.topAnchor, constant: 15),
            distanceLabel.centerXAnchor.constraint(equalTo: detailContainer.centerXAnchor),
            
            // Azimuth Label
            azimuthLabel.topAnchor.constraint(equalTo: distanceLabel.bottomAnchor, constant: 10),
            azimuthLabel.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor, constant: 20),
            
            // Elevation Label
            elevationLabel.topAnchor.constraint(equalTo: distanceLabel.bottomAnchor, constant: 10),
            elevationLabel.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor, constant: -20),
            
            // Direction Indicators
            directionIndicatorStack.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor, constant: -15),
            directionIndicatorStack.centerXAnchor.constraint(equalTo: detailContainer.centerXAnchor),
            directionIndicatorStack.widthAnchor.constraint(equalToConstant: 160),
            directionIndicatorStack.heightAnchor.constraint(equalToConstant: 30),
            
            // Arrow sizes
            leftArrowImageView.widthAnchor.constraint(equalToConstant: 30),
            rightArrowImageView.widthAnchor.constraint(equalToConstant: 30),
            upArrowImageView.widthAnchor.constraint(equalToConstant: 30),
            downArrowImageView.widthAnchor.constraint(equalToConstant: 30),
            
            // Disconnect Button
            disconnectButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            disconnectButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        
        // Initially hide detail container
        detailContainer.alpha = 0
    }
    
    private func setupActions() {
        disconnectButton.addTarget(self, action: #selector(disconnectTapped), for: .touchUpInside)
    }
    
    // MARK: - Navigator Mode
    private func startNavigatorMode() {
        // Add a small delay to ensure any previous MPC sessions are fully terminated
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            // Initialize MultipeerConnectivity with navigator role - connect to multiple anchors
            #if targetEnvironment(simulator)
            self.mpc = MPCSession(service: "nisample", identity: "navigator-simulator", maxPeers: 10)
            #else
            let uniqueId = "navigator-\(UserSession.shared.userId ?? "unknown")-\(Date().timeIntervalSince1970)"
            self.mpc = MPCSession(service: "nisample", identity: uniqueId, maxPeers: 10)
            #endif
            
            self.mpc?.peerConnectedHandler = { [weak self] peer in
                self?.handleAnchorConnected(peer)
            }
            
            self.mpc?.peerDataHandler = { [weak self] data, peer in
                self?.handleDataReceived(data: data, from: peer)
            }
            
            self.mpc?.peerDisconnectedHandler = { [weak self] peer in
                self?.handleAnchorDisconnected(peer)
            }
            
            self.mpc?.start()
            self.updateStatus("Searching for anchor...")
        }
    }
    
    // MARK: - Anchor Connection Management
    private func handleAnchorConnected(_ peer: MCPeerID) {
        // Accept connection from any anchor for multi-anchor tracking
        DispatchQueue.main.async { [weak self] in
            // Create new NISession for this anchor
            let session = NISession()
            session.delegate = self
            self?.sessions[peer] = session
            
            // Check if this is the primary selected anchor
            if let anchorId = self?.selectedAnchorId,
               peer.displayName == "anchor-\(anchorId)" {
                self?.primaryAnchor = peer
                self?.updateStatus("Connected to primary anchor")
            } else {
                self?.updateStatus("Connected to \(self?.connectedAnchors.count ?? 0) anchors")
            }
            
            self?.connectedAnchors.append(peer)
            
            // Share discovery token
            if let discoveryToken = session.discoveryToken {
                self?.shareDiscoveryToken(discoveryToken, with: peer)
            }
            
            // Start tracking session if needed
            self?.startTrackingSessionIfNeeded()
        }
    }
    
    private func handleAnchorDisconnected(_ peer: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            // Clean up session for this anchor
            self?.sessions[peer]?.invalidate()
            self?.sessions.removeValue(forKey: peer)
            self?.peerTokens.removeValue(forKey: peer)
            self?.anchorDistances.removeValue(forKey: peer)
            
            if let index = self?.connectedAnchors.firstIndex(of: peer) {
                self?.connectedAnchors.remove(at: index)
            }
            
            // Check if this was the primary anchor
            if self?.primaryAnchor == peer {
                self?.primaryAnchor = nil
                self?.currentDistanceDirectionState = .unknown
                self?.updateStatus("Disconnected from primary anchor")
                self?.updateVisualization(state: .unknown, nearbyObject: nil)
            }
            
            // Update status
            if self?.connectedAnchors.isEmpty == true {
                self?.updateStatus("Searching for anchors...")
                self?.measurementTimer?.invalidate()
                self?.measurementTimer = nil
                DistanceErrorTracker.shared.endSession()
            } else {
                self?.updateStatus("Connected to \(self?.connectedAnchors.count ?? 0) anchors")
            }
        }
    }
    
    private func handleDataReceived(data: Data, from peer: MCPeerID) {
        guard let discoveryToken = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.peerTokens[peer] = discoveryToken
            
            // Start tracking with this anchor
            if let session = self?.sessions[peer] {
                let config = NINearbyPeerConfiguration(peerToken: discoveryToken)
                session.run(config)
                
                if peer == self?.primaryAnchor {
                    self?.updateStatus("Tracking primary anchor")
                } else {
                    self?.updateStatus("Tracking \(self?.connectedAnchors.count ?? 0) anchors")
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
    
    private func startTrackingSessionIfNeeded() {
        // Start tracking session if we have multiple anchors
        guard connectedAnchors.count >= 2,
              measurementTimer == nil else { return }
        
        // Fetch destinations for all connected anchors
        var participants: [String: AnchorDestination] = [:]
        
        // Add navigator (no destination)
        if let userId = UserSession.shared.userId {
            DistanceErrorTracker.shared.registerDevice(userId, destination: nil)
        }
        
        // Add anchors with their destinations
        for anchor in connectedAnchors {
            let components = anchor.displayName.components(separatedBy: "-")
            if components.count >= 2 {
                let anchorUserId = components[1]
                
                // Fetch destination for this anchor
                FirebaseManager.shared.fetchUserDestination(userId: anchorUserId) { result in
                    if case .success(let destStr) = result,
                       let destString = destStr,
                       let destination = AnchorDestination(rawValue: destString) {
                        participants[anchorUserId] = destination
                        DistanceErrorTracker.shared.registerDevice(anchorUserId, destination: destination)
                        
                        // Start session if we have enough participants
                        if participants.count >= 2 {
                            DistanceErrorTracker.shared.startSession(participants: participants)
                        }
                    }
                }
            }
        }
        
        startMeasurementTimer()
    }
    
    private func startMeasurementTimer() {
        measurementTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateDistanceTracking()
        }
    }
    
    private func updateDistanceTracking() {
        guard let userId = UserSession.shared.userId else { return }
        
        // Update distances for all connected anchors
        for (peer, distance) in anchorDistances {
            let components = peer.displayName.components(separatedBy: "-")
            if components.count >= 2 {
                DistanceErrorTracker.shared.updateDistance(from: userId, to: components[1], distance: distance)
            }
        }
    }
    
    // MARK: - NISessionDelegate
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        // Find which peer this session belongs to
        guard let peer = sessions.first(where: { $0.value === session })?.key,
              let peerToken = peerTokens[peer] else {
            return
        }
        
        // Find the anchor object for this peer
        guard let anchorObject = nearbyObjects.first(where: { $0.discoveryToken == peerToken }) else {
            return
        }
        
        // Update distance for this anchor
        DispatchQueue.main.async { [weak self] in
            self?.anchorDistances[peer] = anchorObject.distance
            
            // If this is the primary anchor, update visualization
            if peer == self?.primaryAnchor {
                let nextState = self?.getDistanceDirectionState(from: anchorObject) ?? .unknown
                self?.updateVisualization(from: self?.currentDistanceDirectionState ?? .unknown,
                                         to: nextState,
                                         with: anchorObject)
                self?.currentDistanceDirectionState = nextState
            }
            
            // Update multi-anchor display if needed
            self?.updateMultiAnchorDisplay()
            
            // Update API server with current data
            self?.updateAPIData()
        }
    }
    
    // MARK: - API Data Update
    private func updateAPIData() {
        // Only update if user is actually in navigator role
        guard UserSession.shared.userRole == .navigator else { 
            APIServer.shared.clearNavigatorData()
            return 
        }
        
        var distances: [String: Float] = [:]
        for (peer, distance) in anchorDistances {
            let anchorName = peer.displayName.replacingOccurrences(of: "anchor-", with: "")
            distances[anchorName] = distance
        }
        
        let navigatorData = [[
            "id": UserSession.shared.userId ?? "unknown",
            "name": UserSession.shared.displayName ?? UIDevice.current.name,
            "targetAnchor": selectedAnchorName ?? "none",
            "battery": Int(UIDevice.current.batteryLevel * 100),
            "status": connectedAnchors.isEmpty ? "idle" : "active",
            "connectedAnchors": connectedAnchors.count,
            "distances": distances
        ] as [String : Any]]
        
        APIServer.shared.updateNavigatorData(navigatorData)
    }
    
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        // Find which peer this session belongs to
        guard let peer = sessions.first(where: { $0.value === session })?.key,
              let peerToken = peerTokens[peer] else {
            return
        }
        
        if nearbyObjects.contains(where: { $0.discoveryToken == peerToken }) {
            // Remove distance for this anchor
            anchorDistances.removeValue(forKey: peer)
            
            if peer == primaryAnchor {
                currentDistanceDirectionState = .unknown
            }
            
            switch reason {
            case .peerEnded:
                // Handle in disconnected handler
                break
            case .timeout:
                if let config = session.configuration {
                    session.run(config)
                }
                updateStatus("Connection timeout - retrying")
            default:
                break
            }
        }
    }
    
    func sessionWasSuspended(_ session: NISession) {
        currentDistanceDirectionState = .unknown
        updateStatus("Session suspended")
    }
    
    func sessionSuspensionEnded(_ session: NISession) {
        if let config = session.configuration {
            session.run(config)
            updateStatus("Session resumed")
        }
    }
    
    func session(_ session: NISession, didInvalidateWith error: Error) {
        currentDistanceDirectionState = .unknown
        
        if case NIError.userDidNotAllow = error {
            updateStatus("Nearby Interaction access required")
        } else {
            startNavigatorMode()
        }
    }
    
    // MARK: - Visualization
    private func getDistanceDirectionState(from nearbyObject: NINearbyObject) -> DistanceDirectionState {
        if nearbyObject.distance == nil && nearbyObject.direction == nil {
            return .unknown
        }
        
        let isNearby = nearbyObject.distance.map { $0 < nearbyDistanceThreshold } ?? false
        let directionAvailable = nearbyObject.direction != nil
        
        if isNearby && directionAvailable {
            return .closeUpInFOV
        } else if !isNearby && directionAvailable {
            return .notCloseUpInFOV
        } else {
            return .outOfFOV
        }
    }
    
    private func updateVisualization(from currentState: DistanceDirectionState? = nil,
                                    to nextState: DistanceDirectionState? = nil,
                                    with nearbyObject: NINearbyObject?) {
        let state = nextState ?? currentState ?? .unknown
        updateVisualization(state: state, nearbyObject: nearbyObject)
    }
    
    private func updateVisualization(state: DistanceDirectionState, nearbyObject: NINearbyObject?) {
        // Update arrow state
        arrowView.setDistanceState(distance: nearbyObject?.distance, isInFOV: state != .outOfFOV && state != .unknown)
        
        // Update arrow direction
        if let direction = nearbyObject?.direction {
            let azimuth = azimuth(from: direction)
            arrowView.updateDirection(azimuth: azimuth, animated: true)
            updateDirectionIndicators(azimuth: azimuth, elevation: elevation(from: direction))
        }
        
        // Show/hide detail container
        UIView.animate(withDuration: 0.3) {
            self.detailContainer.alpha = (state == .unknown || state == .outOfFOV) ? 0 : 1
        }
        
        // Update distance label
        if let distance = nearbyObject?.distance {
            distanceLabel.text = String(format: "%.2f meters", distance)
            
            // Change color based on distance
            if distance < nearbyDistanceThreshold {
                distanceLabel.textColor = .systemGreen
            } else if distance < 1.0 {
                distanceLabel.textColor = .systemBlue
            } else {
                distanceLabel.textColor = .label
            }
        } else {
            distanceLabel.text = "-- meters"
            distanceLabel.textColor = .systemGray
        }
        
        // Update azimuth and elevation labels
        if let direction = nearbyObject?.direction {
            let azimuthDegrees = azimuth(from: direction).radiansToDegrees
            let elevationDegrees = elevation(from: direction).radiansToDegrees
            
            azimuthLabel.text = String(format: "Azimuth: %3.0f°", azimuthDegrees)
            elevationLabel.text = String(format: "Elevation: %3.0f°", elevationDegrees)
        } else {
            azimuthLabel.text = "Azimuth: --°"
            elevationLabel.text = "Elevation: --°"
        }
        
        // Trigger haptic feedback when close
        if state == .closeUpInFOV && currentDistanceDirectionState != .closeUpInFOV {
            arrowView.triggerHapticFeedback()
        }
    }
    
    private func updateDirectionIndicators(azimuth: Float, elevation: Float) {
        let azimuthDegrees = azimuth.radiansToDegrees
        let elevationDegrees = elevation.radiansToDegrees
        let threshold: Float = 15.0
        
        // Update horizontal indicators
        if abs(azimuthDegrees) <= threshold {
            leftArrowImageView.tintColor = .systemGray3
            rightArrowImageView.tintColor = .systemGray3
        } else if azimuthDegrees < 0 {
            leftArrowImageView.tintColor = .systemBlue
            rightArrowImageView.tintColor = .systemGray3
        } else {
            leftArrowImageView.tintColor = .systemGray3
            rightArrowImageView.tintColor = .systemBlue
        }
        
        // Update vertical indicators
        if abs(elevationDegrees) <= threshold {
            upArrowImageView.tintColor = .systemGray3
            downArrowImageView.tintColor = .systemGray3
        } else if elevationDegrees > 0 {
            upArrowImageView.tintColor = .systemBlue
            downArrowImageView.tintColor = .systemGray3
        } else {
            upArrowImageView.tintColor = .systemGray3
            downArrowImageView.tintColor = .systemBlue
        }
    }
    
    // MARK: - Helper Methods
    private func updateStatus(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = text
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
        
        // Update QoD score based on connected anchors
        let hasAllAnchors = connectedAnchors.count >= 3
        FirebaseManager.shared.updateQoDScore(userId: userId, score: hasAllAnchors ? 90 : nil)
    }
    
    private func updatePresence(isOnline: Bool) {
        if let userId = UserSession.shared.userId {
            FirebaseManager.shared.updateUserPresence(userId: userId, isOnline: isOnline)
        }
    }
    
    private func cleanupSession() {
        measurementTimer?.invalidate()
        measurementTimer = nil
        
        batteryTimer?.invalidate()
        batteryTimer = nil
        
        DistanceErrorTracker.shared.endSession()
        
        // Clear all NI sessions
        sessions.values.forEach { $0.invalidate() }
        sessions.removeAll()
        
        // Reset anchor tracking state
        connectedAnchors.removeAll()
        anchorDistances.removeAll()
        selectedAnchorId = nil
        selectedAnchorName = nil
        
        // Invalidate MPC session
        mpc?.invalidate()
        mpc = nil
        
        // Reset UI
        updateStatus("Disconnected")
        updateDistance(nil)
        
        // Clear API data
        updateAPIData()
    }
    
    private func updateMultiAnchorDisplay() {
        // Update UI to show distances to all anchors
        var statusText = "Tracking: "
        var distanceTexts: [String] = []
        
        for (peer, distance) in anchorDistances {
            let components = peer.displayName.components(separatedBy: "-")
            if components.count >= 2 {
                let anchorId = components[1]
                distanceTexts.append("\(anchorId): \(String(format: "%.2fm", distance))")
            }
        }
        
        if !distanceTexts.isEmpty {
            statusText += distanceTexts.joined(separator: ", ")
            // You could update a secondary label here to show all distances
        }
    }
    
    // MARK: - Actions
    @objc private func backTapped() {
        cleanupSession()
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func disconnectTapped() {
        let alert = UIAlertController(title: "Disconnect", message: "Are you sure you want to disconnect from this anchor?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Disconnect", style: .destructive) { [weak self] _ in
            self?.cleanupSession()
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }
}