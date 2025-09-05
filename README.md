# UWBNavigator

A comprehensive indoor navigation system using Ultra-Wideband (UWB) technology, featuring an iOS app with Apple's Nearby Interaction framework and a web-based monitoring dashboard. Navigate to people or points of interest with centimeter-level precision while monitoring system performance in real-time.

## 🆕 Latest Updates

### IPv6 and IPv4 Dual-Stack Support (January 2025) - NEW!
- **Full IPv6 Support**: Discovery and connection now work seamlessly with both IPv4 and IPv6 addresses
- **Dual-Stack mDNS Discovery**: Automatically detects and uses both address families from Bonjour/mDNS broadcasts
- **Intelligent Address Selection**: Prefers IPv4 for compatibility but falls back to IPv6 when needed
- **Multiple Address Attempts**: Tries all available addresses (both IPv4 and IPv6) for robust connectivity
- **Enhanced Error Handling**: Better logging and diagnostics for connection attempts across both protocols
- **Future-Proof**: Fully compatible with IPv6-only networks as required by modern iOS deployments

### Bonjour Service Role Broadcasting Fix (September 2024)
- **Dynamic Service Updates**: Bonjour service now updates automatically after user login
- **Accurate Role Display**: Fixed issue where devices showed incorrect role/email in network discovery
- **Real-time Synchronization**: Service broadcasts immediately reflect current user session
- **Enhanced Device Detection**: Web console now shows correct device information on first discovery
- **Improved Reliability**: Eliminates need to restart app after role changes

### Automatic Device Discovery with Bonjour (December 2024) - WORKING!
- **Zero Configuration**: iOS devices automatically discovered via Bonjour/mDNS
- **FastAPI Aggregation Server**: Central Python server that discovers and aggregates data from all iOS devices
- **No Manual IP Setup**: Eliminates need for hardcoded IP addresses - devices appear automatically
- **Role-Based Display**: Anchors and navigators properly separated in web console columns
- **WebSocket Support**: Real-time data streaming to web dashboard
- **Scalable Architecture**: Supports unlimited devices automatically
- **Manual Registration Fallback**: Can manually register devices if Bonjour has issues

### Multi-Device Connection Support (September 2024) - WORKING!
- **Two Anchor Phone Setup**: Successfully tested with two anchor devices running simultaneously  
- **Single Navigator Connection**: One navigator device can connect to and track multiple anchors
- **Stable WebApp Integration**: All devices properly appear and stream data to the web console
- **Enhanced Auto-Discovery**: Improved `auto_discover.py` and `auto_discover.sh` scripts for better device detection
- **Robust API Server**: Updated APIServer.swift with better multi-port support and connection handling

## 🎯 Features

### Core Navigation
- **Real-time Direction Arrow**: Dynamic arrow pointing toward your destination
- **Precise Distance Tracking**: Centimeter-level accuracy using UWB technology
- **Multi-directional Indicators**: Visual guides showing left/right/up/down directions
- **Haptic Feedback**: Tactile notification when reaching destination (< 0.3m)

### User Roles
- **Navigator Mode**: Find and navigate to anchor points
- **Anchor Mode**: Broadcast your location for others to find you

### Technical Features
- Firebase Authentication & Real-time Database
- MultipeerConnectivity for device discovery
- Nearby Interaction framework for UWB ranging
- Automatic session management and reconnection
- Background mode support for continuous tracking
- Real-time error tracking against ground truth distances
- Battery monitoring and QoD (Quality of Data) scoring

### Guardian Console (Web Dashboard)
- **Automatic Device Discovery**: Devices appear automatically - no configuration needed
- **Real-time Monitoring**: View all active anchors and navigators
- **Battery Tracking**: Monitor device battery levels
- **QoD Scores**: Quality metrics for positioning accuracy
- **Distance Measurements**: Live error tracking against ground truth
- **Smart Contract Simulation**: View measurement history as transactions
- **FastAPI Backend**: Centralized data aggregation with Bonjour discovery
- **WebSocket Updates**: Real-time streaming of device data

