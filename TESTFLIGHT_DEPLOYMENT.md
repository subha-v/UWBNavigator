# TestFlight Deployment Guide

## Prerequisites
- Mac with Xcode 14.0 or later
- Apple Developer Account ($99/year)
- Physical iPhone with U1 chip (iPhone 11 or later) for testing
- App Store Connect access

## Step 1: Open and Configure Xcode Project

### 1.1 Add Firebase SDK
1. Open `NIPeekaboo.xcodeproj` in Xcode
2. Go to **File → Add Package Dependencies**
3. Enter URL: `https://github.com/firebase/firebase-ios-sdk`
4. Click **Add Package**
5. Select these packages:
   - `FirebaseAuth`
   - `FirebaseFirestore`
   - `FirebaseFirestoreSwift` (optional)
6. Click **Add Package**

### 1.2 Add GoogleService-Info.plist to Project
1. In Xcode, right-click on the `NIPeekaboo` folder (where Info.plist is)
2. Select **Add Files to "NIPeekaboo"**
3. Navigate to and select `GoogleService-Info.plist`
4. Make sure **"Copy items if needed"** is checked
5. Make sure **"NIPeekaboo"** target is selected
6. Click **Add**

## Step 2: Configure Project Settings

### 2.1 Set Bundle Identifier
1. Select the project in navigator
2. Select the `NIPeekaboo` target
3. Go to **Signing & Capabilities** tab
4. Change Bundle Identifier to something unique:
   - Format: `com.yourcompany.nearbynavigator`
   - Example: `com.valuenex.uwbnavigator`

### 2.2 Configure Signing
1. In **Signing & Capabilities** tab:
2. Check **"Automatically manage signing"**
3. Select your **Team** from dropdown
   - Personal Team (for development)
   - Organization Team (for App Store)
4. Xcode will create provisioning profiles automatically

### 2.3 Set App Version
1. Go to **General** tab
2. Set **Version**: `1.0.0`
3. Set **Build**: `1`

### 2.4 Update App Display Name
1. In **General** tab
2. Change **Display Name** to: `UWB Navigator`

### 2.5 Configure Capabilities
1. Go to **Signing & Capabilities** tab
2. Click **"+ Capability"**
3. Add these capabilities (if not already present):
   - **Nearby Interaction** (required)
   - **Background Modes** (optional, for background updates)
4. Verify these permissions in Info.plist:
   - `NSNearbyInteractionAllowOnceUsageDescription`
   - `NSNearbyInteractionUsageDescription`
   - `NSLocalNetworkUsageDescription`

## Step 3: App Store Connect Setup

