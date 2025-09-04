/*
See LICENSE folder for this sample's licensing information.

Abstract:
Firebase manager for authentication and Firestore operations.
*/

import Foundation
import UIKit
import Firebase
import FirebaseAuth
import FirebaseFirestore

enum UserRole: String {
    case anchor = "anchor"
    case navigator = "navigator"
}

enum AnchorDestination: String, CaseIterable {
    case window = "window"
    case meetingRoom = "meeting_room"
    case kitchen = "kitchen"
    
    var displayName: String {
        switch self {
        case .window:
            return "Window"
        case .meetingRoom:
            return "Meeting Room"
        case .kitchen:
            return "Kitchen"
        }
    }
}

struct AnchorData {
    let id: String
    let name: String
    let destination: String?
}

class FirebaseManager {
    static let shared = FirebaseManager()
    
    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    
    private init() {}
    
    // MARK: - Authentication Methods
    
    func signIn(email: String, password: String, completion: @escaping (Result<String, Error>) -> Void) {
        auth.signIn(withEmail: email, password: password) { authResult, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let userId = authResult?.user.uid else {
                completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User ID not found"])))
                return
            }
            completion(.success(userId))
        }
    }
    
    func signUp(email: String, password: String, displayName: String, role: UserRole, destination: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        auth.createUser(withEmail: email, password: password) { [weak self] authResult, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let userId = authResult?.user.uid else {
                completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User ID not found"])))
                return
            }
            
            // Create user document in Firestore
            var userData: [String: Any] = [
                "email": email,
                "displayName": displayName,
                "role": role.rawValue,
                "isOnline": true,
                "lastSeen": FieldValue.serverTimestamp(),
                "createdAt": FieldValue.serverTimestamp()
            ]
            
            // Add destination for anchor users
            if let destination = destination {
                userData["destination"] = destination
            }
            
            self?.db.collection("users").document(userId).setData(userData) { error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                // If user is an anchor, also add to anchors collection
                if role == .anchor {
                    var anchorData: [String: Any] = [
                        "displayName": displayName,
                        "isAvailable": true,
                        "connectedNavigators": []
                    ]
                    
                    // Add destination to anchor data
                    if let destination = destination {
                        anchorData["destination"] = destination
                    }
                    self?.db.collection("anchors").document(userId).setData(anchorData) { error in
                        if let error = error {
                            completion(.failure(error))
                            return
                        }
                        completion(.success(userId))
                    }
                } else {
                    completion(.success(userId))
                }
            }
        }
    }
    