## 📱 Requirements

### iOS App
- **Devices**: iPhone 11 or newer (requires U1 chip)
- **iOS Version**: iOS 14.0 or later
- **Xcode**: 14.0 or later
- **Swift**: 5.0 or later
- **Firebase Account**: For authentication and anchor discovery

### Guardian Console
- **Python**: 3.8 or later (for FastAPI server)
- **Node.js**: 18.0 or later
- **npm**: 8.0 or later
- **Modern web browser**: Chrome, Firefox, Safari, or Edge

## 🚀 Quick Start

### 1. Start FastAPI Server (NEW!)
```bash
cd UWBNavigator
./start_server.sh
# Server runs on http://localhost:8000
# Automatically discovers iOS devices on network
```

### 2. Run iOS App
- Build and deploy to iPhone(s)
- Sign in and select role (Anchor/Navigator)
- Devices automatically appear in web console

### 3. Open Web Dashboard
```bash
cd UWBNavigator-Web/uwb-navigator-web
npm install
npm run dev
# Open http://localhost:3002
```

## 🚀 Detailed Installation

### 1. Clone the Repository
```bash
git clone https://github.com/subha-v/UWBNavigator.git
cd UWBNavigator
```

### 2. Install Dependencies
```bash
pod install
```
If using Swift Package Manager, packages will be resolved automatically when opening the project.

Additionally, add the Swifter HTTP server package:
1. Open `NIPeekaboo.xcodeproj` in Xcode
2. Go to File → Add Package Dependencies
3. Add: `https://github.com/httpswift/swifter`
4. Select version: Up to Next Major Version (2.0.0)

