/*
See LICENSE folder for this sample's licensing information.

Abstract:
User session manager for maintaining authentication state.
*/

import Foundation

class UserSession {
    static let shared = UserSession()
    
    private let userDefaults = UserDefaults.standard
    private let userIdKey = "com.nipeekaboo.userId"
    private let userRoleKey = "com.nipeekaboo.userRole"
    private let userDisplayNameKey = "com.nipeekaboo.displayName"
    private let selectedAnchorKey = "com.nipeekaboo.selectedAnchor"
    
    private init() {}
    
    var userId: String? {
        get { userDefaults.string(forKey: userIdKey) }
        set { userDefaults.set(newValue, forKey: userIdKey) }
    }
    
    var userRole: UserRole? {
        get {
            guard let roleString = userDefaults.string(forKey: userRoleKey) else { return nil }
            return UserRole(rawValue: roleString)
        }
        set { userDefaults.set(newValue?.rawValue, forKey: userRoleKey) }
    }
    
    var displayName: String? {
        get { userDefaults.string(forKey: userDisplayNameKey) }
        set { userDefaults.set(newValue, forKey: userDisplayNameKey) }
    }
    
    var selectedAnchorId: String? {
        get { userDefaults.string(forKey: selectedAnchorKey) }
        set { userDefaults.set(newValue, forKey: selectedAnchorKey) }
    }
    
    var isLoggedIn: Bool {
        return userId != nil && userRole != nil
    }
    
    func setSession(userId: String, role: UserRole, displayName: String) {
        self.userId = userId
        self.userRole = role
        self.displayName = displayName
        
        // Update Bonjour service to broadcast correct role and email
        APIServer.shared.updateBonjourService()
    }
    
    func clearSession() {
        userId = nil
        userRole = nil
        displayName = nil
        selectedAnchorId = nil
    }
    
    func clearSelectedAnchor() {
        selectedAnchorId = nil
    }
}