/*
See LICENSE folder for this sample's licensing information.

Abstract:
View controller for navigator phones with arrow-based navigation display.
*/

import UIKit
import NearbyInteraction
import MultipeerConnectivity

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
    private var session: NISession?
    private var peerDiscoveryToken: NIDiscoveryToken?
    private var mpc: MPCSession?
    private var connectedAnchor: MCPeerID?
    private var sharedTokenWithPeer = false
    private let nearbyDistanceThreshold: Float = 0.3
    
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
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cleanupSession()
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
        // Create NISession
        session = NISession()
        session?.delegate = self
        sharedTokenWithPeer = false
        
        // Initialize MultipeerConnectivity with navigator role
        #if targetEnvironment(simulator)
        mpc = MPCSession(service: "nisample", identity: "navigator-simulator", maxPeers: 1)
        #else
        mpc = MPCSession(service: "nisample", identity: "navigator-\(UserSession.shared.userId ?? "unknown")", maxPeers: 1)
        #endif
        
        mpc?.peerConnectedHandler = { [weak self] peer in
            self?.handleAnchorConnected(peer)
        }
        
        mpc?.peerDataHandler = { [weak self] data, peer in
            self?.handleDataReceived(data: data, from: peer)
        }
        
        mpc?.peerDisconnectedHandler = { [weak self] peer in
            self?.handleAnchorDisconnected(peer)
        }
        
        mpc?.start()
        updateStatus("Searching for anchor...")
    }
    
    // MARK: - Anchor Connection Management
    private func handleAnchorConnected(_ peer: MCPeerID) {
        // Check if this is the selected anchor
        // Peer display name format: "anchor-userId"
        guard let anchorId = selectedAnchorId,
              peer.displayName == "anchor-\(anchorId)" else {
            // Not the anchor we're looking for
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.connectedAnchor = peer
            self?.updateStatus("Connected to anchor")
            
            // Share discovery token
            if let myToken = self?.session?.discoveryToken {
                self?.shareDiscoveryToken(myToken, with: peer)
            }
        }
    }
    
    private func handleAnchorDisconnected(_ peer: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            if self?.connectedAnchor == peer {
                self?.connectedAnchor = nil
                self?.peerDiscoveryToken = nil
                self?.sharedTokenWithPeer = false
                self?.currentDistanceDirectionState = .unknown
                self?.updateStatus("Disconnected from anchor")
                self?.updateVisualization(state: .unknown, nearbyObject: nil)
                
                // Restart session
                self?.session?.invalidate()
                self?.startNavigatorMode()
            }
        }
    }
    
    private func handleDataReceived(data: Data, from peer: MCPeerID) {
        guard let discoveryToken = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.peerDiscoveryToken = discoveryToken
            
            // Start tracking with anchor
            let config = NINearbyPeerConfiguration(peerToken: discoveryToken)
            self?.session?.run(config)
            self?.updateStatus("Tracking anchor")
        }
    }
    
    private func shareDiscoveryToken(_ token: NIDiscoveryToken, with peer: MCPeerID) {
        guard let encodedData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            return
        }
        mpc?.sendData(data: encodedData, peers: [peer], mode: .reliable)
        sharedTokenWithPeer = true
    }
    
    // MARK: - NISessionDelegate
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let peerToken = peerDiscoveryToken else { return }
        
        // Find the anchor object
        guard let anchorObject = nearbyObjects.first(where: { $0.discoveryToken == peerToken }) else {
            return
        }
        
        // Update visualization
        let nextState = getDistanceDirectionState(from: anchorObject)
        DispatchQueue.main.async { [weak self] in
            self?.updateVisualization(from: self?.currentDistanceDirectionState ?? .unknown,
                                     to: nextState,
                                     with: anchorObject)
            self?.currentDistanceDirectionState = nextState
        }
    }
    
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        guard let peerToken = peerDiscoveryToken else { return }
        
        if nearbyObjects.contains(where: { $0.discoveryToken == peerToken }) {
            currentDistanceDirectionState = .unknown
            
            switch reason {
            case .peerEnded:
                peerDiscoveryToken = nil
                session.invalidate()
                startNavigatorMode()
                updateStatus("Anchor ended session")
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
    
    private func cleanupSession() {
        session?.invalidate()
        mpc?.invalidate()
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