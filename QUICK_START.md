# Quick Start Guide - UWB Navigator App

## 🚀 Immediate Setup Steps

### 1. Open Project in Xcode
```bash
cd /Users/subha/Downloads/VALUENEX/NearbyInteractionUWB
open NIPeekaboo.xcodeproj
```

### 2. Add Firebase SDK (In Xcode)
1. **File → Add Package Dependencies**
2. URL: `https://github.com/firebase/firebase-ios-sdk`
3. Add packages: `FirebaseAuth`, `FirebaseFirestore`

### 3. Add GoogleService-Info.plist to Xcode
1. Right-click `NIPeekaboo` folder in Xcode
2. **Add Files to "NIPeekaboo"**
3. Select `GoogleService-Info.plist` (already in project folder)
4. Check **"Copy items if needed"**
5. Ensure target `NIPeekaboo` is checked

### 4. Configure Signing
1. Select project → `NIPeekaboo` target
2. **Signing & Capabilities** tab
3. Check **"Automatically manage signing"**
4. Select your **Team**
5. Change **Bundle Identifier** to something unique:
   - Example: `com.[yourname].uwbnavigator`

### 5. Build and Run
1. Connect iPhone (11 or later)
2. Select your device in Xcode
3. Press **Run** (⌘R)

## 📱 Testing the App

### Test Setup (2 Devices)
**Device 1 - Anchor:**
1. Launch app
2. Sign up → Select "Anchor" role
3. Wait on anchor screen

**Device 2 - Navigator:**
1. Launch app
2. Sign up → Select "Navigator" role
3. Select the anchor from list
4. Follow arrow to navigate

### Test Setup (1 Device + Simulator)
⚠️ **Note**: Simulator doesn't have U1 chip, so NearbyInteraction won't work, but you can test UI/authentication:
1. Run on Simulator for UI testing
2. Run on device for full functionality

## 🔍 Verify Everything Works

### Check Firebase Connection
1. Run app
2. Try to sign up
3. Check [Firebase Console](https://console.firebase.google.com) → Authentication
4. New user should appear

### Check Firestore
1. After signup, check Firestore Database
2. Should see:
   - `users` collection with user data
   - `anchors` collection (if anchor role)

## 📤 Deploy to TestFlight

### Quick Archive & Upload
1. Select **"Any iOS Device"** in Xcode
2. **Product → Archive**
3. In Organizer: **Distribute App**
4. Select **App Store Connect → Upload**
5. Follow prompts

### In App Store Connect
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Create new app with same Bundle ID
3. Wait for build processing (email notification)
4. Add to TestFlight group

## ⚡ Common Quick Fixes

### "Module 'Firebase' not found"
→ Re-add Firebase packages via SPM

### "GoogleService-Info.plist not found"
→ Make sure file is added to Xcode target (not just in folder)

### "Signing requires development team"
→ Add Apple ID in Xcode → Settings → Accounts

### App crashes on launch
→ Check GoogleService-Info.plist matches Firebase project

### Can't see other device
→ Ensure both devices have U1 chip (iPhone 11+)
→ Keep devices within 9 meters
→ Grant all permissions

## 🎯 Ready to Go!
Your app is now configured with:
- ✅ Firebase Authentication
- ✅ Firestore Database
- ✅ Role-based system (Anchor/Navigator)
- ✅ Arrow navigation UI
- ✅ Real-time UWB tracking

## 📞 Testing Credentials (Optional)
For quick testing, you can create these test accounts:
- Anchor: `anchor@test.com` / `password123`
- Navigator: `navigator@test.com` / `password123`

## 🔗 Important Links
- [Firebase Console](https://console.firebase.google.com) - Manage users/database
- [App Store Connect](https://appstoreconnect.apple.com) - Manage TestFlight
- [Apple Developer](https://developer.apple.com) - Certificates & Profiles

---
**Ready to build!** Open Xcode and press ⌘R to run on your device.