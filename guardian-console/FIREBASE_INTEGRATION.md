# Guardian Console Firebase Integration

## Overview
The Guardian Console has been integrated with Firebase to show real-time data from the UWB navigation system.

## Setup Instructions

1. **Install Dependencies** (Already completed)
   ```bash
   npm install firebase
   ```

2. **Switch to Firebase Version**
   To use the Firebase-integrated version instead of the mock data version:
   ```bash
   # Rename the current page to backup
   mv app/page.tsx app/page-mock.tsx
   
   # Use the Firebase version
   mv app/page-firebase.tsx app/page.tsx
   ```

3. **Run the Application**
   ```bash
   npm run dev
   ```

## Features

### Real-Time Data Display
- **Anchors Panel**: Shows anchor locations (Window, Kitchen, Meeting Room) with:
  - Agent ID (destination name)
  - QoD Score (calculated from distance measurements or N/A if no measurements)
  - Battery level (updated every 30 seconds from iOS app)
  - Status (online/offline based on last active time)

- **Navigators Panel**: Shows navigator users with:
  - Agent ID (username from email)
  - QoD Score (shows N/A until all 3 anchors are connected)
  - Battery level (from UIDevice API)
  - Status (active/idle based on online status)

- **Smart Contracts Panel**: Shows recent distance measurements as contracts with:
  - Transaction ID (generated from timestamp)
  - Navigator ID
  - Error in meters (from distance measurements)
  - Pass/Fail status based on normalized error

### Data Sources
- User data from Firestore `users` collection
- Distance measurements from `distance_sessions` collection
- Real-time updates via Firestore listeners
- Battery updates every 30 seconds from iOS devices

## iOS App Updates

The iOS app has been updated to:
1. Send battery level updates every 30 seconds
2. Update QoD scores based on connected anchors
3. Update presence status (online/offline)
4. Send data via `updateBatteryLevel()` and `updateQoDScore()` methods

## Firebase Schema

```
users/
  {userId}/
    email: string
    role: "Anchor" | "Navigator"
    destination: string (for anchors)
    battery: number (0-100)
    qodScore: number | null
    lastActive: timestamp
    isOnline: boolean

distance_sessions/
  {sessionId}/
    metadata:
      created_at: timestamp
      participants: array
    measurements/
      {measurementId}/
        device_i_id: string
        device_j_id: string
        d_true: number
        d_hat: number
        e: number (plain error)
        k: number (normalized error)
        timestamp: timestamp
```

## Testing

1. Start the Guardian Console web app
2. Launch the iOS app on anchor devices (Window, Kitchen, Meeting Room)
3. Launch the iOS app on navigator device (adpatil989@gmail.com)
4. Watch real-time updates appear in the console:
   - Anchors show as online with battery levels
   - Navigator shows as online with battery
   - QoD scores appear once all 3 anchors connect
   - Measurements appear in Smart Contracts panel

## Troubleshooting

- **No data showing**: Check Firebase console for data in users collection
- **Offline status**: Devices are considered offline if lastActive > 30 seconds ago
- **N/A QoD scores**: QoD only calculated when all 3 anchors are connected
- **No measurements**: Ensure all 3 anchors and navigator are connected