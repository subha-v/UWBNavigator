#!/usr/bin/env python3
"""
Test script for the Image Similarity Server
Tests various scenarios including Swift app integration
"""

import asyncio
import base64
import json
import time
from pathlib import Path
from typing import Dict, Any

import httpx
from PIL import Image
import io

# Server configuration
SERVER_URL = "http://localhost:8001"
SIMILARITY_ENDPOINT = f"{SERVER_URL}/api/similarity"
SIMILARITY_BASE64_ENDPOINT = f"{SERVER_URL}/api/similarity-base64"
TEST_ENDPOINT = f"{SERVER_URL}/api/test-similarity"
HEALTH_ENDPOINT = f"{SERVER_URL}/health"

# Ground truth images
GROUND_TRUTH_DIR = Path("/Users/subha/Downloads/UWBNavigator-Web/similarity")
GROUND_TRUTH_IMAGES = {
    "Kitchen": GROUND_TRUTH_DIR / "kitchen.png",
    "Meeting Room": GROUND_TRUTH_DIR / "meetingRoom.png",
    "Window": GROUND_TRUTH_DIR / "window.png"
}

def print_test_header(test_name: str):
    """Print a formatted test header"""
    print(f"\n{'='*60}")
    print(f"TEST: {test_name}")
    print(f"{'='*60}")

def print_result(success: bool, message: str, details: Dict[str, Any] = None):
    """Print test result with formatting"""
    status = "✅ PASS" if success else "❌ FAIL"
    print(f"{status}: {message}")
    if details:
        for key, value in details.items():
            print(f"  {key}: {value}")

async def test_server_health():
    """Test if the server is running and healthy"""
    print_test_header("Server Health Check")

    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(HEALTH_ENDPOINT)
            if response.status_code == 200:
                data = response.json()
                print_result(True, "Server is healthy", data)
                return True
            else:
                print_result(False, f"Server returned status {response.status_code}")
                return False
        except httpx.ConnectError:
            print_result(False, f"Cannot connect to server at {SERVER_URL}")
            print("  Make sure the server is running: python3 similarity_server.py")
            return False
        except Exception as e:
            print_result(False, f"Unexpected error: {e}")
            return False

async def test_ground_truth_similarity():
    """Test similarity calculation with ground truth images (should be ~100%)"""
    print_test_header("Ground Truth Similarity Test")

    async with httpx.AsyncClient(timeout=30.0) as client:
        for location, image_path in GROUND_TRUTH_IMAGES.items():
            print(f"\n📍 Testing {location}...")

            if not image_path.exists():
                print_result(False, f"Ground truth image not found: {image_path}")
                continue

            try:
                # Use the test endpoint
                response = await client.post(
                    TEST_ENDPOINT,
                    data={"location": location}
                )

                if response.status_code == 200:
                    data = response.json()
                    score = data.get("similarity_score", 0)

                    # Expect very high similarity (>95%) when comparing with itself
                    if score >= 95:
                        print_result(True, f"{location} similarity: {score:.1f}%",
                                   {"Expected": "~100%", "Actual": f"{score:.1f}%"})
                    else:
                        print_result(False, f"{location} similarity too low: {score:.1f}%",
                                   {"Expected": ">95%", "Actual": f"{score:.1f}%"})
                else:
                    print_result(False, f"Server returned status {response.status_code}")
                    print(f"  Response: {response.text}")

            except Exception as e:
                print_result(False, f"Error testing {location}: {e}")

async def test_multipart_upload():
    """Test multipart form data upload (standard method)"""
    print_test_header("Multipart Form Upload Test")

    async with httpx.AsyncClient(timeout=30.0) as client:
        # Test with Kitchen image
        location = "Kitchen"
        image_path = GROUND_TRUTH_IMAGES[location]

        if not image_path.exists():
            print_result(False, f"Test image not found: {image_path}")
            return

        try:
            with open(image_path, 'rb') as f:
                files = {'image': ('test_image.png', f, 'image/png')}
                data = {
                    'location': location,
                    'navigator_id': 'test_navigator_001',
                    'navigator_name': 'Test Navigator',
                    'anchor_id': 'anchor_kitchen_001'
                }

                response = await client.post(SIMILARITY_ENDPOINT, files=files, data=data)

                if response.status_code == 200:
                    result = response.json()
                    score = result.get('similarity_score', 0)

                    print_result(True, f"Multipart upload successful", {
                        "Location": location,
                        "Similarity": f"{score:.1f}%",
                        "Navigator": result.get('navigator_name')
                    })
                else:
                    print_result(False, f"Server returned status {response.status_code}")
                    print(f"  Response: {response.text}")

        except Exception as e:
            print_result(False, f"Error in multipart upload: {e}")

async def test_base64_upload():
    """Test base64 encoded image upload (for Swift app integration)"""
    print_test_header("Base64 Upload Test (Swift Integration)")

    async with httpx.AsyncClient(timeout=30.0) as client:
        # Test with Window image
        location = "Window"
        image_path = GROUND_TRUTH_IMAGES[location]

        if not image_path.exists():
            print_result(False, f"Test image not found: {image_path}")
            return

        try:
            # Read and encode image as base64
            with open(image_path, 'rb') as f:
                image_bytes = f.read()
                image_base64 = base64.b64encode(image_bytes).decode('utf-8')

            # Prepare request data
            data = {
                'image_base64': image_base64,
                'location': location,
                'navigator_id': 'swift_navigator_001',
                'navigator_name': 'Swift Test Navigator',
                'anchor_id': 'anchor_window_001'
            }

            response = await client.post(SIMILARITY_BASE64_ENDPOINT, data=data)

            if response.status_code == 200:
                result = response.json()
                score = result.get('similarity_score', 0)

                print_result(True, f"Base64 upload successful", {
                    "Location": location,
                    "Similarity": f"{score:.1f}%",
                    "Navigator": result.get('navigator_name'),
                    "Format": "base64"
                })
            else:
                print_result(False, f"Server returned status {response.status_code}")
                print(f"  Response: {response.text}")

        except Exception as e:
            print_result(False, f"Error in base64 upload: {e}")

