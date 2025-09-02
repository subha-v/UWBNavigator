# Firebase Setup Instructions

## Prerequisites
Before running the app, you need to set up Firebase for authentication and Firestore database.

## Step 1: Create Firebase Project
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Create a project" or select an existing project
3. Follow the setup wizard

## Step 2: Add iOS App to Firebase
1. In Firebase Console, click "Add app" and select iOS
2. Enter your iOS bundle ID (e.g., `com.example.NIPeekaboo`)
3. Download the `GoogleService-Info.plist` file
4. **IMPORTANT**: Place the `GoogleService-Info.plist` file in the `/NIPeekaboo` folder (same directory as `Info.plist`)

## Step 3: Enable Authentication
1. In Firebase Console, go to Authentication > Sign-in method
2. Enable "Email/Password" authentication
3. Click "Save"

## Step 4: Set up Firestore Database
1. In Firebase Console, go to Firestore Database
2. Click "Create database"
3. Choose "Start in test mode" for development (configure security rules for production)
4. Select your preferred location
5. Click "Enable"

## Step 5: Configure Firestore Security Rules
For development, you can use these basic rules:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow authenticated users to read/write their own data
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Allow all authenticated users to read anchors
    match /anchors/{anchorId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == anchorId;
    }
  }
}
```

## Step 6: Add Firebase SDK to Xcode Project

### Using Swift Package Manager (Recommended):
1. Open `NIPeekaboo.xcodeproj` in Xcode
2. Go to File > Add Packages...
3. Enter the Firebase iOS SDK repository URL: `https://github.com/firebase/firebase-ios-sdk`
4. Choose version (latest stable recommended)
5. Add the following packages:
   - FirebaseAuth
   - FirebaseFirestore
   - FirebaseFirestoreSwift (optional, for Codable support)

### Using CocoaPods (Alternative):
1. Create a `Podfile` in the project root:
```ruby
platform :ios, '14.0'
use_frameworks!

target 'NIPeekaboo' do
  pod 'Firebase/Auth'
  pod 'Firebase/Firestore'
end
```
2. Run `pod install`
3. Open `NIPeekaboo.xcworkspace` instead of `.xcodeproj`

## Step 7: Update Code Files
1. Uncomment Firebase imports in the following files:
   - `AppDelegate.swift`
   - `FirebaseManager.swift`

2. Uncomment the Firebase initialization in `AppDelegate.swift`:
```swift
FirebaseApp.configure()
```

3. Uncomment all Firebase-related code in `FirebaseManager.swift`

## Step 8: Test the App

### For Testing with Multiple Devices:
1. Install the app on at least two devices with U1 chip (iPhone 11 or later)
2. Create accounts with different roles:
   - Device 1: Sign up as "Anchor"
   - Device 2: Sign up as "Navigator"
3. The Navigator can select the Anchor from the list and navigate to it

### Mock Testing (Without Firebase):
The app includes mock implementations that work without Firebase:
- Mock login accepts any email/password
- Mock anchor list shows sample anchors
- Useful for UI testing without Firebase setup

## Firestore Data Structure

The app uses the following Firestore structure:

```
firestore/
├── users/
│   └── {userId}/
│       ├── email: string
│       ├── displayName: string
│       ├── role: "anchor" | "navigator"
│       ├── isOnline: boolean
│       ├── lastSeen: timestamp
│       └── createdAt: timestamp
│
└── anchors/
    └── {userId}/
        ├── displayName: string
        ├── isAvailable: boolean
        └── connectedNavigators: array<string>
```

## Troubleshooting

### Common Issues:

1. **"No GoogleService-Info.plist found"**
   - Ensure the file is added to the Xcode project target
   - Check that it's in the correct directory

2. **Authentication not working**
   - Verify Email/Password auth is enabled in Firebase Console
   - Check network connectivity

3. **Firestore read/write errors**
   - Review security rules
   - Ensure database is created and not in offline mode

4. **NearbyInteraction not working**
   - Ensure devices have U1 chip (iPhone 11+)
   - Grant location and NearbyInteraction permissions
   - Devices need to be in close proximity (within ~9 meters)

## Production Considerations

Before deploying to production:
1. Implement proper Firestore security rules
2. Enable Firebase App Check for security
3. Configure proper authentication methods
4. Set up Firebase Analytics and Crashlytics
5. Implement proper error handling and logging
6. Consider rate limiting and usage quotas