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
    private var startTime: Date?
    private var requestCount: Int = 0
    private var lastRequestTime: Date?
    private var failedRequests: Int = 0
    
    // Data sources (will be updated by view controllers)
    var anchorData: [[String: Any]] = []
    var navigatorData: [[String: Any]] = []
    var distanceData: [String: Any] = [:]
    
    private override init() {
        super.init()
        setupNotificationObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupNotificationObservers() {
        // Monitor app lifecycle events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func appWillEnterForeground() {
        NSLog("📱 APIServer: App entering foreground")
        // Restart server if it was running but stopped
        if !isRunning {
            NSLog("🔄 APIServer: Restarting server after foreground transition")
            restart()
        }
    }
    
    @objc private func appDidEnterBackground() {
        NSLog("📱 APIServer: App entering background")
        if let uptime = getUptime() {
            NSLog("📊 APIServer Stats - Uptime: \(Int(uptime))s, Requests: \(requestCount), Failed: \(failedRequests)")
        }
    }
    
    private func getUptime() -> TimeInterval? {
        guard let startTime = startTime else { return nil }
        return Date().timeIntervalSince(startTime)
    }
    
    func start() {
        NSLog("🚀 APIServer: Starting server...")
        
        guard !isRunning else { 
            NSLog("⚠️ APIServer already running on port \(currentPort)")
            return 
        }
        
        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        setupRoutes()
        
        // Try different ports if 8080 fails
        let ports = [8080, 8081, 8082, 8083]
        var started = false
        
        for port in ports {
            do {
                NSLog("📌 APIServer: Attempting to start on port \(port)")
                
                // Try both IPv4 and IPv6
                do {
                    // First try dual-stack (IPv4 + IPv6)
                    try server.start(UInt16(port), forceIPv4: false)
                    NSLog("✅ APIServer: Started with dual-stack (IPv4 + IPv6) on port \(port)")
                } catch {
                    // Fallback to IPv4 only
                    NSLog("⚠️ APIServer: Dual-stack failed, trying IPv4 only on port \(port)")
                    try server.start(UInt16(port), forceIPv4: true)
                    NSLog("✅ APIServer: Started with IPv4 only on port \(port)")
                }
                
                isRunning = true
                started = true
                currentPort = port
                startTime = Date()
                
                NSLog("📱 Device IP: \(getWiFiAddress() ?? "Unknown")")
                NSLog("🔗 Access at: http://\(getWiFiAddress() ?? "localhost"):\(port)/api/status")
                
                // Start Bonjour service broadcasting
                startBonjourService(port: port)
                
                break
            } catch {
                NSLog("❌ APIServer: Failed to start on port \(port): \(error.localizedDescription)")
            }
        }
        
        if !started {
            NSLog("🚨 APIServer: CRITICAL - Failed to start on ANY port!")
        }
    }
    
    func stop() {
        NSLog("🛑 APIServer: Stopping server...")
        
        server.stop()
        netService?.stop()
        netService = nil
        isRunning = false
        
        if let uptime = getUptime() {
            NSLog("📊 APIServer Final Stats:")
            NSLog("   - Uptime: \(Int(uptime)) seconds")
            NSLog("   - Total Requests: \(requestCount)")
            NSLog("   - Failed Requests: \(failedRequests)")
        }
        
        NSLog("✅ APIServer: Server stopped")
    }
    
    func restart() {
        NSLog("🔄 APIServer: Restarting server...")
        stop()
        // Small delay to ensure clean shutdown
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.start()
        }
    }
    
    // Update Bonjour service after login to broadcast correct role and email
    func updateBonjourService() {
        guard isRunning else {
            NSLog("⚠️ APIServer: Cannot update Bonjour - server not running")
            return
        }
        
        NSLog("📡 APIServer: Updating Bonjour service...")
        
        // Stop existing Bonjour service
        netService?.stop()
        netService = nil
        
        // Restart with updated user info (using the stored port)
        startBonjourService(port: currentPort)
        
        NSLog("✅ APIServer: Bonjour updated - Role: \(UserSession.shared.userRole?.rawValue ?? "unknown"), Email: \(UserSession.shared.userId ?? "unknown")")
    }
    
    private func setupRoutes() {
        // CORS headers for all responses
        let corsHeaders: [String: String] = [
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type",
            "Content-Type": "application/json"
        ]
        
        // Middleware-like request logging
        let logRequest: (HttpRequest) -> Void = { request in
            self.lastRequestTime = Date()
            NSLog("📥 APIServer Request: \(request.method) \(request.path) from \(request.address ?? "unknown")")
        }
        
        // GET /api/status - Returns server status and device info
        server["/api/status"] = { request in
            logRequest(request)
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
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "server": [
                    "uptime": self.getUptime() ?? 0,
                    "requestCount": self.requestCount,
                    "failedRequests": self.failedRequests
                ]
            ]
            
            self.requestCount += 1
            
            let jsonData = try? JSONSerialization.data(withJSONObject: status, options: .prettyPrinted)
            let jsonString = String(data: jsonData ?? Data(), encoding: .utf8) ?? "{}"
            
            return HttpResponse.raw(200, "OK", corsHeaders) { writer in
                try writer.write([UInt8](jsonString.utf8))
            }
        }
        
        // GET /api/anchors - Returns anchor devices data
        server["/api/anchors"] = { [weak self] request in
            logRequest(request)
            // Handle OPTIONS for CORS preflight
            if request.method == "OPTIONS" {
                return HttpResponse.raw(200, "OK", corsHeaders) { writer in
                    try writer.write([UInt8]())
                }
            }
            
            guard let self = self else {
                self?.failedRequests += 1
                return HttpResponse.internalServerError
            }
            
            let anchors = self.getAnchorsData()
            let jsonData = try? JSONSerialization.data(withJSONObject: anchors, options: .prettyPrinted)
            let jsonString = String(data: jsonData ?? Data(), encoding: .utf8) ?? "[]"
            
            self.requestCount += 1
            NSLog("✅ APIServer: Anchors request successful - returned \(anchors.count) anchors")
            
            return HttpResponse.raw(200, "OK", corsHeaders) { writer in
                try writer.write([UInt8](jsonString.utf8))
            }
        }
        
        // GET /api/navigators - Returns navigator devices data
        server["/api/navigators"] = { [weak self] request in
            logRequest(request)
            // Handle OPTIONS for CORS preflight
            if request.method == "OPTIONS" {
                return HttpResponse.raw(200, "OK", corsHeaders) { writer in
                    try writer.write([UInt8]())
                }
            }
            
            guard let self = self else {
                self?.failedRequests += 1
                return HttpResponse.internalServerError
            }
            
            let navigators = self.getNavigatorsData()
            let jsonData = try? JSONSerialization.data(withJSONObject: navigators, options: .prettyPrinted)
            let jsonString = String(data: jsonData ?? Data(), encoding: .utf8) ?? "[]"
            
            self.requestCount += 1
            NSLog("✅ APIServer: Navigators request successful - returned \(navigators.count) navigators")
            
            return HttpResponse.raw(200, "OK", corsHeaders) { writer in
                try writer.write([UInt8](jsonString.utf8))
            }
        }
        
        // GET /api/distances - Returns current distance measurements
        server["/api/distances"] = { [weak self] request in
            logRequest(request)
            // Handle OPTIONS for CORS preflight
            if request.method == "OPTIONS" {
                return HttpResponse.raw(200, "OK", corsHeaders) { writer in
                    try writer.write([UInt8]())
                }
            }
            
            guard let self = self else {
                self?.failedRequests += 1
                return HttpResponse.internalServerError
            }
            
            let jsonData = try? JSONSerialization.data(withJSONObject: self.distanceData, options: .prettyPrinted)
            let jsonString = String(data: jsonData ?? Data(), encoding: .utf8) ?? "{}"
            
            self.requestCount += 1
            NSLog("✅ APIServer: Distances request successful")
            
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
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            // Check for IPv4 or IPv6 interface
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {  // WiFi interface
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, socklen_t(0), NI_NUMERICHOST)
                    
                    let addressString = String(cString: hostname)
                    
                    // Prefer IPv4 for compatibility
                    if addrFamily == UInt8(AF_INET) {
                        address = addressString
                        break  // Use IPv4 if available
                    } else if address == nil {
                        // Store IPv6 as fallback
                        address = addressString
                    }
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
        
        NSLog("📡 APIServer: Broadcasting Bonjour service: \(serviceName) on port \(port)")
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
        NSLog("✅ APIServer: Bonjour service published successfully")
        NSLog("   - Name: \(sender.name)")
        NSLog("   - Type: \(sender.type)")
        NSLog("   - Domain: \(sender.domain)")
        NSLog("   - Port: \(sender.port)")
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        NSLog("❌ APIServer: Bonjour service failed to publish")
        for (key, value) in errorDict {
            NSLog("   - \(key): \(value)")
        }
        
        // Try to republish with a different name
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            NSLog("🔄 APIServer: Retrying Bonjour publish...")
            self?.updateBonjourService()
        }
    }
    
    func netServiceDidStop(_ sender: NetService) {
        NSLog("🛑 APIServer: Bonjour service stopped")
    }
}