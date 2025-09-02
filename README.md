# UWBNavigator

A real-time indoor navigation iOS app using Ultra-Wideband (UWB) technology and Apple's Nearby Interaction framework. Navigate to people or points of interest with centimeter-level precision using directional arrows and distance indicators.

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

## 📱 Requirements

- **Devices**: iPhone 11 or newer (requires U1 chip)
- **iOS Version**: iOS 14.0 or later
- **Xcode**: 14.0 or later
- **Swift**: 5.0 or later
- **Firebase Account**: For authentication and anchor discovery

## 🚀 Installation

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
1. Open `NIPeekaboo.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run on a physical device (UWB not available in simulator)

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

## 🏗 Architecture

### Technology Stack
- **UWB Ranging**: Apple Nearby Interaction framework
- **Device Discovery**: MultipeerConnectivity
- **Backend**: Firebase (Auth + Realtime Database)
- **UI Framework**: UIKit with programmatic constraints
- **Navigation**: Custom ArrowView with Core Animation

### Key Components

```
NIPeekaboo/
├── View Controllers/
│   ├── LoginViewController.swift          # Authentication
│   ├── SignUpViewController.swift          # User registration
│   ├── AnchorSelectionViewController.swift # Browse anchors
│   ├── AnchorViewController.swift         # Anchor mode UI
│   └── NavigatorViewController.swift      # Navigator mode UI
├── Views/
│   └── ArrowView.swift                    # Custom arrow visualization
├── Networking/
│   ├── MPCSession.swift                   # MultipeerConnectivity wrapper
│   └── FirebaseManager.swift              # Firebase operations
├── Models/
│   └── UserSession.swift                  # Session management
└── Resources/
    └── Info.plist                         # App configuration
```

### Data Flow
1. **Authentication**: Firebase Auth → UserSession
2. **Discovery**: Firebase DB → Available Anchors List
3. **Connection**: MultipeerConnectivity → Peer Discovery
4. **Ranging**: NI Discovery Tokens → UWB Sessions
5. **Visualization**: NINearbyObject → Arrow Updates

## 🔧 Troubleshooting

### Common Issues

**"Nearby Interaction access required"**
- Go to Settings → Privacy → Nearby Interactions
- Enable permission for the app

**Devices not discovering each other**
- Ensure both devices have WiFi and Bluetooth enabled
- Check that both are on the same network
- Restart the app on both devices

**Arrow not appearing**
- Verify line of sight between devices
- Check distance is within UWB range (~9 meters)
- Ensure phone is held upright for compass accuracy

**Connection drops frequently**
- Keep devices within range
- Avoid obstacles between devices
- Check battery optimization settings

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