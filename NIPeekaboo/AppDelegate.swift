/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A class that responds to application life cycle events.
*/

import UIKit
import NearbyInteraction
import Firebase

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Initialize Firebase
        FirebaseApp.configure()
        
        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        // Start API server
        APIServer.shared.start()
        
        // Check for NearbyInteraction support
        if !NISession.isSupported {
            print("unsupported device")
            // Ensure that the device supports NearbyInteraction and present
            //  an error message view controller, if not.
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            window?.rootViewController = storyboard.instantiateViewController(withIdentifier: "unsupportedDeviceMessage")
            return true
        }
        
        // Setup initial navigation based on login status
        setupInitialViewController()
        
        return true
    }
    
    private func setupInitialViewController() {
        window = UIWindow(frame: UIScreen.main.bounds)
        
        // Check if user is already logged in
        if UserSession.shared.isLoggedIn {
            // Navigate based on user role
            if let role = UserSession.shared.userRole {
                switch role {
                case .anchor:
                    let anchorVC = AnchorViewController()
                    let navController = UINavigationController(rootViewController: anchorVC)
                    window?.rootViewController = navController
                case .navigator:
                    let anchorSelectionVC = AnchorSelectionViewController()
                    let navController = UINavigationController(rootViewController: anchorSelectionVC)
                    window?.rootViewController = navController
                }
            } else {
                // Role not found, show login
                showLoginScreen()
            }
        } else {
            // Show login screen
            showLoginScreen()
        }
        
        window?.makeKeyAndVisible()
    }
    
    private func showLoginScreen() {
        let loginVC = LoginViewController()
        let navController = UINavigationController(rootViewController: loginVC)
        window?.rootViewController = navController
    }
}

