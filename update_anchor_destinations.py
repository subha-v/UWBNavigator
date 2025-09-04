#!/usr/bin/env python3
"""
Update anchor destinations in Firebase for testing
Sets the correct anchor destinations for each user
"""

import firebase_admin
from firebase_admin import credentials, firestore
import os

# Initialize Firebase (you'll need to provide path to your service account key)
# Download from Firebase Console > Project Settings > Service Accounts
SERVICE_ACCOUNT_KEY = "path/to/serviceAccountKey.json"  # Update this path

# Initialize Firebase Admin
if os.path.exists(SERVICE_ACCOUNT_KEY):
    cred = credentials.Certificate(SERVICE_ACCOUNT_KEY)
    firebase_admin.initialize_app(cred)
else:
    print("⚠️  Service account key not found. Using default credentials.")
    firebase_admin.initialize_app()

db = firestore.client()

# Anchor configurations based on your testing setup
ANCHOR_CONFIGS = {
    "subhavee1@gmail.com": {
        "destination": "window",
        "name": "Window Anchor",
        "role": "anchor"
    },
    "akshata@valuenex.com": {
        "destination": "kitchen", 
        "name": "Kitchen Anchor",
        "role": "anchor"
    },
    "elena@valuenex.com": {
        "destination": "meeting_room",
        "name": "Meeting Room Anchor",
        "role": "anchor"
    }
}

def update_user_destinations():
    """Update destinations for anchor users in Firebase"""
    print("🔄 Updating anchor destinations in Firebase...\n")
    
    for email, config in ANCHOR_CONFIGS.items():
        try:
            # Find user by email
            users_ref = db.collection('users')
            query = users_ref.where('email', '==', email).limit(1)
            docs = query.get()
            
            if docs:
                user_doc = docs[0]
                user_id = user_doc.id
                
                # Update user document with destination
                update_data = {
                    'destination': config['destination'],
                    'role': config['role'],
                    'displayName': config['name']
                }
                
                users_ref.document(user_id).update(update_data)
                print(f"✅ Updated {email}:")
                print(f"   - Destination: {config['destination']}")
                print(f"   - Display Name: {config['name']}")
                print(f"   - User ID: {user_id}\n")
            else:
                print(f"⚠️  User not found: {email}")
                print(f"   User needs to sign in to the app first\n")
                
        except Exception as e:
            print(f"❌ Error updating {email}: {e}\n")

def verify_destinations():
    """Verify that destinations are correctly set"""
    print("\n📋 Verifying current destinations:\n")
    
    for email in ANCHOR_CONFIGS.keys():
        try:
            users_ref = db.collection('users')
            query = users_ref.where('email', '==', email).limit(1)
            docs = query.get()
            
            if docs:
                user_data = docs[0].to_dict()
                print(f"📱 {email}:")
                print(f"   - Role: {user_data.get('role', 'Not set')}")
                print(f"   - Destination: {user_data.get('destination', 'Not set')}")
                print(f"   - Display Name: {user_data.get('displayName', 'Not set')}\n")
        except Exception as e:
            print(f"❌ Error checking {email}: {e}\n")

def show_ground_truth():
    """Display ground truth distances for reference"""
    print("\n📏 Ground Truth Distances:\n")
    print("- Window ↔ Kitchen: 405 inches (10.287 meters)")
    print("- Window ↔ Meeting Room: 219.96 inches (5.587 meters)") 
    print("- Kitchen ↔ Meeting Room: 243.588 inches (6.187 meters)")

if __name__ == "__main__":
    print("=" * 60)
    print("UWB Navigator - Anchor Destination Update Tool")
    print("=" * 60)
    
    # Update destinations
    update_user_destinations()
    
    # Verify the updates
    verify_destinations()
    
    # Show ground truth for reference
    show_ground_truth()
    
    print("\n" + "=" * 60)
    print("✨ Done! Restart the iOS apps to load new destinations")
    print("=" * 60)