    func signOut(completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            try auth.signOut()
            UserSession.shared.clearSession()
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
    
    func getCurrentUser() -> String? {
        return auth.currentUser?.uid
    }
    
    // MARK: - Firestore Methods
    
    func fetchUserRole(userId: String, completion: @escaping (Result<UserRole, Error>) -> Void) {
        db.collection("users").document(userId).getDocument { document, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let document = document, document.exists,
                  let roleString = document.data()?["role"] as? String,
                  let role = UserRole(rawValue: roleString) else {
                completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User role not found"])))
                return
            }
            
            completion(.success(role))
        }
    }
    
    func fetchAvailableAnchors(completion: @escaping (Result<[(id: String, name: String)], Error>) -> Void) {
        db.collection("anchors").whereField("isAvailable", isEqualTo: true).getDocuments { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let documents = snapshot?.documents else {
                completion(.success([]))
                return
            }
            
            let anchors = documents.compactMap { doc -> (id: String, name: String)? in
                guard let name = doc.data()["displayName"] as? String else { return nil }
                return (id: doc.documentID, name: name)
            }
            
            completion(.success(anchors))
        }
    }
    
    func updateAnchorConnection(anchorId: String, navigatorId: String, isConnecting: Bool, completion: @escaping (Error?) -> Void) {
        if isConnecting {
            db.collection("anchors").document(anchorId).updateData([
                "connectedNavigators": FieldValue.arrayUnion([navigatorId])
            ]) { error in
                completion(error)
            }
        } else {
            db.collection("anchors").document(anchorId).updateData([
                "connectedNavigators": FieldValue.arrayRemove([navigatorId])
            ]) { error in
                completion(error)
            }
        }
    }
    
    func updateUserPresence(userId: String, isOnline: Bool) {
        let data: [String: Any] = [
            "isOnline": isOnline,
            "lastSeen": FieldValue.serverTimestamp()
        ]
        db.collection("users").document(userId).updateData(data) { error in
            if let error = error {
                print("Error updating presence: \(error)")
            }
        }
    }
    
    func updateBatteryLevel(userId: String, batteryLevel: Float) {
        let data: [String: Any] = [
            "battery": Int(batteryLevel * 100),
            "lastActive": FieldValue.serverTimestamp()
        ]
        db.collection("users").document(userId).updateData(data) { error in
            if let error = error {
                print("Error updating battery level: \(error)")
            }
        }
    }
    
    func updateQoDScore(userId: String, score: Int?) {
        var data: [String: Any] = [
            "lastActive": FieldValue.serverTimestamp()
        ]
        
        if let score = score {
            data["qodScore"] = score
        } else {
            data["qodScore"] = FieldValue.delete()
        }
        
        db.collection("users").document(userId).updateData(data) { error in
            if let error = error {
                print("Error updating QoD score: \(error)")
            }
        }
    }
    
    func fetchUserDestination(userId: String, completion: @escaping (Result<String?, Error>) -> Void) {
        db.collection("users").document(userId).getDocument { document, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let document = document, document.exists else {
                completion(.success(nil))
                return
            }
            
            let destination = document.data()?["destination"] as? String
            completion(.success(destination))
        }
    }
    
    func fetchAllAnchorsWithDestinations(completion: @escaping (Result<[AnchorData], Error>) -> Void) {
        db.collection("anchors").whereField("isAvailable", isEqualTo: true).getDocuments { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let documents = snapshot?.documents else {
                completion(.success([]))
                return
            }
            
            let anchors = documents.compactMap { doc -> AnchorData? in
                guard let name = doc.data()["displayName"] as? String else { return nil }
                let destination = doc.data()["destination"] as? String
                return AnchorData(id: doc.documentID, name: name, destination: destination)
            }
            
            completion(.success(anchors))
        }
    }
    
    // MARK: - Update Existing Anchor Destinations
    func updateExistingAnchorDestinations() {
        // Predefined mapping of emails/UIDs to destinations
        // Try both email and UID formats since Firebase Auth might use UIDs
        let destinationMappings: [(identifier: String, destination: String, displayName: String)] = [
            // Email mappings
            ("subhavee1@gmail.com", "window", "Window Anchor"),
            ("akshata@valuenex.com", "kitchen", "Kitchen Anchor"),
            ("elena@valuenex.com", "meeting_room", "Meeting Room Anchor"),
            // UID mappings (based on actual device data)
            ("0o3RPyMtuvSwy1G67WebWQNEQDg2", "window", "subhavee1"),  // subhavee1's UID
            ("r11EHbHmQYONTjVBXwWp54fi5Ut1", "kitchen", "akshata"),   // akshata's UID
        ]
        
        print("Starting destination updates for all anchor accounts...")
        
        for mapping in destinationMappings {
            // Try to find user by email first, then by UID
            db.collection("users")
                .whereField("email", isEqualTo: mapping.identifier)
                .getDocuments { [weak self] snapshot, error in
                    if let error = error {
                        print("Error finding user \(mapping.identifier): \(error)")
                        return
                    }
                    
                    // If not found by email, try directly as document ID (UID)
                    if snapshot?.documents.isEmpty == true {
                        // Try to update directly by UID
                        self?.db.collection("users").document(mapping.identifier).getDocument { document, error in
                            if let document = document, document.exists {
                                // Update the document
                                document.reference.updateData([
                                    "destination": mapping.destination,
                                    "displayName": mapping.displayName
                                ]) { error in
                                    if let error = error {
                                        print("Error updating destination for UID \(mapping.identifier): \(error)")
                                    } else {
                                        print("✅ Successfully updated destination for \(mapping.displayName) (UID: \(mapping.identifier)) to \(mapping.destination)")
                                    }
                                }
                            } else {
                                print("User document not found for UID: \(mapping.identifier)")
                            }
                        }
                        return
                    }
                    
                    guard let documents = snapshot?.documents,
                          let userDoc = documents.first else {
                        print("User not found: \(mapping.identifier)")
                        return
                    }
                    
                    let userId = userDoc.documentID
                    let batch = self?.db.batch()
                    
                    // Update user document
                    if let userRef = self?.db.collection("users").document(userId) {
                        batch?.updateData([
                            "destination": mapping.destination,
                            "displayName": mapping.displayName
                        ], forDocument: userRef)
                    }
                    
                    // Update anchor document
                    if let anchorRef = self?.db.collection("anchors").document(userId) {
                        batch?.updateData(["destination": mapping.destination], forDocument: anchorRef)
                    }
                    
                    // Commit batch update
                    batch?.commit { error in
                        if let error = error {
                            print("Error updating destinations for \(mapping.identifier): \(error)")
                        } else {
                            print("✅ Successfully updated \(mapping.displayName) (ID: \(mapping.identifier)) with destination: \(mapping.destination)")
                        }
                    }
                }
        }
    }
}