### 3. Firebase Setup
1. Create a new Firebase project at [Firebase Console](https://console.firebase.google.com)
2. Add an iOS app with your bundle identifier
3. Download `GoogleService-Info.plist`
4. Add the file to the project root (already in .gitignore)
5. Enable Authentication (Email/Password)
6. Enable Realtime Database

### 4. Configure Info.plist
The following keys are already configured:
- `NSNearbyInteractionAllowOnceUsageDescription`: Permission for UWB ranging
- `NSLocalNetworkUsageDescription`: Permission for peer-to-peer connectivity
- `NSBonjourServices`: Required for MultipeerConnectivity

### 5. Build and Run

#### iOS App
1. Open `NIPeekaboo.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run on a physical device (UWB not available in simulator)

#### Guardian Console
1. Navigate to the guardian-console directory:
   ```bash
   cd guardian-console
   ```
2. Install dependencies:
   ```bash
   npm install
   ```
3. Start the development server:
   ```bash
   npm run dev
   ```
4. Open [http://localhost:3000](http://localhost:3000) in your browser

## 🎮 Usage

### First Time Setup
1. Launch the app on two or more iPhone 11+ devices
2. Create an account or sign in
3. Choose your role:
   - **Anchor**: Your location will be broadcast to navigators
   - **Navigator**: Find and navigate to available anchors

### Navigation Flow

#### As an Anchor:
1. Tap "Anchor Mode" after signing in
2. Your device becomes discoverable to navigators
3. View connected navigators and their distances in real-time
4. Multiple navigators can connect simultaneously

#### As a Navigator:
1. Tap "Navigator Mode" after signing in
2. Select an anchor from the available list
3. Follow the on-screen arrow to navigate
4. Monitor your distance and direction in real-time

### Understanding the UI

#### Navigator View Components:

**Direction Arrow**:
- **Blue Arrow**: Normal navigation state, pointing toward destination
- **Gray Arrow**: Destination is out of field of view or tracking unavailable
- **Green Tint**: Very close to destination (< 0.3m)
- Arrow size indicates confidence in direction

**Distance Display**:
- Green text: < 0.3 meters (arrival zone)
- Blue text: < 1.0 meter (close proximity)
- Default text: > 1.0 meter (normal navigation)

**Direction Indicators**:
- Blue highlighted arrows show which way to turn
- Help when anchor is outside direct view
- Update threshold: ±15 degrees

**Technical Readouts**:
- Azimuth: Horizontal angle to target (-180° to 180°)
- Elevation: Vertical angle to target (-90° to 90°)

#### Anchor View Components:
- List of connected navigators
- Real-time distance to each navigator
- Connection status indicators:
  - 🟠 Orange: Connected, initializing
  - 🟢 Green: Actively tracking
  - 🔴 Red: Disconnected

## 🌐 Web Dashboard Integration

The app includes an HTTP API server for real-time web dashboard integration:

### API Server
- **Port**: 8080
- **Auto-starts**: When app launches
- **Protocol**: HTTP with CORS enabled

### Available Endpoints

#### GET /api/status
Returns device status and information:
```json
{
  "status": "online",
  "deviceName": "iPhone 14 Pro",
  "batteryLevel": 85,
  "timestamp": "2025-01-04T12:00:00Z"
}
```

#### GET /api/anchors
Returns data from anchor devices:
```json
[{
  "id": "user-unique-id",
  "name": "Device Name", 
  "destination": "Location Name",
  "battery": 92,
  "status": "connected",
  "connectedNavigators": 3,
  "measuredDistance": 1.5,
  "distanceError": 0.05
}]
```

#### GET /api/navigators
Returns data from navigator devices:
```json
[{
  "id": "user-unique-id",
  "name": "Device Name",
  "targetAnchor": "anchor-name",
  "battery": 85,
  "status": "active",
  "connectedAnchors": 2,
  "distances": {
    "anchor1": 1.5,
    "anchor2": 2.3
  }
}]
```

#### GET /api/distances
Returns current distance measurements between devices.

### Connecting Web Dashboard
1. Find iPhone's IP: Settings → Wi-Fi → (i) icon → IP Address
2. Configure dashboard with: `http://[iPhone-IP]:8080`
3. Ensure iPhone and computer are on same network
4. API updates automatically as tracking data changes

## 🏗 Architecture

### Technology Stack
- **UWB Ranging**: Apple Nearby Interaction framework
- **Device Discovery**: MultipeerConnectivity
- **Backend**: Firebase (Auth + Realtime Database)
- **UI Framework**: UIKit with programmatic constraints
- **Navigation**: Custom ArrowView with Core Animation
- **API Server**: Swifter HTTP server for web integration

### Project Structure

```
UWBNavigator/
├── NIPeekaboo/                            # iOS Application
│   ├── LoginViewController.swift          # Authentication
│   ├── SignUpViewController.swift          # User registration
│   ├── AnchorSelectionViewController.swift # Browse anchors
│   ├── AnchorViewController.swift         # Anchor mode UI
│   ├── NavigatorViewController.swift      # Navigator mode UI
│   ├── ArrowView.swift                    # Custom arrow visualization
│   ├── MPCSession.swift                   # MultipeerConnectivity wrapper
│   ├── APIServer.swift                    # HTTP server for web dashboard
│   ├── FirebaseManager.swift              # Firebase operations
│   ├── DistanceErrorTracker.swift        # Error tracking & metrics
│   └── UserSession.swift                  # Session management
├── guardian-console/                       # Web Dashboard
│   ├── app/                               # Next.js app directory
│   │   └── page.tsx                       # Main dashboard
│   ├── components/                        # UI components
│   ├── hooks/                             # React hooks
│   │   └── useFirebaseData.ts            # Real-time data hooks
│   └── lib/                               # Utilities
│       └── firebase.ts                    # Firebase config
└── NIPeekaboo.xcodeproj                  # Xcode project
```

### Data Flow
1. **Authentication**: Firebase Auth → UserSession
2. **Discovery**: Firebase DB → Available Anchors List
3. **Connection**: MultipeerConnectivity → Peer Discovery
4. **Ranging**: NI Discovery Tokens → UWB Sessions
5. **Visualization**: NINearbyObject → Arrow Updates

### Network Architecture (IPv4/IPv6 Dual-Stack)

The FastAPI server implements full dual-stack support for seamless operation across different network configurations:

#### mDNS/Bonjour Discovery
- **Service Type**: `_uwbnav._tcp.local.` (standard) or `_uwbnav-http._tcp.local.` (HTTP variant)
- **Address Parsing**: Handles both 4-byte (IPv4) and 16-byte (IPv6) address formats
- **TXT Records**: Includes deviceId, email, role, and deviceName metadata

#### Connection Strategy
1. **Address Priority**: Attempts IPv4 first for compatibility, falls back to IPv6
2. **URL Formatting**: Automatically brackets IPv6 addresses (e.g., `http://[2001:db8::1]:8080`)
3. **Multi-Port Support**: Tries ports 8080-8083 for each address
4. **Retry Logic**: Exhaustive testing of all address/port combinations

#### Implementation Details
```python
# IPv4 parsing
if len(addr_bytes) == 4:
    addr = socket.inet_ntoa(addr_bytes)  # Standard IPv4
    
# IPv6 parsing  
elif len(addr_bytes) == 16:
    addr = socket.inet_ntop(socket.AF_INET6, addr_bytes)  # IPv6 with proper formatting
    if '%' in addr:
        addr = addr.split('%')[0]  # Remove zone index if present
```

## 🔧 Troubleshooting

### Common Issues

**"Nearby Interaction access required"**
- Go to Settings → Privacy → Nearby Interactions
- Enable permission for the app

**Devices not discovering each other**
- Ensure both devices have WiFi and Bluetooth enabled
- Check that both are on the same network
- Restart the app on both devices
- For IPv6-only networks, ensure router supports mDNS/Bonjour multicast

**Arrow not appearing**
- Verify line of sight between devices
- Check distance is within UWB range (~9 meters)
- Ensure phone is held upright for compass accuracy

**Connection drops frequently**
- Keep devices within range
- Avoid obstacles between devices
- Check battery optimization settings

**IPv6 Connection Issues**
- Check if devices advertise IPv6 addresses: Look for `Found IPv6:` in server logs
- Verify IPv6 connectivity: `ping6 <device-ipv6-address>`
- Some routers may block IPv6 multicast - check router settings
- If only IPv6 works, ensure FastAPI server binds to `::/0` (all IPv6 interfaces)

### Performance Tips
- Best accuracy with clear line of sight
- Optimal range: 1-5 meters
- Hold phone upright for accurate direction
- Minimize metal obstacles between devices

## 🚢 Deployment

### TestFlight Distribution
1. Archive the app in Xcode
2. Upload to App Store Connect
3. Configure TestFlight test groups
4. Add internal/external testers
5. Submit for review if needed

### App Store Release
1. Ensure all Firebase configs are production-ready
2. Update app metadata and screenshots
3. Submit for App Store review
4. Monitor crash reports and analytics

## 📊 Technical Specifications

### UWB Capabilities
- **Range**: Up to 9 meters (typical)
- **Accuracy**: ±10 cm in optimal conditions
- **Update Rate**: ~30 Hz
- **Field of View**: ±60 degrees horizontal

### Device Compatibility
- iPhone 11, 11 Pro, 11 Pro Max
- iPhone 12 series (all models)
- iPhone 13 series (all models)
- iPhone 14 series (all models)
- iPhone 15 series (all models)
- Apple Watch Series 6 and later (future support)
- AirTags (different use case)

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Development Guidelines
- Follow Swift style guidelines
- Add unit tests for new features
- Update documentation as needed
- Test on multiple device models
- Ensure backward compatibility

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Apple's Nearby Interaction sample code
- Firebase for backend services
- The iOS development community

## 📧 Contact

For questions or support, please open an issue on GitHub or contact the maintainers.

---

**Note**: This app requires physical iOS devices with U1 chips for testing. The UWB functionality cannot be simulated in Xcode simulator.