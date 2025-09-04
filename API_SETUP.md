# UWB Navigator API Setup Guide

This guide explains how to connect the UWB Navigator web console to your iOS app for real-time data display.

## Prerequisites

1. Both iOS device and computer running the webapp must be on the same WiFi network
2. iOS app must be built and running on a physical device (not simulator)
3. Node.js installed for running the webapp

## iOS App Setup

### 1. Add Swifter Package

Open the iOS project in Xcode and add the Swifter package:

1. In Xcode, go to File → Add Package Dependencies
2. Enter the URL: `https://github.com/httpswift/swifter.git`
3. Choose version 1.5.0 or later
4. Add to your app target

### 2. Update Info.plist

Add the following to your `Info.plist` to allow local network connections:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app needs local network access to share tracking data with the web console</string>
```

### 3. Files Added

- `APIServer.swift` - HTTP server that exposes tracking data via REST API
- Modified `AppDelegate.swift` - Starts API server and enables battery monitoring

### 4. Update View Controllers

In your `NavigatorViewController.swift`, add code to update the API server with current data:

```swift
// Add this method to update API data
private func updateAPIData() {
    let navigatorData = [[
        "id": UserSession.shared.userId ?? "unknown",
        "name": UserSession.shared.displayName ?? UIDevice.current.name,
        "targetAnchor": selectedAnchorName ?? "none",
        "battery": Int(UIDevice.current.batteryLevel * 100),
        "status": connectedAnchors.isEmpty ? "idle" : "active",
        "connectedAnchors": connectedAnchors.count,
        "distances": anchorDistances.mapValues { Float($0) }
    ] as [String : Any]]
    
    APIServer.shared.updateNavigatorData(navigatorData)
}

// Call updateAPIData() whenever data changes
```

Similarly update `AnchorViewController.swift`:

```swift
// Add this method to update API data
private func updateAPIData() {
    let anchorData = [[
        "id": UserSession.shared.userId ?? "unknown",
        "name": UserSession.shared.displayName ?? UIDevice.current.name,
        "destination": anchorDestination?.rawValue ?? "unknown",
        "battery": Int(UIDevice.current.batteryLevel * 100),
        "status": connectedNavigators.isEmpty ? "disconnected" : "connected",
        "connectedNavigators": connectedNavigators.count
    ] as [String : Any]]
    
    APIServer.shared.updateAnchorData(anchorData)
}
```

## Web App Setup

### 1. Configure Environment

1. Navigate to the webapp directory:
   ```bash
   cd /Users/subha/Downloads/UWBNavigator-Web/uwb-navigator-web
   ```

2. Copy the example environment file:
   ```bash
   cp .env.local.example .env.local
   ```

3. Edit `.env.local` and set your iPhone's IP address:
   ```
   NEXT_PUBLIC_API_URL=http://192.168.1.100:8080
   ```

   To find your iPhone's IP:
   - Go to Settings → Wi-Fi
   - Tap the (i) icon next to your connected network
   - Note the IP Address

### 2. Run the Web App

```bash
npm run dev
```

The app will be available at http://localhost:3002

## Testing the Connection

1. **Start iOS App**: Build and run the iOS app on your physical device
2. **Check API Server**: The iOS app console should show:
   - "API Server started on port 8080"
   - "Device IP: 192.168.x.x"
3. **Configure WebApp**: Update `.env.local` with the IP shown in iOS console
4. **Test Connection**: The webapp header should show "Connected" in green

## Available API Endpoints

The iOS app exposes these endpoints:

- `GET /api/status` - Server status and device info
- `GET /api/anchors` - List of anchor devices and their data
- `GET /api/navigators` - List of navigator devices and their data
- `GET /api/distances` - Current distance measurements

## Data Available from iOS App

### Anchor Data
- User ID (email)
- Device name
- Destination (Window/Kitchen/Meeting Room)
- Battery level
- Connection status
- Number of connected navigators
- Distance measurements and errors (from DistanceErrorTracker)

### Navigator Data
- User ID (email)
- Device name
- Target anchor name
- Battery level
- Connection status
- Number of connected anchors
- Real-time distances to each anchor

## Troubleshooting

### Connection Issues
- Ensure both devices are on the same WiFi network
- Check firewall settings on your computer
- Verify the IP address is correct in `.env.local`
- Try accessing `http://[IPHONE_IP]:8080/api/status` directly in browser

### No Data Showing
- Check iOS console for API server logs
- Ensure view controllers are calling `updateAPIData()` methods
- Verify battery monitoring is enabled (check for battery icon in webapp)

### Build Errors
- Make sure Swifter package is properly installed
- Clean build folder (Shift+Cmd+K) and rebuild
- Check that `APIServer.swift` is added to your app target

## Security Notes

- The API server only runs on local network (not accessible from internet)
- No authentication is implemented (suitable for development/testing)
- For production use, add proper authentication and HTTPS