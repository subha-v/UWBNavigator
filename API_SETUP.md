# UWB Navigator API Setup Guide

This guide explains how to connect the UWB Navigator web console to your iOS app for real-time data display using automatic Bonjour/mDNS discovery.

## Prerequisites

1. Both iOS device and computer must be on the same WiFi network
2. iOS app must be built and running on a physical device (not simulator)
3. Python 3.8+ installed for running the FastAPI server
4. Node.js installed for running the webapp

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

## FastAPI Server Setup (NEW - Automatic Discovery!)

### 1. Start the FastAPI Server

The FastAPI server automatically discovers iOS devices on your network using Bonjour/mDNS:

```bash
cd /Users/subha/Downloads/UWBNavigator
./start_server.sh
```

Or manually:

```bash
cd /Users/subha/Downloads/UWBNavigator
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python fastapi_server.py
```

The server will:
- Start on http://localhost:8000
- Automatically discover iOS devices running the UWB Navigator app
- Aggregate data from all discovered devices
- Separate anchors and navigators by role
- Provide real-time WebSocket updates

### 2. Verify Server

Open http://localhost:8000 in your browser to see:
- API documentation
- List of discovered devices
- Real-time status updates

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

3. The default configuration should work:
   ```
   NEXT_PUBLIC_FASTAPI_URL=http://localhost:8000
   ```

### 2. Run the Web App

```bash
npm run dev
```

The app will be available at http://localhost:3002

## Testing the Connection

1. **Start iOS App**: Build and run the iOS app on your physical device
2. **Check iOS Console**: The iOS app should show:
   - "✅ API Server started on port 808X"
   - "📡 Broadcasting Bonjour service: [email]-[device] on port 808X"
   - "✅ Bonjour service published successfully"
3. **Start FastAPI Server**: Run `./start_server.sh` - you should see:
   - "✅ Discovered device: [email] ([role]) at [IP]:[PORT]"
4. **Open Web App**: The header should show "Connected" in green
5. **Verify Separation**: 
   - Anchors appear only in the Anchor column
   - Navigators appear only in the Navigator column

## Available API Endpoints

### FastAPI Server Endpoints (Primary)

The FastAPI server provides these aggregated endpoints:

- `GET /` - Health check and server status
- `GET /api/status` - Server status and discovered devices
- `GET /api/devices` - List of all discovered iOS devices
- `GET /api/anchors` - Aggregated anchor data from all devices
- `GET /api/navigators` - Aggregated navigator data from all devices
- `GET /api/all` - All aggregated data in one response
- `POST /api/refresh` - Manually trigger device discovery refresh
- `WS /ws` - WebSocket for real-time updates

### iOS Device Endpoints (Direct Access)

Each iOS device still exposes:

- `GET /api/status` - Device status and info
- `GET /api/anchors` - Anchor data from this device
- `GET /api/navigators` - Navigator data from this device
- `GET /api/distances` - Distance measurements

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

## How It Works

### Automatic Device Discovery

1. **iOS Broadcasts**: Each iOS device broadcasts a Bonjour service `_uwbnav-http._tcp`
2. **FastAPI Discovers**: The FastAPI server automatically finds all iOS devices
3. **Data Aggregation**: FastAPI fetches and aggregates data from all devices
4. **Role Separation**: Devices are automatically sorted by role (anchor/navigator)
5. **Web App Display**: The web app shows devices in appropriate columns

### No Manual Configuration Needed!

- ✅ No need to find iPhone IP addresses
- ✅ No need to update configuration files
- ✅ Devices automatically appear when they join the network
- ✅ Works with unlimited number of devices

## Troubleshooting

### FastAPI Server Issues

- **No devices discovered**:
  - Ensure iOS app is running and shows "Bonjour service published"
  - Check firewall settings (allow Python)
  - Verify all devices are on same WiFi network
  - Try `POST http://localhost:8000/api/refresh` to force refresh

- **Connection errors**:
  - Check if iOS device shows correct IP in console
  - Verify iOS API server is running (check iOS console)
  - Try restarting the iOS app

### Web App Issues

- **No data showing**:
  - Verify FastAPI server is running (http://localhost:8000)
  - Check browser console for errors
  - Ensure `.env.local` has correct FastAPI URL

### No Data Showing
- Check iOS console for API server logs
- Ensure view controllers are calling `updateAPIData()` methods
- Verify battery monitoring is enabled (check for battery icon in webapp)

### Build Errors
- Make sure Swifter package is properly installed
- Clean build folder (Shift+Cmd+K) and rebuild
- Check that `APIServer.swift` is added to your app target

## Architecture Benefits

### Previous Architecture (Direct Connection)
- ❌ Manual IP configuration required
- ❌ Hardcoded device list
- ❌ Multiple connection attempts
- ❌ No central aggregation
- ❌ Difficult to scale

### New Architecture (Bonjour + FastAPI)
- ✅ Automatic device discovery
- ✅ Zero configuration
- ✅ Centralized data aggregation
- ✅ Proper role separation
- ✅ WebSocket real-time updates
- ✅ Scales to any number of devices
- ✅ Single endpoint for web app

## Security Notes

- The API server only runs on local network (not accessible from internet)
- No authentication is implemented (suitable for development/testing)
- For production use, add proper authentication and HTTPS
- Bonjour/mDNS only works on local network for security