### 3.1 Create App ID
1. Go to [Apple Developer Portal](https://developer.apple.com)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Click **Identifiers → +**
4. Select **App IDs** → Continue
5. Select **App** → Continue
6. Enter:
   - Description: `UWB Navigator`
   - Bundle ID: Same as in Xcode (e.g., `com.valuenex.uwbnavigator`)
7. Enable Capabilities:
   - **NearbyInteraction**
8. Click **Continue** → **Register**

### 3.2 Create App in App Store Connect
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Click **My Apps → +** → **New App**
3. Fill in:
   - Platform: iOS
   - Name: `UWB Navigator`
   - Primary Language: English
   - Bundle ID: Select from dropdown
   - SKU: `UWBNAV001` (or any unique identifier)
4. Click **Create**

## Step 4: Build and Archive

### 4.1 Select Generic Device
1. In Xcode, select scheme dropdown (top bar)
2. Choose **"Any iOS Device (arm64)"** instead of simulator

### 4.2 Clean Build Folder
1. **Product → Clean Build Folder** (⇧⌘K)

### 4.3 Archive the App
1. **Product → Archive**
2. Wait for build to complete (may take several minutes)
3. Organizer window will open automatically

### 4.4 Validate Archive
1. In Organizer, select your archive
2. Click **Validate App**
3. Follow prompts:
   - Sign in with Apple ID if needed
   - Select provisioning profiles (automatic)
4. Fix any validation issues if they appear

## Step 5: Upload to TestFlight

### 5.1 Distribute App
1. In Organizer, with archive selected
2. Click **Distribute App**
3. Select **App Store Connect** → Next
4. Select **Upload** → Next
5. Keep default options → Next
6. Review and click **Upload**
7. Wait for upload to complete

### 5.2 Configure TestFlight
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Select your app
3. Go to **TestFlight** tab
4. Wait for build to process (10-30 minutes)
   - You'll receive email when ready

### 5.3 Add Test Information
When build is processed:
1. Click on the build number
2. Add **Test Details**:
   - What to Test: "Test navigation between anchor and navigator roles"
   - App Description: "UWB-based navigation app"
3. Answer Export Compliance:
   - Does app use encryption? Usually **No**
4. Click **Save**

### 5.4 Create Test Group
1. In TestFlight, go to **Internal Testing** or **External Testing**
2. Create new group:
   - Name: `Beta Testers`
3. Add testers by email
4. Select build to test
5. Click **Save**

## Step 6: Testing

### 6.1 Install TestFlight
Testers need to:
1. Install TestFlight app from App Store
2. Accept email invitation
3. Or redeem code if provided

### 6.2 Install and Test App
1. Open TestFlight
2. Tap on UWB Navigator
3. Tap **Install**
4. Test the app thoroughly

## Important Considerations

### Device Requirements
- **Anchor Phone**: iPhone 11 or later with U1 chip
- **Navigator Phone**: iPhone 11 or later with U1 chip
- Both devices need iOS 14.0+

### Testing Scenarios
1. **Single Navigator**: One anchor, one navigator
2. **Multiple Navigators**: One anchor, 2-3 navigators
3. **Range Testing**: Test at various distances (0.5m to 9m)
4. **Obstacle Testing**: Test with walls/objects between devices

### Common Build Errors and Solutions

#### "Signing for 'NIPeekaboo' requires a development team"
- Select a team in Signing & Capabilities

#### "No account for team"
- Add Apple ID in Xcode → Preferences → Accounts

#### "Profile doesn't include the NearbyInteraction capability"
- Regenerate provisioning profiles
- Ensure capability is added in Apple Developer Portal

#### "GoogleService-Info.plist not found"
- Ensure file is added to Xcode project target
- Check file is in correct location

#### "Firebase module not found"
- Ensure Firebase packages are added via SPM
- Clean build folder and rebuild

### Build Settings Checklist
- [ ] Bundle Identifier set and unique
- [ ] Team selected for signing
- [ ] GoogleService-Info.plist added to target
- [ ] Firebase SDK packages added
- [ ] Info.plist permissions configured
- [ ] Version and build number set
- [ ] Archive validated successfully

## Production Release

After successful TestFlight testing:

1. **Prepare for App Store**:
   - Add App Store screenshots
   - Write app description
   - Add keywords
   - Select categories

2. **Submit for Review**:
   - In App Store Connect, go to app
   - Add build from TestFlight
   - Complete all required information
   - Submit for review

3. **Review Process**:
   - Usually 24-48 hours
   - May receive feedback to address
   - Once approved, can release immediately or schedule

## Support Resources

- [Apple Developer Documentation](https://developer.apple.com/documentation/)
- [TestFlight Documentation](https://developer.apple.com/testflight/)
- [App Store Connect Help](https://help.apple.com/app-store-connect/)
- [Firebase iOS Setup](https://firebase.google.com/docs/ios/setup)

## Troubleshooting Checklist

If app crashes on launch:
- [ ] Verify GoogleService-Info.plist is correct
- [ ] Check Firebase project configuration
- [ ] Ensure all permissions are granted
- [ ] Check device has U1 chip
- [ ] Verify iOS 14.0+ installed

If NearbyInteraction doesn't work:
- [ ] Both devices have U1 chip
- [ ] Permissions granted on both devices
- [ ] Devices within 9 meter range
- [ ] Bluetooth and WiFi enabled
- [ ] Check MultipeerConnectivity connection