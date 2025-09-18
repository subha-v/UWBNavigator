/*
See LICENSE folder for this sample's licensing information.

Abstract:
Builder class for creating consistent navigator API data payloads
*/

import Foundation
import UIKit

class NavigatorAPIDataBuilder {

    // Build navigator data payload with consistent structure
    static func buildNavigatorData(
        status: String = "idle",
        connectedAnchors: [String] = [],
        distances: [String: Float] = [:],
        similarityScore: Int? = nil,
        batteryLevel: Float? = nil,
        location: [String: Any]? = nil
    ) -> [[String: Any]] {

        guard let userId = UserSession.shared.userId,
              let userName = UserSession.shared.displayName else {
            return []
        }

        var navigatorInfo: [String: Any] = [
            "id": userId,
            "name": userName,
            "type": "navigator",
            "status": status,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        // Add connected anchors if any
        if !connectedAnchors.isEmpty {
            navigatorInfo["connected_anchors"] = connectedAnchors
        }

        // Add distances if available
        if !distances.isEmpty {
            navigatorInfo["distances"] = distances
        }

        // Add similarity score if available
        if let score = similarityScore {
            navigatorInfo["similarity_score"] = score
        }

        // Add battery level if available
        if let battery = batteryLevel {
            navigatorInfo["battery"] = Int(battery * 100)
        } else {
            // Try to get current battery level
            UIDevice.current.isBatteryMonitoringEnabled = true
            let battery = UIDevice.current.batteryLevel
            if battery > 0 {
                navigatorInfo["battery"] = Int(battery * 100)
            }
        }

        // Add location if provided
        if let loc = location {
            navigatorInfo["location"] = loc
        }

        return [navigatorInfo]
    }

    // Build idle navigator data (for selection screen)
    static func buildIdleNavigatorData() -> [[String: Any]] {
        return buildNavigatorData(
            status: "idle",
            connectedAnchors: [],
            distances: [:]
        )
    }

    // Build active navigator data (for navigation screen)
    static func buildActiveNavigatorData(
        connectedAnchors: [String],
        distances: [String: Float],
        similarityScore: Int? = nil
    ) -> [[String: Any]] {
        return buildNavigatorData(
            status: "navigating",
            connectedAnchors: connectedAnchors,
            distances: distances,
            similarityScore: similarityScore
        )
    }
}