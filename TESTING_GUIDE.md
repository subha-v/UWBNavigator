# Multi-Anchor UWB Navigation Testing Guide

## Overview
The system now supports multi-anchor UWB navigation with comprehensive error tracking. Each anchor is associated with a specific destination, and the system tracks distances between all devices, calculating errors against ground truth values.

## Test Accounts Configuration

### Anchor Accounts
1. **Window Anchor**
   - Email: subhavee1@gmail.com
   - Destination: Window
   - Already configured in the system

2. **Kitchen Anchor**
   - Email: akshata@valuenex.com
   - Destination: Kitchen
   - Needs to be registered with "Anchor" role and "Kitchen" destination

3. **Meeting Room Anchor**
   - Email: elena@valuenex.com
   - Destination: Meeting Room
   - Needs to be registered with "Anchor" role and "Meeting Room" destination

### Navigator Account
- Email: adpatil989@gmail.com
- Role: Navigator
- Can connect to multiple anchors simultaneously

## Ground Truth Distances
The system uses these pre-configured distances for error calculation:
- Meeting Room ↔ Kitchen: 243.588 inches (6.187 meters)
- Meeting Room ↔ Window: 219.96 inches (5.587 meters)
- Window ↔ Kitchen: 405 inches (10.287 meters)

## Key Features Implemented

### 1. DistanceErrorTracker
- Automatically tracks distances between all connected devices
- Calculates plain error: `e = d_hat - d_true`
- Calculates normalized error: `k = 2e / d_true`
- Logs measurements to Firestore every 3 seconds

### 2. Multi-Peer Sessions
- Anchors can connect to other anchors AND navigators simultaneously
- Each anchor maintains separate NISession for each peer
- Anchor-to-anchor distance tracking for error calculation

### 3. Enhanced SignUp Process
- Anchor users must select their destination during registration
- Three options: Window, Meeting Room, or Kitchen
- Destination is stored in Firebase user profile

### 4. Firebase Schema
```
distance_sessions/
  {session_id}/
    metadata:
      created_at: timestamp
      participants: array of {device_id, destination}
    measurements/
      {auto_id}/
        device_i_id: string
        device_j_id: string
        d_true: number (ground truth in meters)
        d_hat: number (measured distance in meters)
        e: number (plain error)
        k: number (normalized error)
        timestamp: timestamp
```

## Testing Procedure

### Step 1: Account Setup
1. Register elena@valuenex.com as Anchor with "Meeting Room" destination
2. Register akshata@valuenex.com as Anchor with "Kitchen" destination
3. Ensure subhavee1@gmail.com is registered as Anchor with "Window" destination
4. Register/login adpatil989@gmail.com as Navigator

### Step 2: Physical Setup
1. Place iPhone with Window anchor account at the window location
2. Place iPhone with Kitchen anchor account at the kitchen location
3. Place iPhone with Meeting Room anchor account at the meeting room location
4. Use iPhone with Navigator account to move around the space

### Step 3: Start Sessions
1. Launch app on all three anchor devices
2. Each anchor will automatically discover and connect to other anchors
3. Launch app on navigator device
4. Navigator will connect to all available anchors

### Step 4: Verify Data Collection
1. Check Firestore console for `distance_sessions` collection
2. New session document should be created with all participants
3. Every 3 seconds, new measurements should appear in the `measurements` subcollection
4. Each measurement includes:
   - Device pair IDs
   - Ground truth distance (for anchor pairs)
   - Measured distance
   - Calculated errors

### Step 5: Monitor Errors
- Plain error (e): Shows absolute difference in meters
- Normalized error (k): Shows relative error as percentage-like value
- Positive error = measured distance is greater than ground truth
- Negative error = measured distance is less than ground truth

## Troubleshooting

### Devices Not Connecting
- Ensure all devices are on the same Wi-Fi network
- Check that Bluetooth and UWB are enabled
- Verify MultipeerConnectivity permissions are granted

### No Distance Measurements
- Devices need clear line of sight for UWB
- Move devices to have better visibility
- Check that devices support UWB (iPhone 11 or later)

### Missing Ground Truth
- Verify anchor destinations are properly set during registration
- Check Firebase user profiles have `destination` field
- Ensure anchor-to-anchor connections are established

## Data Analysis
The collected error data can be used to:
1. Analyze UWB accuracy in different environments
2. Identify systematic biases in distance measurements
3. Optimize anchor placement for better navigation accuracy
4. Validate the reliability of the UWB technology for indoor navigation