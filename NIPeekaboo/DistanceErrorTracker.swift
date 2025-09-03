/*
See LICENSE folder for this sample's licensing information.

Abstract:
Tracks distance measurements and calculates errors for UWB navigation system.
*/

import Foundation
import NearbyInteraction
import Firebase
import FirebaseFirestore

struct GroundTruthDistance {
    let destination1: AnchorDestination
    let destination2: AnchorDestination
    let distanceInches: Double
    
    var distanceMeters: Double {
        return distanceInches * 0.0254
    }
}

struct DistanceMeasurement {
    let deviceI: String
    let deviceJ: String
    let measuredDistance: Float // d_hat in meters
    let groundTruthDistance: Float // d_true in meters
    let timestamp: Date
    
    var plainError: Float {
        return measuredDistance - groundTruthDistance
    }
    
    var normalizedError: Float {
        guard groundTruthDistance > 0 else { return 0 }
        return (2 * plainError) / groundTruthDistance
    }
}

class DistanceErrorTracker {
    static let shared = DistanceErrorTracker()
    
    private let db = Firestore.firestore()
    private var sessionId: String?
    private var measurementTimer: Timer?
    private var currentMeasurements: [String: Float] = [:]
    private var deviceDestinations: [String: AnchorDestination] = [:]
    
    // Ground truth distances
    private let groundTruthDistances: [GroundTruthDistance] = [
        GroundTruthDistance(destination1: .meetingRoom, destination2: .kitchen, distanceInches: 243.588),
        GroundTruthDistance(destination1: .meetingRoom, destination2: .window, distanceInches: 219.96),
        GroundTruthDistance(destination1: .window, destination2: .kitchen, distanceInches: 405.0)
    ]
    
    private init() {}
    
    // MARK: - Session Management
    
    func startSession(participants: [String: AnchorDestination]) {
        // Check if session is already active
        guard sessionId == nil else {
            print("Session already active: \(sessionId!)")
            return
        }
        
        // Use timestamp as session ID for easy identification
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        sessionId = "session_\(timestamp)"
        
        deviceDestinations = participants
        
        // Create session in Firestore
        let sessionData: [String: Any] = [
            "created_at": FieldValue.serverTimestamp(),
            "readable_timestamp": timestamp,
            "participants": participants.map { ["device_id": $0.key, "destination": $0.value.rawValue] },
            "anchor_configuration": [
                "window_kitchen": 405.0,  // inches
                "window_meeting_room": 219.96,  // inches
                "meeting_room_kitchen": 243.588  // inches
            ]
        ]
        
        db.collection("distance_sessions").document(sessionId!).setData(sessionData) { error in
            if let error = error {
                print("Error creating session: \(error)")
            } else {
                print("Session created: \(self.sessionId!)")
                print("Timestamp: \(timestamp)")
                print("Participants: \(participants.values.map { $0.displayName })")
                self.startMeasurementTimer()
            }
        }
    }
    
    func endSession() {
        measurementTimer?.invalidate()
        measurementTimer = nil
        
        if let sessionId = sessionId {
            db.collection("distance_sessions").document(sessionId).updateData([
                "ended_at": FieldValue.serverTimestamp()
            ])
        }
        
        sessionId = nil
        currentMeasurements.removeAll()
        deviceDestinations.removeAll()
    }
    
    // MARK: - Distance Updates
    
    func updateDistance(from deviceI: String, to deviceJ: String, distance: Float) {
        let key = createPairKey(deviceI, deviceJ)
        currentMeasurements[key] = distance
    }
    
    private func createPairKey(_ device1: String, _ device2: String) -> String {
        // Ensure consistent ordering
        let sorted = [device1, device2].sorted()
        return "\(sorted[0])_\(sorted[1])"
    }
    
    // MARK: - Measurement Timer
    
    private func startMeasurementTimer() {
        measurementTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.recordMeasurements()
        }
    }
    
    private func recordMeasurements() {
        guard let sessionId = sessionId else { return }
        
        let timestamp = Date()
        var measurements: [[String: Any]] = []
        
        for (pairKey, measuredDistance) in currentMeasurements {
            let devices = pairKey.split(separator: "_").map(String.init)
            guard devices.count == 2 else { continue }
            
            let deviceI = devices[0]
            let deviceJ = devices[1]
            
            // Get ground truth distance if both devices are anchors with destinations
            if let destI = deviceDestinations[deviceI],
               let destJ = deviceDestinations[deviceJ] {
                
                if let groundTruth = getGroundTruthDistance(between: destI, and: destJ) {
                    let measurement = DistanceMeasurement(
                        deviceI: deviceI,
                        deviceJ: deviceJ,
                        measuredDistance: measuredDistance,
                        groundTruthDistance: Float(groundTruth.distanceMeters),
                        timestamp: timestamp
                    )
                    
                    measurements.append([
                        "device_i_id": measurement.deviceI,
                        "device_j_id": measurement.deviceJ,
                        "d_true": measurement.groundTruthDistance,
                        "d_hat": measurement.measuredDistance,
                        "e": measurement.plainError,
                        "k": measurement.normalizedError,
                        "timestamp": FieldValue.serverTimestamp()
                    ])
                }
            } else {
                // For navigator-to-anchor measurements (no ground truth)
                measurements.append([
                    "device_i_id": deviceI,
                    "device_j_id": deviceJ,
                    "d_hat": measuredDistance,
                    "timestamp": FieldValue.serverTimestamp()
                ])
            }
        }
        
        // Write all measurements to Firestore
        if !measurements.isEmpty {
            let batch = db.batch()
            
            for measurement in measurements {
                let docRef = db.collection("distance_sessions")
                    .document(sessionId)
                    .collection("measurements")
                    .document()
                batch.setData(measurement, forDocument: docRef)
            }
            
            batch.commit { error in
                if let error = error {
                    print("Error recording measurements: \(error)")
                } else {
                    print("Recorded \(measurements.count) measurements")
                }
            }
        }
    }
    
    // MARK: - Ground Truth Helpers
    
    private func getGroundTruthDistance(between dest1: AnchorDestination, and dest2: AnchorDestination) -> GroundTruthDistance? {
        return groundTruthDistances.first { distance in
            (distance.destination1 == dest1 && distance.destination2 == dest2) ||
            (distance.destination1 == dest2 && distance.destination2 == dest1)
        }
    }
    
    // MARK: - Device Registration
    
    func registerDevice(_ deviceId: String, destination: AnchorDestination?) {
        if let destination = destination {
            deviceDestinations[deviceId] = destination
        }
    }
    
    func unregisterDevice(_ deviceId: String) {
        deviceDestinations.removeValue(forKey: deviceId)
        
        // Remove all measurements involving this device
        currentMeasurements = currentMeasurements.filter { key, _ in
            !key.contains(deviceId)
        }
    }
}