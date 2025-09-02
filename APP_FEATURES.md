# NearbyInteraction UWB Navigator App - Feature Documentation

## Overview
This iOS app has been enhanced with a role-based authentication system and improved navigation UI. Users can sign up as either **Anchors** (destination points) or **Navigators** (users seeking anchors), with Firebase handling authentication and data management.

## New Features

### 1. Authentication System
- **Email/Password Authentication**: Secure login system via Firebase Auth
- **Role Selection**: Users choose their role (Anchor/Navigator) during signup
- **Session Persistence**: Stay logged in between app launches
- **Secure Logout**: Properly clean up sessions and presence data

### 2. User Roles

#### Anchor Role
- Acts as a destination point for navigators
- Can see all connected navigators in real-time
- Displays distance and connection status for each navigator
- Supports multiple simultaneous navigator connections
- Shows online/offline status in Firebase

#### Navigator Role
- Can browse available anchors
- Select specific anchor to navigate to
- See directional arrow pointing toward selected anchor
- Real-time distance and direction updates
- Visual and haptic feedback when close to anchor

### 3. Enhanced UI Components

#### Arrow Navigation View (Replaces Monkey Emoji)
- **Custom arrow graphic** that rotates based on anchor direction
- **Color-coded states**:
  - Green: Close to anchor (< 0.3m)
  - Blue: Medium distance
  - Gray: Out of field of view
- **Pulse animation** when very close to anchor
- **Smooth rotation animations** for direction changes

#### Navigation Indicators
- Distance display in meters
- Azimuth (horizontal angle) in degrees
- Elevation (vertical angle) in degrees
- Directional arrows (up/down/left/right) for guidance

### 4. Improved MultipeerConnectivity
- **Role-based discovery**: Anchors and Navigators identify each other
- **Selective connections**: Navigators connect only to selected anchors
- **Identity broadcasting**: Includes user role and ID in discovery
- **Automatic reconnection** on connection loss

## App Architecture

### View Controllers

1. **LoginViewController**
   - Email/password login
   - Navigation to signup
   - Error handling and validation

2. **SignUpViewController**
   - Account creation
   - Role selection (Navigator/Anchor)
   - Password confirmation

3. **AnchorViewController**
   - List of connected navigators
   - Real-time distance updates
   - Connection status indicators
   - Logout functionality

4. **NavigatorViewController**
   - Arrow navigation display
   - Distance and direction info
   - Connection status
   - Disconnect option

5. **AnchorSelectionViewController**
   - Browse available anchors
   - Pull-to-refresh functionality
   - Real-time availability status

### Core Components

1. **FirebaseManager**
   - Centralized Firebase operations
   - Authentication methods
   - Firestore CRUD operations
   - Presence management

2. **UserSession**
   - Session state management
   - User preferences storage
   - Role and ID persistence

3. **ArrowView**
   - Custom Core Graphics drawing
   - Rotation animations
   - State-based appearance
   - Haptic feedback integration

4. **Enhanced MPCSession**
   - Role-aware peer discovery
   - Selective connection logic
   - Identity management

## User Flow

### First-Time User
1. Launch app → Login screen
2. Tap "Sign Up" → Create account
3. Choose role (Anchor/Navigator)
4. Complete registration
5. Navigate to role-specific screen

### Returning Anchor User
1. Launch app → Auto-login
2. Anchor dashboard appears
3. Wait for navigators to connect
4. Monitor connected navigators

### Returning Navigator User
1. Launch app → Auto-login
2. Anchor selection screen
3. Choose destination anchor
4. Follow arrow to navigate

## Technical Requirements

### Device Requirements
- iPhone 11 or later (U1 chip required)
- iOS 14.0 or later
- Active internet connection for Firebase

### Permissions Required
- Nearby Interaction
- Local Network Usage
- Internet Access

## Testing Instructions

### Setup for Testing
1. Install app on 2+ compatible devices
2. Create one Anchor account
3. Create one or more Navigator accounts
4. Ensure devices are within 9 meters

### Test Scenarios

#### Basic Navigation Test
1. Login as Anchor on Device A
2. Login as Navigator on Device B
3. Navigator selects the Anchor
4. Arrow should point from B to A
5. Distance should update in real-time

#### Multiple Navigator Test
1. Setup one Anchor
2. Connect 2-3 Navigators
3. Anchor should see all navigators
4. Each navigator sees only the anchor

#### Reconnection Test
1. Establish connection
2. Move devices out of range
3. Return to range
4. Connection should re-establish

## Known Limitations

1. **U1 Chip Requirement**: Only works on iPhone 11 and later
2. **Range Limitation**: ~9 meter maximum range for UWB
3. **Line of Sight**: Best accuracy with clear line of sight
4. **Firebase Dependency**: Requires internet for auth/data

## Future Enhancements

Potential improvements for future versions:
- Push notifications for anchor availability
- Historical navigation data
- Custom anchor names/descriptions
- Group navigation (multiple navigators to same anchor)
- Indoor mapping integration
- Voice guidance
- Anchor scheduling/availability times

## Troubleshooting

### Common Issues

1. **Can't see anchors in list**
   - Ensure anchor is logged in
   - Check internet connection
   - Pull to refresh the list

2. **Arrow not appearing**
   - Verify both devices have U1 chip
   - Check NearbyInteraction permission
   - Ensure devices are in range

3. **Connection drops frequently**
   - Keep devices within range
   - Avoid obstacles between devices
   - Check battery optimization settings

## Security Considerations

- Firebase Authentication protects user accounts
- Firestore rules restrict data access
- No location data is stored permanently
- Peer connections are encrypted
- User IDs are anonymized in peer discovery