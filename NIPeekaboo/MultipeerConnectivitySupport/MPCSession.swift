/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A class that manages peer discovery-token exchange over the local network by using MultipeerConnectivity.
*/

import Foundation
import MultipeerConnectivity

struct MPCSessionConstants {
    static let kKeyIdentity: String = "identity"
    static let kKeyRole: String = "role"
    static let kKeyUserId: String = "userId"
}

class MPCSession: NSObject, MCSessionDelegate, MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate {
    var peerDataHandler: ((Data, MCPeerID) -> Void)?
    var peerConnectedHandler: ((MCPeerID) -> Void)?
    var peerDisconnectedHandler: ((MCPeerID) -> Void)?
    private let serviceString: String
    private let mcSession: MCSession
    private let localPeerID: MCPeerID
    private let mcAdvertiser: MCNearbyServiceAdvertiser
    private let mcBrowser: MCNearbyServiceBrowser
    private let identityString: String
    private let maxNumPeers: Int
    private let userRole: String?
    private let userId: String?

    init(service: String, identity: String, maxPeers: Int) {
        serviceString = service
        identityString = identity
        maxNumPeers = maxPeers
        
        // Extract role and userId from identity if available
        // Identity format: "role-userId" (e.g., "anchor-abc123" or "navigator-xyz789")
        let components = identity.components(separatedBy: "-")
        if components.count >= 2 {
            userRole = components[0]
            userId = components[1]
            // Create peer ID with both role and userId for proper identification
            localPeerID = MCPeerID(displayName: "\(components[0])-\(components[1])")
        } else {
            userRole = nil
            userId = nil
            localPeerID = MCPeerID(displayName: UIDevice.current.name)
        }
        
        mcSession = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        
        // Include role information in discovery info
        var discoveryInfo = [MPCSessionConstants.kKeyIdentity: identityString]
        if let role = userRole {
            discoveryInfo[MPCSessionConstants.kKeyRole] = role
        }
        if let id = userId {
            discoveryInfo[MPCSessionConstants.kKeyUserId] = id
        }
        
        mcAdvertiser = MCNearbyServiceAdvertiser(peer: localPeerID,
                                                 discoveryInfo: discoveryInfo,
                                                 serviceType: serviceString)
        mcBrowser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: serviceString)

        super.init()
        mcSession.delegate = self
        mcAdvertiser.delegate = self
        mcBrowser.delegate = self
    }

    // MARK: - `MPCSession` public methods.
    func start() {
        mcAdvertiser.startAdvertisingPeer()
        mcBrowser.startBrowsingForPeers()
    }

    func suspend() {
        mcAdvertiser.stopAdvertisingPeer()
        mcBrowser.stopBrowsingForPeers()
    }

    func invalidate() {
        suspend()
        mcSession.disconnect()
    }

    func sendDataToAllPeers(data: Data) {
        sendData(data: data, peers: mcSession.connectedPeers, mode: .reliable)
    }

    func sendData(data: Data, peers: [MCPeerID], mode: MCSessionSendDataMode) {
        do {
            try mcSession.send(data, toPeers: peers, with: mode)
        } catch let error {
            NSLog("Error sending data: \(error)")
        }
    }

    // MARK: - `MPCSession` private methods.
    private func peerConnected(peerID: MCPeerID) {
        if let handler = peerConnectedHandler {
            DispatchQueue.main.async {
                handler(peerID)
            }
        }
        if mcSession.connectedPeers.count == maxNumPeers {
            self.suspend()
        }
    }

    private func peerDisconnected(peerID: MCPeerID) {
        if let handler = peerDisconnectedHandler {
            DispatchQueue.main.async {
                handler(peerID)
            }
        }

        if mcSession.connectedPeers.count < maxNumPeers {
            self.start()
        }
    }

    // MARK: - `MCSessionDelegate`.
    internal func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            peerConnected(peerID: peerID)
        case .notConnected:
            peerDisconnected(peerID: peerID)
        case .connecting:
            break
        @unknown default:
            fatalError("Unhandled MCSessionState")
        }
    }

    internal func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let handler = peerDataHandler {
            DispatchQueue.main.async {
                handler(data, peerID)
            }
        }
    }

    internal func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // The sample app intentional omits this implementation.
    }

    internal func session(_ session: MCSession,
                          didStartReceivingResourceWithName resourceName: String,
                          fromPeer peerID: MCPeerID,
                          with progress: Progress) {
        // The sample app intentional omits this implementation.
    }

    internal func session(_ session: MCSession,
                          didFinishReceivingResourceWithName resourceName: String,
                          fromPeer peerID: MCPeerID,
                          at localURL: URL?,
                          withError error: Error?) {
        // The sample app intentional omits this implementation.
    }

    // MARK: - `MCNearbyServiceBrowserDelegate`.
    internal func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let peerIdentity = info?[MPCSessionConstants.kKeyIdentity] else {
            return
        }
        
        // Role-based connection logic
        let peerRole = info?[MPCSessionConstants.kKeyRole]
        let peerId = info?[MPCSessionConstants.kKeyUserId]
        
        // Determine if we should connect based on roles
        var shouldConnect = false
        
        if userRole == "navigator" && peerRole == "anchor" {
            // Navigator connects to anchors
            // Check if this is the selected anchor
            if let selectedAnchorId = UserSession.shared.selectedAnchorId {
                shouldConnect = peerId == selectedAnchorId
            } else {
                // No specific anchor selected, connect to any anchor
                shouldConnect = true
            }
        } else if userRole == "anchor" && peerRole == "navigator" {
            // Anchor accepts connections from navigators
            shouldConnect = true
        } else if userRole == "anchor" && peerRole == "anchor" {
            // Anchors connect to other anchors for mesh network
            shouldConnect = true
        } else if userRole == nil || peerRole == nil {
            // Fallback to original identity matching for backward compatibility
            shouldConnect = peerIdentity == identityString
        }
        
        if shouldConnect && mcSession.connectedPeers.count < maxNumPeers {
            browser.invitePeer(peerID, to: mcSession, withContext: nil, timeout: 10)
        }
    }

    internal func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // The sample app intentional omits this implementation.
    }

    // MARK: - `MCNearbyServiceAdvertiserDelegate`.
    internal func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                             didReceiveInvitationFromPeer peerID: MCPeerID,
                             withContext context: Data?,
                             invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Accept the invitation only if the number of peers is less than the maximum.
        if self.mcSession.connectedPeers.count < maxNumPeers {
            invitationHandler(true, mcSession)
        }
    }
}
