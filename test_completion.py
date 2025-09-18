#!/usr/bin/env python3
"""
Test script to simulate a navigator reaching destination and sending completion
"""
import requests
import json
from datetime import datetime
import uuid

def test_navigator_completion():
    # FastAPI server endpoints
    fastapi_url = "http://localhost:8000/api/navigator-completed"
    webapp_url = "http://localhost:3001/api/navigator-update"

    # Simulate navigator completion data
    completion_data = {
        "navigator_id": "test-navigator-123",
        "navigator_name": "Test Navigator",
        "anchor_destination": "Anchor Station A",
        "timestamp": datetime.now().isoformat()
    }

    print("📱 Simulating Navigator Completion...")
    print(f"Navigator: {completion_data['navigator_name']}")
    print(f"Destination: {completion_data['anchor_destination']}")
    print(f"Time: {completion_data['timestamp']}")
    print("-" * 50)

    try:
        # Send to FastAPI server
        print("\n1. Sending to FastAPI server...")
        response = requests.post(fastapi_url, json=completion_data)

        if response.status_code == 200:
            result = response.json()
            print("✅ FastAPI Response:")
            print(json.dumps(result, indent=2))

            # Check if contract was created
            if 'contract' in result:
                print("\n📄 Smart Contract Created:")
                print(f"  - TX ID: {result['contract']['txId']}")
                print(f"  - Navigator: {result['contract']['navigatorId']}")
                print(f"  - Anchor: {result['contract']['anchorPhone']}")
                print(f"  - Price: {result['contract']['price']} {result['contract']['currency']}")
                print(f"  - Status: {result['contract']['status']}")
        else:
            print(f"❌ FastAPI Error: {response.status_code}")
            print(response.text)

    except Exception as e:
        print(f"❌ Error sending to FastAPI: {e}")

    print("\n" + "=" * 50)

    # Now test fetching the contracts from webapp
    try:
        print("\n2. Fetching contracts from webapp...")
        response = requests.get(webapp_url.replace("/navigator-update", "/navigator-update"))

        if response.status_code == 200:
            result = response.json()
            if 'contracts' in result and result['contracts']:
                print(f"✅ Found {len(result['contracts'])} contracts in webapp:")
                for contract in result['contracts'][-3:]:  # Show last 3
                    print(f"\n  Contract {contract.get('txId', 'N/A')[:10]}...")
                    print(f"    Navigator: {contract.get('navigatorId', 'N/A')}")
                    print(f"    Anchor: {contract.get('anchorPhone', 'N/A')}")
                    print(f"    Status: {contract.get('status', 'N/A')}")
            else:
                print("⚠️ No contracts found in webapp yet")
        else:
            print(f"❌ Webapp Error: {response.status_code}")

    except Exception as e:
        print(f"❌ Error fetching from webapp: {e}")

    print("\n" + "=" * 50)
    print("\n✨ Test completed!")
    print("\nIn a real scenario:")
    print("1. Navigator phone shows 'Reached Destination' button when < 0.3m from anchor")
    print("2. User presses button")
    print("3. Smart contract appears in webapp dashboard")
    print("4. Navigator returns to anchor selection screen")

if __name__ == "__main__":
    test_navigator_completion()