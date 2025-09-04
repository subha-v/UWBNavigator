/*
See LICENSE folder for this sample's licensing information.

Abstract:
HTTP API server for exposing UWB tracking data to webapp.
*/

import Foundation
import UIKit
import Swifter

class APIServer: NSObject {
    static let shared = APIServer()
    
    private let server = HttpServer()
    private var netService: NetService?
    private var currentPort: Int = 0
    private var isRunning = false
    
    // Data sources (will be updated by view controllers)
    var anchorData: [[String: Any]] = []
    var navigatorData: [[String: Any]] = []
    var distanceData: [String: Any] = [:]
    
    private override init() {
        super.init()
    }
    
    func start() {
        guard !isRunning else { 
            print("API Server already running")
            return 
        }
        
        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        setupRoutes()
        
        do {
            // Try different ports if 8080 fails
            let ports = [8080, 8081, 8082, 8083]
            var started = false
            
            for port in ports {
                do {
                    try server.start(UInt16(port), forceIPv4: true)
                    isRunning = true
                    started = true
                    currentPort = port
                    print("✅ API Server started on port \(port)")
                    print("📱 Device IP: \(getWiFiAddress() ?? "Unknown")")
                    print("🔗 Access at: http://\(getWiFiAddress() ?? "localhost"):\(port)/api/status")
                    
                    // Start Bonjour service broadcasting
                    startBonjourService(port: port)
                    
                    break
                } catch {
                    print("❌ Failed to start on port \(port): \(error)")
                }
            }
            
            if !started {
                print("❌ API Server failed to start on any port")
            }
        }
    }
    
    func stop() {
        server.stop()
        netService?.stop()
        netService = nil
        isRunning = false
        print("API Server stopped")
    }
    
    // Update Bonjour service after login to broadcast correct role and email
    func updateBonjourService() {
        guard isRunning else { return }
        
        // Get current port
        let currentPort = server.port ?? 8080
        
        // Stop existing Bonjour service
        netService?.stop()
        netService = nil
        
        // Restart with updated user info
        startBonjourService(port: Int(currentPort))
        print("📡 Updated Bonjour service with role: \(UserSession.shared.userRole?.rawValue ?? "unknown"), email: \(UserSession.shared.userId ?? "unknown")")
    }
    
