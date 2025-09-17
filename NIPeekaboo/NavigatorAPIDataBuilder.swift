/*
See LICENSE folder for this sample's licensing information.

Abstract:
Helper for building navigator API payloads shared across view controllers.
*/

import UIKit

struct NavigatorAPIDataBuilder {
    static func buildData(selectedAnchorName: String?,
                          connectedAnchorCount: Int,
                          distances: [String: Float],
                          statusOverride: String? = nil) -> [[String: Any]] {
        let status = statusOverride ?? (connectedAnchorCount > 0 ? "active" : "idle")
        let batteryLevel = UIDevice.current.batteryLevel
        let batteryPercentage = Int(batteryLevel * 100)

        return [[
            "id": UserSession.shared.userId ?? "unknown",
            "name": UserSession.shared.displayName ?? UIDevice.current.name,
            "targetAnchor": selectedAnchorName ?? "none",
            "battery": batteryPercentage,
            "status": status,
            "connectedAnchors": connectedAnchorCount,
            "distances": distances
        ]]
    }
}
