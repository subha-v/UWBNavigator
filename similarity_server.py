"""
Standalone Image Similarity Server
Handles image similarity calculations for UWB Navigator
Runs on port 8001
"""

import asyncio
import logging
import socket
import sys
import base64
import io
from typing import Optional, Dict, Any
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, File, Form, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import httpx
import uvicorn
from zeroconf import ServiceInfo, Zeroconf
import uuid

# Add similarity module path
sys.path.append("/Users/subha/Downloads/UWBNavigator-Web/similarity")

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('similarity_server.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Global Zeroconf instance
zeroconf_instance: Optional[Zeroconf] = None
service_info: Optional[ServiceInfo] = None

# Configuration
WEBAPP_URL = "http://localhost:3000"  # Update with actual webapp URL
WEBAPP_UPDATE_ENDPOINT = f"{WEBAPP_URL}/api/navigator-update"

# Create FastAPI app
app = FastAPI(title="UWB Navigator Image Similarity Server")

# Add CORS middleware for webapp and Swift app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup_event():
    """Initialize server and advertise via Bonjour"""
    global zeroconf_instance, service_info

    try:
        # Initialize Zeroconf
        zeroconf_instance = Zeroconf()

        # Get local IP address
        hostname = socket.gethostname()
        local_ip = socket.gethostbyname(hostname)

        # Create service info for similarity server
        service_info = ServiceInfo(
            "_uwb-similarity._tcp.local.",
            "UWB Navigator Similarity Server._uwb-similarity._tcp.local.",
            addresses=[socket.inet_aton(local_ip)],
            port=8001,
            properties={
                'version': '1.0',
                'path': '/api/similarity',
                'description': 'Image similarity calculation service'
            }
        )

        # Register service
        zeroconf_instance.register_service(service_info)
        logger.info(f"✅ Advertising Similarity Server on {local_ip}:8001 via Bonjour")

    except Exception as e:
        logger.error(f"Failed to advertise service via Bonjour: {e}")

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on server shutdown"""
    global zeroconf_instance, service_info

    if service_info and zeroconf_instance:
        zeroconf_instance.unregister_service(service_info)
        logger.info("Unregistered Bonjour service")

    if zeroconf_instance:
        zeroconf_instance.close()
        logger.info("Closed Zeroconf")

@app.get("/")
async def root():
    """Root endpoint with server info"""
    return {
        "service": "UWB Navigator Image Similarity Server",
        "version": "1.0",
        "endpoints": {
            "similarity": "/api/similarity",
            "health": "/health",
            "test": "/api/test-similarity"
        },
        "status": "online",
        "port": 8001
    }

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "service": "similarity-server"
    }

@app.post("/api/similarity")
async def calculate_similarity(
    image: UploadFile = File(...),
    location: str = Form(..., description="Location: Kitchen, Meeting Room, or Window"),
    navigator_id: str = Form(...),
    navigator_name: str = Form(...),
    anchor_id: Optional[str] = Form(None),
    timestamp: Optional[str] = Form(None),
    image_format: Optional[str] = Form("bytes", description="Format: bytes, base64")
):
    """
    Calculate similarity between uploaded image and ground truth for given location.

    Parameters:
    - image: The uploaded image file
    - location: The anchor location (Kitchen, Meeting Room, Window)
    - navigator_id: ID of the navigator
    - navigator_name: Name of the navigator
    - anchor_id: Optional anchor ID
    - timestamp: Optional timestamp
    - image_format: Format of the image (bytes or base64)

    Returns:
    - similarity_score: Percentage similarity (0-100)
    - status: Processing status
    - contract: Smart contract data (if applicable)
    """
    try:
        logger.info(f"📸 Received similarity request from {navigator_name} (ID: {navigator_id}) for location: {location}")

        # Read image data
        image_data = await image.read()

        # Import similarity calculation module
        try:
            from image_similarity import calculate_similarity_from_bytes
        except ImportError as e:
            logger.error(f"Failed to import image_similarity module: {e}")
            raise HTTPException(status_code=500, detail="Image similarity module not available")

        # Calculate similarity score
        try:
            similarity_score = calculate_similarity_from_bytes(image_data, location)
            logger.info(f"✅ Calculated similarity: {similarity_score:.1f}% for {navigator_name} at {location}")
        except Exception as e:
            logger.error(f"Error in similarity calculation: {e}")
            raise HTTPException(status_code=500, detail=f"Similarity calculation failed: {str(e)}")

        # Create response data
        response_data = {
            "success": True,
            "similarity_score": similarity_score,
            "navigator_id": navigator_id,
            "navigator_name": navigator_name,
            "location": location,
            "timestamp": timestamp or datetime.now().isoformat(),
            "message": f"Similarity calculated: {similarity_score:.1f}%"
        }

        # Create smart contract data if score is above threshold
        if similarity_score >= 50:
            contract_data = {
                "txId": f"0x{uuid.uuid4().hex[:8]}",
                "navigatorId": navigator_name,
                "navigatorUserId": navigator_id,
                "anchors": [location],
                "anchorId": anchor_id,
                "asset": "Location verification | Photo attestation",
                "price": 15,
                "currency": "USDC",
                "status": "Settled",
                "qodQuorum": "Pass" if similarity_score >= 50 else "Fail",
                "timestamp": datetime.now().isoformat(),
                "dop": round(similarity_score / 50, 1),  # Degree of precision
                "minAnchors": 1,
                "actualAnchors": 1,
                "similarityScore": similarity_score
            }
            response_data["contract"] = contract_data

        # Notify webapp asynchronously (don't wait for response)
        asyncio.create_task(notify_webapp(response_data))

        return JSONResponse(content=response_data)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Unexpected error in similarity calculation: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Failed to process similarity request: {str(e)}"
        )

@app.post("/api/similarity-base64")
async def calculate_similarity_base64(
    image_base64: str = Form(..., description="Base64 encoded image"),
    location: str = Form(..., description="Location: Kitchen, Meeting Room, or Window"),
    navigator_id: str = Form(...),
    navigator_name: str = Form(...),
    anchor_id: Optional[str] = Form(None),
    timestamp: Optional[str] = Form(None)
):
    """
    Alternative endpoint for Swift app that sends base64 encoded images.
    """
    try:
        logger.info(f"📸 Received base64 similarity request from {navigator_name} for location: {location}")

        # Decode base64 image
        try:
            # Remove data URL prefix if present
            if image_base64.startswith('data:image'):
                image_base64 = image_base64.split(',')[1]

            image_data = base64.b64decode(image_base64)
        except Exception as e:
            logger.error(f"Failed to decode base64 image: {e}")
            raise HTTPException(status_code=400, detail="Invalid base64 image data")

        # Import similarity calculation module
        from image_similarity import calculate_similarity_from_bytes

        # Calculate similarity score
        similarity_score = calculate_similarity_from_bytes(image_data, location)
        logger.info(f"✅ Calculated similarity: {similarity_score:.1f}% for {navigator_name} at {location}")

        # Create response data
        response_data = {
            "success": True,
            "similarity_score": similarity_score,
            "navigator_id": navigator_id,
            "navigator_name": navigator_name,
            "location": location,
            "timestamp": timestamp or datetime.now().isoformat(),
            "message": f"Similarity calculated: {similarity_score:.1f}%"
        }

        # Notify webapp
        asyncio.create_task(notify_webapp(response_data))

        return JSONResponse(content=response_data)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Error in base64 similarity calculation: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/test-similarity")
async def test_similarity(location: str = Form(...)):
    """
    Test endpoint to verify similarity calculation with ground truth images.
    Uses the ground truth image itself as test image to verify 100% match.
    """
    try:
        logger.info(f"🧪 Testing similarity for location: {location}")

        # Map location to ground truth file
        ground_truth_map = {
            "Kitchen": "/Users/subha/Downloads/UWBNavigator-Web/similarity/kitchen.png",
            "Meeting Room": "/Users/subha/Downloads/UWBNavigator-Web/similarity/meetingRoom.png",
            "Window": "/Users/subha/Downloads/UWBNavigator-Web/similarity/window.png"
        }

        if location not in ground_truth_map:
            raise HTTPException(status_code=400, detail=f"Invalid location: {location}")

        gt_path = ground_truth_map[location]

        # Read the ground truth image
        with open(gt_path, 'rb') as f:
            image_data = f.read()

        # Import similarity calculation
        from image_similarity import calculate_similarity_from_bytes

        # Calculate similarity (should be ~100% since comparing with itself)
        similarity_score = calculate_similarity_from_bytes(image_data, location)

        return {
            "success": True,
            "location": location,
            "similarity_score": similarity_score,
            "expected_score": "~100% (testing with ground truth)",
            "message": f"Test successful: {similarity_score:.1f}% match"
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Test failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

async def notify_webapp(data: Dict[str, Any]):
    """
    Send similarity results to webapp for QoD update.
    """
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.post(
                WEBAPP_UPDATE_ENDPOINT,
                json={
                    "type": "navigator_similarity_update",
                    "data": data
                }
            )

            if response.status_code == 200:
                logger.info(f"✅ Successfully notified webapp about similarity update")
            else:
                logger.warning(f"⚠️ Webapp notification returned status {response.status_code}")

    except httpx.ConnectError:
        logger.warning(f"⚠️ Could not connect to webapp at {WEBAPP_UPDATE_ENDPOINT}")
    except Exception as e:
        logger.error(f"❌ Failed to notify webapp: {e}")

def kill_process_on_port(port: int):
    """Kill any process using the specified port"""
    import subprocess
    import platform

    system = platform.system()

    try:
        if system == "Darwin" or system == "Linux":
            # Find process using the port
            result = subprocess.run(
                ["lsof", "-i", f":{port}"],
                capture_output=True,
                text=True
            )

            if result.stdout:
                lines = result.stdout.strip().split('\n')[1:]  # Skip header
                for line in lines:
                    if line:
                        parts = line.split()
                        if len(parts) > 1:
                            pid = parts[1]
                            try:
                                subprocess.run(["kill", "-9", pid], check=False)
                                logger.info(f"Killed process {pid} using port {port}")
                            except Exception as e:
                                logger.warning(f"Could not kill process {pid}: {e}")
        elif system == "Windows":
            # Windows command to find and kill process
            result = subprocess.run(
                ["netstat", "-ano"],
                capture_output=True,
                text=True
            )

            for line in result.stdout.split('\n'):
                if f":{port}" in line and "LISTENING" in line:
                    parts = line.split()
                    if parts:
                        pid = parts[-1]
                        try:
                            subprocess.run(["taskkill", "/F", "/PID", pid], check=False)
                            logger.info(f"Killed process {pid} using port {port}")
                        except Exception as e:
                            logger.warning(f"Could not kill process {pid}: {e}")
    except Exception as e:
        logger.warning(f"Could not check/kill processes on port {port}: {e}")

if __name__ == "__main__":
    import time

    # Kill any existing process on port 8001
    port = 8001
    logger.info(f"🔍 Checking for existing processes on port {port}...")
    kill_process_on_port(port)

    # Small delay to ensure port is released
    time.sleep(0.5)

    # Start the server
    logger.info(f"🚀 Starting Similarity Server on port {port}...")
    logger.info(f"📍 Server will be available at http://localhost:{port}")
    logger.info(f"📸 Similarity endpoint: http://localhost:{port}/api/similarity")

    uvicorn.run(app, host="0.0.0.0", port=port)