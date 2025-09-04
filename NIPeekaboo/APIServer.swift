/*
See LICENSE folder for this sample's licensing information.

Abstract:
HTTP API server for exposing UWB tracking data to webapp.
*/

import Foundation
import UIKit
import Swifter

class APIServer {
    static let shared = APIServer()
    
    private let server = HttpServer()
    private var isRunning = false
    
    // Data sources (will be updated by view controllers)
    var anchorData: [[String: Any]] = []
    var navigatorData: [[String: Any]] = []
    var distanceData: [String: Any] = [:]
    
    private init() {}
    
    func start() {
        guard !isRunning else { return }
        
        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        setupRoutes()
        
        do {
            try server.start(8080, forceIPv4: true)
            isRunning = true
            print("API Server started on port 8080")
            print("Device IP: \(getWiFiAddress() ?? "Unknown")")
        } catch {
            print("Failed to start API server: \(error)")
        }
    }
    
    func stop() {
        server.stop()
        isRunning = false
        print("API Server stopped")
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
}