async def test_cross_location_similarity():
    """Test similarity between different locations (should be low)"""
    print_test_header("Cross-Location Similarity Test")

    async with httpx.AsyncClient(timeout=30.0) as client:
        # Test Kitchen image against Meeting Room location
        test_cases = [
            ("Kitchen", "Meeting Room"),  # Kitchen image, Meeting Room location
            ("Meeting Room", "Window"),   # Meeting Room image, Window location
            ("Window", "Kitchen")         # Window image, Kitchen location
        ]

        for image_location, test_location in test_cases:
            print(f"\n📍 Testing {image_location} image against {test_location} location...")

            image_path = GROUND_TRUTH_IMAGES[image_location]
            if not image_path.exists():
                print_result(False, f"Image not found: {image_path}")
                continue

            try:
                with open(image_path, 'rb') as f:
                    files = {'image': (f'{image_location}.png', f, 'image/png')}
                    data = {
                        'location': test_location,  # Wrong location
                        'navigator_id': 'cross_test_001',
                        'navigator_name': 'Cross Test Navigator'
                    }

                    response = await client.post(SIMILARITY_ENDPOINT, files=files, data=data)

                    if response.status_code == 200:
                        result = response.json()
                        score = result.get('similarity_score', 0)

                        # Expect low similarity (<50%) for different locations
                        if score < 50:
                            print_result(True, f"Cross-location similarity correctly low", {
                                "Image": image_location,
                                "Tested Against": test_location,
                                "Similarity": f"{score:.1f}%",
                                "Expected": "<50%"
                            })
                        else:
                            print_result(False, f"Cross-location similarity too high", {
                                "Image": image_location,
                                "Tested Against": test_location,
                                "Similarity": f"{score:.1f}%",
                                "Expected": "<50%"
                            })
                    else:
                        print_result(False, f"Server returned status {response.status_code}")

            except Exception as e:
                print_result(False, f"Error in cross-location test: {e}")

async def test_invalid_location():
    """Test with invalid location"""
    print_test_header("Invalid Location Test")

    async with httpx.AsyncClient(timeout=30.0) as client:
        # Create a small test image
        img = Image.new('RGB', (100, 100), color='red')
        img_bytes = io.BytesIO()
        img.save(img_bytes, format='PNG')
        img_bytes.seek(0)

        try:
            files = {'image': ('test.png', img_bytes, 'image/png')}
            data = {
                'location': 'Invalid Location',
                'navigator_id': 'error_test_001',
                'navigator_name': 'Error Test Navigator'
            }

            response = await client.post(SIMILARITY_ENDPOINT, files=files, data=data)

            # We expect this to either handle gracefully or return an error
            if response.status_code in [200, 400, 500]:
                print_result(True, f"Invalid location handled (status {response.status_code})")
                if response.status_code == 200:
                    result = response.json()
                    print(f"  Default behavior: {result.get('message', 'N/A')}")
            else:
                print_result(False, f"Unexpected status: {response.status_code}")

        except Exception as e:
            print_result(False, f"Error handling invalid location: {e}")

async def test_performance():
    """Test server performance with multiple requests"""
    print_test_header("Performance Test")

    async with httpx.AsyncClient(timeout=30.0) as client:
        location = "Kitchen"
        image_path = GROUND_TRUTH_IMAGES[location]

        if not image_path.exists():
            print_result(False, f"Test image not found: {image_path}")
            return

        # Prepare image data
        with open(image_path, 'rb') as f:
            image_bytes = f.read()

        num_requests = 5
        start_time = time.time()

        tasks = []
        for i in range(num_requests):
            img_io = io.BytesIO(image_bytes)
            files = {'image': (f'test_{i}.png', img_io, 'image/png')}
            data = {
                'location': location,
                'navigator_id': f'perf_test_{i:03d}',
                'navigator_name': f'Performance Test {i}'
            }

            task = client.post(SIMILARITY_ENDPOINT, files=files, data=data)
            tasks.append(task)

        try:
            responses = await asyncio.gather(*tasks)

            end_time = time.time()
            duration = end_time - start_time
            avg_time = duration / num_requests

            success_count = sum(1 for r in responses if r.status_code == 200)

            print_result(
                success_count == num_requests,
                f"Processed {num_requests} requests in {duration:.2f}s",
                {
                    "Successful": f"{success_count}/{num_requests}",
                    "Average Time": f"{avg_time:.2f}s per request",
                    "Total Duration": f"{duration:.2f}s"
                }
            )

        except Exception as e:
            print_result(False, f"Error in performance test: {e}")

async def main():
    """Run all tests"""
    print("\n" + "="*60)
    print("IMAGE SIMILARITY SERVER TEST SUITE")
    print("="*60)
    print(f"Server URL: {SERVER_URL}")
    print(f"Ground Truth Dir: {GROUND_TRUTH_DIR}")

    # Check server health first
    if not await test_server_health():
        print("\n⚠️  Server is not running. Please start it with:")
        print("    python3 similarity_server.py")
        return

    # Run all tests
    await test_ground_truth_similarity()
    await test_multipart_upload()
    await test_base64_upload()
    await test_cross_location_similarity()
    await test_invalid_location()
    await test_performance()

    print("\n" + "="*60)
    print("TEST SUITE COMPLETED")
    print("="*60)

if __name__ == "__main__":
    asyncio.run(main())