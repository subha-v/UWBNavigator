/*
See LICENSE folder for this sample's licensing information.

Abstract:
View controller for navigator phones with arrow-based navigation display.
*/

import UIKit
import NearbyInteraction
import MultipeerConnectivity
import Firebase

class NavigatorViewController: UIViewController, NISessionDelegate, NetServiceBrowserDelegate, NetServiceDelegate {
    
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

    private let reachedDestinationButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Reached Destination", for: .normal)
        button.backgroundColor = .systemGreen
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        button.layer.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
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

    // MARK: - Server Discovery
    // Use your Mac's IP address for testing (update this when your IP changes)
    private var fastAPIServerURL: String = "http://10.1.10.206:8000"
    private var serviceBrowser: NetServiceBrowser?
    private var fastAPIService: NetService?
    
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
        discoverFastAPIServer()

        // Only initialize API data if actually in navigator role
        if UserSession.shared.userRole == .navigator {
            updateAPIData()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePresence(isOnline: true)
        // Update API data when view appears to ensure navigator shows up on webapp
        updateAPIData()
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
        view.addSubview(reachedDestinationButton)
        
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
            disconnectButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // Reached Destination Button
            reachedDestinationButton.bottomAnchor.constraint(equalTo: disconnectButton.topAnchor, constant: -20),
            reachedDestinationButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            reachedDestinationButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            reachedDestinationButton.heightAnchor.constraint(equalToConstant: 50)
        ])

        // Initially hide detail container
        detailContainer.alpha = 0
    }
    
    private func setupActions() {
        disconnectButton.addTarget(self, action: #selector(disconnectTapped), for: .touchUpInside)
        reachedDestinationButton.addTarget(self, action: #selector(reachedDestinationTapped), for: .touchUpInside)
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Extract anchor ID from peer display name (format: "anchor-{userId}")
            let peerAnchorId = peer.displayName.replacingOccurrences(of: "anchor-", with: "")
            
            // Only accept connection from the selected anchor
            if let selectedId = self.selectedAnchorId {
                if peerAnchorId != selectedId {
                    print("Ignoring connection from non-selected anchor: \(peer.displayName)")
                    // Reject this connection as it's not the one we want
                    return
                }
            }
            
            // Check if we already have a session for this peer
            if self.sessions[peer] != nil {
                print("Session already exists for peer: \(peer.displayName)")
                return
            }
            
            // Create new NISession for this anchor
            let session = NISession()
            session.delegate = self
            self.sessions[peer] = session
            
            // This is our primary selected anchor
            self.primaryAnchor = peer
            self.connectedAnchors.append(peer)
            self.updateStatus("Connected to \(self.selectedAnchorName ?? "anchor")")
            
            // Share discovery token
            if let discoveryToken = session.discoveryToken {
                self.shareDiscoveryToken(discoveryToken, with: peer)
            }
            
            // Start tracking session if needed
            self.startTrackingSessionIfNeeded()
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
            guard let self = self else { return }
            
            // Only accept tokens from our selected anchor
            let peerAnchorId = peer.displayName.replacingOccurrences(of: "anchor-", with: "")
            if let selectedId = self.selectedAnchorId, peerAnchorId != selectedId {
                print("Ignoring discovery token from non-selected anchor: \(peer.displayName)")
                return
            }
            
            // Store the token for this peer
            self.peerTokens[peer] = discoveryToken
            
            // Start tracking with this anchor
            if let session = self.sessions[peer] {
                let config = NINearbyPeerConfiguration(peerToken: discoveryToken)
                session.run(config)
                
                if peer == self.primaryAnchor {
                    self.updateStatus("Tracking \(self.selectedAnchorName ?? "anchor")")
                } else {
                    self.updateStatus("Tracking \(self.connectedAnchors.count) anchors")
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

        let navigatorData = NavigatorAPIDataBuilder.buildData(
            selectedAnchorName: selectedAnchorName,
            connectedAnchorCount: connectedAnchors.count,
            distances: distances
        )

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

        // Show/hide reached destination button when close
        UIView.animate(withDuration: 0.3) {
            self.reachedDestinationButton.isHidden = (state != .closeUpInFOV)
            self.reachedDestinationButton.alpha = (state == .closeUpInFOV) ? 1.0 : 0.0
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

        // Update API data to ensure navigator stays visible on webapp even when idle
        updateAPIData()
    }
    
    private func updatePresence(isOnline: Bool) {
        if let userId = UserSession.shared.userId {
            FirebaseManager.shared.updateNavigatorPresence(userId: userId, isOnline: isOnline)
        }
    }
    
    private func cleanupSession() {
        measurementTimer?.invalidate()
        measurementTimer = nil

        batteryTimer?.invalidate()
        batteryTimer = nil

        // Stop service discovery
        serviceBrowser?.stop()
        serviceBrowser = nil

        DistanceErrorTracker.shared.endSession()

        // Clear all NI sessions
        sessions.values.forEach { $0.invalidate() }
        sessions.removeAll()

        // Reset anchor tracking state
        connectedAnchors.removeAll()
        anchorDistances.removeAll()
        peerTokens.removeAll()
        primaryAnchor = nil
        currentDistanceDirectionState = .unknown
        // Important: Do NOT clear selectedAnchorId and selectedAnchorName here
        // They are set by the AnchorSelectionViewController and should persist

        // Invalidate MPC session
        mpc?.invalidate()
        mpc = nil

        // Reset UI
        updateStatus("Disconnected")
        updateVisualization(from: .unknown, to: .unknown, with: nil)

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

    @objc private func reachedDestinationTapped() {
        // Send completion notification directly without photo
        sendNavigatorCompletion()
    }

    // MARK: - Navigator Completion
    private func sendNavigatorCompletion() {
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Processing", message: "Sending completion notification...", preferredStyle: .alert)
        present(loadingAlert, animated: true)

        // Use discovered FastAPI server URL (or fallback to hardcoded IP)
        let apiUrl = "\(fastAPIServerURL)/api/navigator-completed"
        NSLog("📡 Using FastAPI server at: \(apiUrl)")
        NSLog("📱 Sending completion for navigator: \(UserSession.shared.displayName ?? "unknown")")
        NSLog("🎯 Target anchor: \(selectedAnchorName ?? "unknown")")

        guard let url = URL(string: apiUrl) else {
            loadingAlert.dismiss(animated: true)
            showError("Invalid server URL: \(apiUrl)")
            return
        }

        // Prepare JSON request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Create completion data
        let completionData: [String: Any] = [
            "navigator_id": UserSession.shared.userId ?? "unknown",
            "navigator_name": UserSession.shared.displayName ?? "unknown",
            "anchor_destination": selectedAnchorName ?? "unknown",
            "anchor_id": selectedAnchorId ?? "unknown",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        do {
            let body = try JSONSerialization.data(withJSONObject: completionData, options: [])
            request.httpBody = body
            NSLog("📱 Sending completion data: \(completionData)")
        } catch {
            loadingAlert.dismiss(animated: true) {
                self.showError("Failed to prepare data: \(error.localizedDescription)")
            }
            return
        }

        request.timeoutInterval = 30  // 30 second timeout

        NSLog("📱 Sending completion notification to: \(apiUrl)")

        // Create URL session with timeout configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)

        // Send request
        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    if let error = error {
                        NSLog("❌ Error sending completion: \(error.localizedDescription)")
                        self?.showError("Failed to send completion: \(error.localizedDescription)")
                        return
                    }

                    if let httpResponse = response as? HTTPURLResponse {
                        NSLog("📱 Server response status: \(httpResponse.statusCode)")
                        if httpResponse.statusCode != 200 {
                            if let data = data, let errorString = String(data: data, encoding: .utf8) {
                                NSLog("❌ Server error: \(errorString)")
                                self?.showError("Server error: \(errorString)")
                            } else {
                                self?.showError("Server error: Status \(httpResponse.statusCode)")
                            }
                            return
                        }
                    }

                    guard let data = data else {
                        NSLog("❌ No data received from server")
                        self?.showError("No response from server")
                        return
                    }

                    do {
                        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                        NSLog("✅ Server response: \(json ?? [:])")

                        if let success = json?["success"] as? Bool, success,
                           let contract = json?["contract"] as? [String: Any] {
                            NSLog("✅ Smart contract created: \(contract["txId"] ?? "unknown")")
                        }

                        // Show success message
                        let successAlert = UIAlertController(
                            title: "Destination Reached!",
                            message: "You have successfully reached \(self?.selectedAnchorName ?? "the destination"). A smart contract has been created.",
                            preferredStyle: .alert
                        )
                        successAlert.addAction(UIAlertAction(title: "Continue Navigating", style: .default) { _ in
                            // Hide the button and continue navigating (don't disconnect!)
                            self?.reachedDestinationButton.isHidden = true
                            self?.reachedDestinationButton.alpha = 0.0
                        })
                        successAlert.addAction(UIAlertAction(title: "Return to Selection", style: .cancel) { _ in
                            // Only disconnect if user chooses to return
                            self?.cleanupSession()
                            // Ensure we're on main thread for UI operations
                            DispatchQueue.main.async {
                                if let navController = self?.navigationController {
                                    navController.popViewController(animated: true)
                                } else {
                                    // If navigation controller is nil, try to dismiss
                                    self?.dismiss(animated: true)
                                }
                            }
                        })
                        self?.present(successAlert, animated: true)

                    } catch {
                        NSLog("❌ Failed to parse response: \(error)")
                        self?.showError("Failed to parse server response")
                    }
                }
            }
        }.resume()
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - FastAPI Server Discovery
    private func discoverFastAPIServer() {
        serviceBrowser = NetServiceBrowser()
        serviceBrowser?.delegate = self
        serviceBrowser?.searchForServices(ofType: "_uwbnav-fastapi._tcp.", inDomain: "local.")
        NSLog("🔍 Searching for FastAPI server via Bonjour...")
    }

    // MARK: - NetServiceBrowserDelegate
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        NSLog("📡 Found FastAPI service: \(service.name)")
        fastAPIService = service
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        NSLog("📴 Lost FastAPI service: \(service.name)")
        if service == fastAPIService {
            fastAPIService = nil
            fastAPIServerURL = "http://10.1.10.206:8000"  // Fallback
        }
    }

    // MARK: - NetServiceDelegate
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses, !addresses.isEmpty else { return }

        for addressData in addresses {
            let socketAddress = addressData.withUnsafeBytes { bytes in
                bytes.load(as: sockaddr_in.self)
            }

            if socketAddress.sin_family == AF_INET {
                let ipAddress = String(cString: inet_ntoa(socketAddress.sin_addr))
                let port = Int(socketAddress.sin_port.bigEndian)

                fastAPIServerURL = "http://\(ipAddress):\(port)"
                NSLog("✅ FastAPI server discovered at: \(fastAPIServerURL)")
                break
            }
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        NSLog("❌ Failed to resolve FastAPI service: \(errorDict)")
    }
}