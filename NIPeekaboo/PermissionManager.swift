/*
See LICENSE folder for this sample's licensing information.

Abstract:
Manages all permission requests for the app
*/

import Foundation
import CoreBluetooth
import AVFoundation
import NearbyInteraction

class PermissionManager: NSObject {
    static let shared = PermissionManager()

    private var centralManager: CBCentralManager?
    private var bluetoothCompletion: ((Bool) -> Void)?

    override init() {
        super.init()
    }

    // Request all required permissions
    func requestAllPermissions(completion: @escaping (Bool) -> Void) {
        var allPermissionsGranted = true
        let group = DispatchGroup()

        // 1. Check Nearby Interaction support
        if !NISession.isSupported {
            print("❌ Device doesn't support Nearby Interaction")
            completion(false)
            return
        }

        // 2. Request Bluetooth permission
        group.enter()
        requestBluetoothPermission { granted in
            if !granted {
                allPermissionsGranted = false
                print("❌ Bluetooth permission denied")
            } else {
                print("✅ Bluetooth permission granted")
            }
            group.leave()
        }

        // 3. Request Camera permission (for photo verification)
        group.enter()
        requestCameraPermission { granted in
            if !granted {
                allPermissionsGranted = false
                print("❌ Camera permission denied")
            } else {
                print("✅ Camera permission granted")
            }
            group.leave()
        }

        // Note: NISession will request its own permission when first run
        // Note: Local Network permission is requested automatically when needed

        group.notify(queue: .main) {
            print("All permission requests completed. Granted: \(allPermissionsGranted)")
            completion(allPermissionsGranted)
        }
    }

    // Request Bluetooth permission
    private func requestBluetoothPermission(completion: @escaping (Bool) -> Void) {
        bluetoothCompletion = completion
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    // Request Camera permission
    private func requestCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    // Check if all permissions are granted
    func checkAllPermissions() -> Bool {
        // Check Bluetooth
        let bluetoothGranted = CBCentralManager.authorization == .allowedAlways

        // Check Camera
        let cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized

        // Check NI support
        let niSupported = NISession.isSupported

        return bluetoothGranted && cameraGranted && niSupported
    }

    // Get permission status for debugging
    func getPermissionStatus() -> String {
        var status = "Permission Status:\n"

        // Bluetooth
        switch CBCentralManager.authorization {
        case .allowedAlways:
            status += "✅ Bluetooth: Allowed\n"
        case .notDetermined:
            status += "⚠️ Bluetooth: Not Determined\n"
        case .restricted:
            status += "❌ Bluetooth: Restricted\n"
        case .denied:
            status += "❌ Bluetooth: Denied\n"
        @unknown default:
            status += "❓ Bluetooth: Unknown\n"
        }

        // Camera
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            status += "✅ Camera: Authorized\n"
        case .notDetermined:
            status += "⚠️ Camera: Not Determined\n"
        case .restricted:
            status += "❌ Camera: Restricted\n"
        case .denied:
            status += "❌ Camera: Denied\n"
        @unknown default:
            status += "❓ Camera: Unknown\n"
        }

        // Nearby Interaction
        if NISession.isSupported {
            status += "✅ Nearby Interaction: Supported\n"
        } else {
            status += "❌ Nearby Interaction: Not Supported\n"
        }

        return status
    }
}

// MARK: - CBCentralManagerDelegate
extension PermissionManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on")
            bluetoothCompletion?(true)
        case .poweredOff:
            print("Bluetooth is powered off")
            bluetoothCompletion?(false)
        case .unauthorized:
            print("Bluetooth is unauthorized")
            bluetoothCompletion?(false)
        case .unsupported:
            print("Bluetooth is unsupported")
            bluetoothCompletion?(false)
        case .resetting:
            print("Bluetooth is resetting")
            bluetoothCompletion?(false)
        case .unknown:
            print("Bluetooth state is unknown")
            bluetoothCompletion?(false)
        @unknown default:
            print("Unknown Bluetooth state")
            bluetoothCompletion?(false)
        }

        bluetoothCompletion = nil
    }
}