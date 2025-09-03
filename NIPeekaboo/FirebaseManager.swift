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
        // Predefined mapping of emails to destinations
        let destinationMappings: [(email: String, destination: String)] = [
            ("subhavee1@gmail.com", "window"),
            ("akshata@valuenex.com", "kitchen"),
            ("elena@valuenex.com", "meeting_room")
        ]
        
        print("Starting destination updates for all anchor accounts...")
        
        for mapping in destinationMappings {
            // Find user by email
            db.collection("users")
                .whereField("email", isEqualTo: mapping.email)
                .getDocuments { [weak self] snapshot, error in
                    if let error = error {
                        print("Error finding user \(mapping.email): \(error)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents,
                          let userDoc = documents.first else {
                        print("User not found: \(mapping.email)")
                        return
                    }
                    
                    let userId = userDoc.documentID
                    let batch = self?.db.batch()
                    
                    // Update user document
                    if let userRef = self?.db.collection("users").document(userId) {
                        batch?.updateData(["destination": mapping.destination], forDocument: userRef)
                    }
                    
                    // Update anchor document
                    if let anchorRef = self?.db.collection("anchors").document(userId) {
                        batch?.updateData(["destination": mapping.destination], forDocument: anchorRef)
                    }
                    
                    // Commit batch update
                    batch?.commit { error in
                        if let error = error {
                            print("Error updating destinations for \(mapping.email): \(error)")
                        } else {
                            print("Successfully updated \(mapping.email) with destination: \(mapping.destination)")
                        }
                    }
                }
        }
    }
}