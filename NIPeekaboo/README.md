# NIPeekaboo - Multi-Anchor UWB Navigation System

## Overview
NIPeekaboo is an iOS application that implements a multi-anchor Ultra-Wideband (UWB) navigation system using Apple's Nearby Interaction framework. The system enables precise distance tracking between multiple anchors and navigators, with comprehensive error analysis against ground truth measurements.

## Features

### Core Functionality
- **Multi-Anchor Tracking**: Simultaneous tracking between multiple anchor devices
- **Navigator Support**: Mobile devices can navigate to fixed anchor points
- **Real-time Distance Measurement**: Using iPhone's U1 chip for precise UWB ranging
- **Error Analysis**: Automatic calculation of measurement errors against ground truth

### Recent Updates (September 2024)

#### Multi-Anchor Session Management
- **Required 3-Anchor Configuration**: System now requires all three predefined anchors to be connected before starting tracking
- **Dynamic Status Display**: Shows "Waiting for: [missing anchors]" until all required anchors are online
- **Automatic Session Creation**: Tracking session starts automatically when all anchors are connected

#### Enhanced Error Tracking
- **Ground Truth Comparison**: Compares measured distances against known ground truth values
- **Error Metrics**:
  - Plain error (e = d_hat - d_true) in meters
  - Normalized error (k = 2e/d_true) as unitless percentage
- **Timestamped Sessions**: Sessions named with timestamp format `session_yyyy-MM-dd_HH-mm-ss`

#### Firebase Integration
- **Real-time Data Logging**: Measurements recorded to Firestore every 3 seconds
- **Structured Data Storage**: Organized in `distance_sessions` collection with measurements subcollection
- **Automatic Destination Assignment**: Pre-configured anchor accounts automatically assigned to destinations

## System Architecture

### Anchor Configuration
Three fixed anchor positions with predefined accounts:
- **Window**: subhavee1@gmail.com
- **Kitchen**: akshata@valuenex.com  
- **Meeting Room**: elena@valuenex.com

### Ground Truth Distances
- Meeting Room ↔ Kitchen: 243.588 inches (6.187 meters)
- Meeting Room ↔ Window: 219.96 inches (5.587 meters)
- Window ↔ Kitchen: 405 inches (10.287 meters)

### Technical Implementation
- **Multiple NISessions**: Each anchor maintains separate NISession for each peer
- **Bidirectional Tracking**: Distance measured independently from both ends
- **Concurrent Measurements**: All anchor pairs tracked simultaneously
- **Firestore Schema**: Structured data with session metadata and time-series measurements

## Setup Instructions

### Prerequisites
- Xcode 14.0 or later
- iOS 15.0 or later
- iPhone 11 or newer (with U1 chip)
- Firebase project with Firestore enabled

### Installation
1. Clone the repository
2. Open `NIPeekaboo.xcodeproj` in Xcode
3. Configure Firebase:
   - Add your `GoogleService-Info.plist` to the project
   - Enable Authentication and Firestore in Firebase Console
4. Build and run on physical devices (UWB not supported in simulator)

### Account Setup
1. Register anchor accounts with designated destinations:
   - Email must match predefined configuration
   - Select appropriate destination during signup
2. Existing accounts will have destinations auto-assigned on first login

## Usage

### For Anchors
1. Login with anchor account
2. Place device at designated physical location
3. Wait for other anchors to connect
4. System automatically starts tracking when all 3 anchors are online

### For Navigators
1. Login with navigator account
2. Select target anchor from available list
3. Follow on-screen navigation guidance
4. View real-time distance and direction

### Admin Features
- Long press (3 seconds) on login screen logo
- Enter admin password to access destination update utility
- Batch update destinations for existing accounts

## Data Collection

### Firestore Structure
```
distance_sessions/
  session_yyyy-MM-dd_HH-mm-ss/
    metadata:
      created_at: timestamp
      participants: [...]
      anchor_configuration: {...}
    measurements/
      {document_id}/
        device_i_id: string
        device_j_id: string
        d_true: number (meters)
        d_hat: number (meters)
        e: number (plain error)
        k: number (normalized error)
        timestamp: timestamp
```

## Testing

### Test Configuration
- Requires 3 physical iPhones with U1 chip
- Devices must be on same network
- Clear line of sight recommended for best accuracy

### Monitoring
- Check Firestore console for real-time data
- View error metrics in measurements collection
- Session documents include all tracking data

## Technical Notes

### NISession Management
- Each anchor creates separate NISession per connected peer
- Sessions remain active until explicit disconnection
- UWB tracking operates independently per session
- Maximum 10 concurrent peers supported

### Known Limitations
- Requires iOS devices with U1 chip
- Accuracy affected by obstacles and interference
- Maximum range approximately 9 meters
- Requires all 3 anchors for session start

## License
See LICENSE folder for licensing information.

## Contributors
- VALUENEX Team
- Subha (Development Lead)

## Support
For issues or questions, please contact the development team or create an issue in the repository.