    private func setupRoutes() {
        // CORS headers for all responses
        let corsHeaders: [String: String] = [
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type",
            "Content-Type": "application/json"
        ]
        
        // GET /api/status - Returns server status and device info
        server["/api/status"] = { request in
            // Handle OPTIONS for CORS preflight
            if request.method == "OPTIONS" {
                return HttpResponse.raw(200, "OK", corsHeaders) { writer in
                    try writer.write([UInt8]())
                }
            }
            
            let status: [String: Any] = [
                "status": "online",
                "deviceName": UIDevice.current.name,
                "deviceModel": UIDevice.current.model,
                "systemVersion": UIDevice.current.systemVersion,
                "batteryLevel": Int(UIDevice.current.batteryLevel * 100),
                "email": UserSession.shared.userId ?? "unknown",
                "role": UserSession.shared.userRole?.rawValue ?? "unknown",
                "port": self.currentPort,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
            
            let jsonData = try? JSONSerialization.data(withJSONObject: status, options: .prettyPrinted)
            let jsonString = String(data: jsonData ?? Data(), encoding: .utf8) ?? "{}"
            
            return HttpResponse.raw(200, "OK", corsHeaders) { writer in
                try writer.write([UInt8](jsonString.utf8))
            }
        }
        
        // GET /api/anchors - Returns anchor devices data
        server["/api/anchors"] = { [weak self] request in
            // Handle OPTIONS for CORS preflight
            if request.method == "OPTIONS" {
                return HttpResponse.raw(200, "OK", corsHeaders) { writer in
                    try writer.write([UInt8]())
                }
            }
            
            guard let self = self else { return HttpResponse.internalServerError }
            
            let anchors = self.getAnchorsData()
            let jsonData = try? JSONSerialization.data(withJSONObject: anchors, options: .prettyPrinted)
            let jsonString = String(data: jsonData ?? Data(), encoding: .utf8) ?? "[]"
            
            return HttpResponse.raw(200, "OK", corsHeaders) { writer in
                try writer.write([UInt8](jsonString.utf8))
            }
        }
        
        // GET /api/navigators - Returns navigator devices data
        server["/api/navigators"] = { [weak self] request in
            // Handle OPTIONS for CORS preflight
            if request.method == "OPTIONS" {
                return HttpResponse.raw(200, "OK", corsHeaders) { writer in
                    try writer.write([UInt8]())
                }
            }
            
            guard let self = self else { return HttpResponse.internalServerError }
            
            let navigators = self.getNavigatorsData()
            let jsonData = try? JSONSerialization.data(withJSONObject: navigators, options: .prettyPrinted)
            let jsonString = String(data: jsonData ?? Data(), encoding: .utf8) ?? "[]"
            
            return HttpResponse.raw(200, "OK", corsHeaders) { writer in
                try writer.write([UInt8](jsonString.utf8))
            }
        }
        
        // GET /api/distances - Returns current distance measurements
        server["/api/distances"] = { [weak self] request in
            // Handle OPTIONS for CORS preflight
            if request.method == "OPTIONS" {
                return HttpResponse.raw(200, "OK", corsHeaders) { writer in
                    try writer.write([UInt8]())
                }
            }
            
            guard let self = self else { return HttpResponse.internalServerError }
            
            let jsonData = try? JSONSerialization.data(withJSONObject: self.distanceData, options: .prettyPrinted)
            let jsonString = String(data: jsonData ?? Data(), encoding: .utf8) ?? "{}"
            
            return HttpResponse.raw(200, "OK", corsHeaders) { writer in
                try writer.write([UInt8](jsonString.utf8))
            }
        }
    }
    
    // MARK: - Data Collection Methods
    
    private func getAnchorsData() -> [[String: Any]] {
        // Return actual anchor data only - no mock data
        return anchorData
    }
    
    private func getNavigatorsData() -> [[String: Any]] {
        // Return actual navigator data only - no mock data
        return navigatorData
    }
    
    // MARK: - Update Methods (to be called by view controllers)
    
    func updateAnchorData(_ data: [[String: Any]]) {
        anchorData = data
        // Clear navigator data when updating as anchor
        navigatorData = []
    }
    
    func updateNavigatorData(_ data: [[String: Any]]) {
        navigatorData = data
        // Clear anchor data when updating as navigator
        anchorData = []
    }
    
    func updateDistanceData(_ data: [String: Any]) {
        distanceData = data
    }
    
    func clearAnchorData() {
        anchorData = []
    }
    
    func clearNavigatorData() {
        navigatorData = []
    }
    
    // MARK: - Helper Methods
    
    private func getWiFiAddress() -> String? {
        var address: String?
        
        // Get list of all interfaces on the local machine
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        
        // For each interface...
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            
            // Check for IPv4 interface
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                
                // Check interface name
                let name = String(cString: interface.ifa_name)
                if name == "en0" {  // Wi-Fi adapter
                    
                    // Convert interface address to a human readable string
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        
        freeifaddrs(ifaddr)
        return address
    }
    
    // MARK: - Bonjour Service Broadcasting
    
    private func startBonjourService(port: Int) {
        // Stop any existing service
        netService?.stop()
        
        // Create service name with user email or device name
        let email = UserSession.shared.userId ?? "unknown"
        let deviceName = UIDevice.current.name.replacingOccurrences(of: " ", with: "-")
        let serviceName = "\(email)-\(deviceName)".replacingOccurrences(of: "@", with: "-at-")
            .replacingOccurrences(of: ".", with: "-")
        
        // Create and configure the NetService
        netService = NetService(
            domain: "local.",
            type: "_uwbnav-http._tcp.",
            name: serviceName,
            port: Int32(port)
        )
        
        // Add TXT record with device metadata
        let txtData = createTXTRecord()
        netService?.setTXTRecord(txtData)
        
        // Set delegate and publish
        netService?.delegate = self
        netService?.publish()
        
        print("📡 Broadcasting Bonjour service: \(serviceName) on port \(port)")
    }
    
    private func createTXTRecord() -> Data {
        var txtRecord = [String: Data]()
        
        // Add device metadata
        txtRecord["email"] = (UserSession.shared.userId ?? "unknown").data(using: .utf8)
        txtRecord["deviceName"] = UIDevice.current.name.data(using: .utf8)
        txtRecord["deviceId"] = (UIDevice.current.identifierForVendor?.uuidString ?? "unknown").data(using: .utf8)
        txtRecord["role"] = (UserSession.shared.userRole?.rawValue ?? "unknown").data(using: .utf8)
        txtRecord["version"] = "1.0".data(using: .utf8)
        
        return NetService.data(fromTXTRecord: txtRecord)
    }
}

// MARK: - NetServiceDelegate

extension APIServer: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        print("✅ Bonjour service published successfully: \(sender.name)")
        print("📡 Service type: \(sender.type)")
        print("📡 Port: \(sender.port)")
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        print("❌ Failed to publish Bonjour service")
        if let errorCode = errorDict[NetService.errorCode] {
            print("   Error code: \(errorCode)")
        }
        if let errorDomain = errorDict[NetService.errorDomain] {
            print("   Error domain: \(errorDomain)")
        }
    }
}