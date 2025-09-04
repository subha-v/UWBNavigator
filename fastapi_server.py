"""
FastAPI server for UWB Navigator with Bonjour/mDNS device discovery
Automatically discovers iOS devices on the network and aggregates their data
"""

import asyncio
import json
import logging
from typing import Dict, List, Any, Optional
from datetime import datetime, timedelta
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import httpx
from zeroconf import ServiceBrowser, ServiceListener, Zeroconf
import socket
import time

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global state
discovered_devices: Dict[str, Dict[str, Any]] = {}
device_data_cache: Dict[str, Dict[str, Any]] = {}
websocket_clients: List[WebSocket] = []
zeroconf_instance: Optional[Zeroconf] = None
service_browser: Optional[ServiceBrowser] = None

class IOSDeviceListener(ServiceListener):
    """Listener for Bonjour/mDNS service discovery"""
    
    def add_service(self, zeroconf: Zeroconf, service_type: str, name: str) -> None:
        """Called when a new service is discovered"""
        try:
            info = zeroconf.get_service_info(service_type, name)
            if info:
                # Parse service info
                addresses = [socket.inet_ntoa(addr) for addr in info.addresses]
                ip = addresses[0] if addresses else None
                port = info.port
                
                # Parse TXT record for metadata
                txt_data = {}
                if info.properties:
                    for key, value in info.properties.items():
                        if isinstance(value, bytes):
                            txt_data[key.decode('utf-8', errors='ignore')] = value.decode('utf-8', errors='ignore')
                        else:
                            txt_data[str(key)] = str(value)
                
                # Extract device info
                device_id = txt_data.get('deviceId', name)
                device_info = {
                    'id': device_id,
                    'name': txt_data.get('deviceName', 'Unknown Device'),
                    'email': txt_data.get('email', 'unknown'),
                    'role': txt_data.get('role', 'unknown'),
                    'ip': ip,
                    'port': port,
                    'service_name': name,
                    'last_seen': datetime.now().isoformat(),
                    'status': 'discovered',
                    'txt_data': txt_data
                }
                
                # Store discovered device
                discovered_devices[device_id] = device_info
                logger.info(f"✅ Discovered device: {device_info['email']} ({device_info['role']}) at {ip}:{port}")
                
                # Trigger immediate data fetch (only in async context)
                try:
                    loop = asyncio.get_running_loop()
                    loop.create_task(fetch_device_data(device_id))
                except RuntimeError:
                    # No running event loop, will be fetched in periodic fetch
                    logger.debug(f"Device {device_id} will be fetched in next periodic cycle")
                
        except Exception as e:
            logger.error(f"Error adding service {name}: {e}")
    
    def remove_service(self, zeroconf: Zeroconf, service_type: str, name: str) -> None:
        """Called when a service is removed"""
        # Find and mark device as offline
        for device_id, device in list(discovered_devices.items()):
            if device.get('service_name') == name:
                device['status'] = 'offline'
                logger.info(f"❌ Device went offline: {device['email']}")
                break
    
    def update_service(self, zeroconf: Zeroconf, service_type: str, name: str) -> None:
        """Called when a service is updated"""
        self.add_service(zeroconf, service_type, name)

async def fetch_device_data(device_id: str) -> None:
    """Fetch data from a specific iOS device"""
    device = discovered_devices.get(device_id)
    if not device or device['status'] == 'offline':
        return
    
    # Try multiple ports if needed
    ports = [device['port']] if device.get('port') else [8080, 8081, 8082, 8083]
    
    async with httpx.AsyncClient(timeout=2.0) as client:
        for port in ports:
            try:
                base_url = f"http://{device['ip']}:{port}"
                
                # Test connection
                status_response = await client.get(f"{base_url}/api/status")
                if status_response.status_code != 200:
                    continue
                
                # Fetch all endpoints
                tasks = [
                    client.get(f"{base_url}/api/status"),
                    client.get(f"{base_url}/api/anchors"),
                    client.get(f"{base_url}/api/navigators"),
                    client.get(f"{base_url}/api/distances")
                ]
                
                responses = await asyncio.gather(*tasks, return_exceptions=True)
                
                # Process responses
                data = {
                    'device_id': device_id,
                    'device_info': device,
                    'timestamp': datetime.now().isoformat(),
                    'status': {},
                    'anchors': [],
                    'navigators': [],
                    'distances': {}
                }
                
                for i, response in enumerate(responses):
                    if isinstance(response, Exception):
                        continue
                    if response.status_code == 200:
                        try:
                            if i == 0:  # status
                                data['status'] = response.json()
                            elif i == 1:  # anchors
                                anchors_data = response.json()
                                if isinstance(anchors_data, list):
                                    data['anchors'] = anchors_data
                            elif i == 2:  # navigators
                                navigators_data = response.json()
                                if isinstance(navigators_data, list):
                                    data['navigators'] = navigators_data
                            elif i == 3:  # distances
                                data['distances'] = response.json()
                        except Exception as e:
                            logger.error(f"Error parsing response from {device_id}: {e}")
                
                # Update cache
                device_data_cache[device_id] = data
                device['status'] = 'connected'
                device['last_successful_fetch'] = datetime.now().isoformat()
                device['port'] = port  # Save working port
                
                # Notify WebSocket clients
                await broadcast_update()
                
                logger.debug(f"✅ Fetched data from {device['email']} on port {port}")
                return
                
            except Exception as e:
                logger.debug(f"Failed to fetch from {device['ip']}:{port}: {e}")
                continue
    
    # Mark as error if all ports failed
    device['status'] = 'error'
    logger.warning(f"⚠️ Could not fetch data from {device['email']}")

async def broadcast_update():
    """Broadcast updates to all connected WebSocket clients"""
    if not websocket_clients:
        return
    
    message = {
        'type': 'update',
        'data': await get_aggregated_data()
    }
    
    disconnected = []
    for client in websocket_clients:
        try:
            await client.send_json(message)
        except:
            disconnected.append(client)
    
    # Remove disconnected clients
    for client in disconnected:
        websocket_clients.remove(client)

async def get_aggregated_data() -> Dict[str, Any]:
    """Aggregate data from all connected devices"""
    all_anchors = []
    all_navigators = []
    devices_info = []
    
    for device_id, cached_data in device_data_cache.items():
        device_info = discovered_devices.get(device_id, {})
        
        # Add device to devices list
        devices_info.append({
            'id': device_id,
            'name': device_info.get('name', 'Unknown'),
            'email': device_info.get('email', 'unknown'),
            'role': device_info.get('role', 'unknown'),
            'ip': device_info.get('ip'),
            'port': device_info.get('port'),
            'status': device_info.get('status', 'unknown'),
            'last_seen': device_info.get('last_seen'),
            'battery': cached_data.get('status', {}).get('batteryLevel')
        })
        
        # Aggregate anchors
        for anchor in cached_data.get('anchors', []):
            # Add source device info
            anchor['source_device'] = device_info.get('email', 'unknown')
            anchor['source_ip'] = device_info.get('ip')
            all_anchors.append(anchor)
        
        # Aggregate navigators
        for navigator in cached_data.get('navigators', []):
            # Add source device info
            navigator['source_device'] = device_info.get('email', 'unknown')
            navigator['source_ip'] = device_info.get('ip')
            all_navigators.append(navigator)
    
    return {
        'devices': devices_info,
        'anchors': all_anchors,
        'navigators': all_navigators,
        'timestamp': datetime.now().isoformat(),
        'connection_count': len([d for d in discovered_devices.values() if d.get('status') == 'connected'])
    }

async def periodic_fetch():
    """Periodically fetch data from all discovered devices"""
    while True:
        try:
            # Fetch from all discovered devices
            tasks = []
            for device_id in discovered_devices.keys():
                tasks.append(fetch_device_data(device_id))
            
            if tasks:
                await asyncio.gather(*tasks, return_exceptions=True)
            
            # Wait before next fetch
            await asyncio.sleep(1)  # Fetch every second
            
        except Exception as e:
            logger.error(f"Error in periodic fetch: {e}")
            await asyncio.sleep(5)

async def cleanup_stale_devices():
    """Remove devices that haven't been seen recently"""
    while True:
        try:
            await asyncio.sleep(30)  # Check every 30 seconds
            
            cutoff = datetime.now() - timedelta(minutes=2)
            stale_devices = []
            
            for device_id, device in discovered_devices.items():
                last_seen = device.get('last_successful_fetch')
                if last_seen:
                    last_seen_dt = datetime.fromisoformat(last_seen)
                    if last_seen_dt < cutoff and device.get('status') != 'offline':
                        device['status'] = 'stale'
                        stale_devices.append(device['email'])
            
            if stale_devices:
                logger.info(f"Marked stale devices: {', '.join(stale_devices)}")
                await broadcast_update()
                
        except Exception as e:
            logger.error(f"Error in cleanup: {e}")

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifecycle"""
    global zeroconf_instance, service_browser
    
    # Startup
    logger.info("🚀 Starting FastAPI server with Bonjour discovery")
    
    # Start Zeroconf/Bonjour discovery
    zeroconf_instance = Zeroconf()
    listener = IOSDeviceListener()
    service_browser = ServiceBrowser(
        zeroconf_instance,
        ["_uwbnav-http._tcp.local."],  # Only listen for UWB Navigator devices
        listener
    )
    logger.info("📡 Started Bonjour service discovery for UWB Navigator devices")
    
    # Start background tasks
    asyncio.create_task(periodic_fetch())
    asyncio.create_task(cleanup_stale_devices())
    
    yield
    
    # Shutdown
    logger.info("Shutting down...")
    if service_browser:
        service_browser.cancel()
    if zeroconf_instance:
        zeroconf_instance.close()

# Create FastAPI app
app = FastAPI(
    title="UWB Navigator API Gateway",
    description="Aggregates data from iOS UWB devices via Bonjour discovery",
    version="1.0.0",
    lifespan=lifespan
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# API Endpoints

@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "status": "online",
        "service": "UWB Navigator API Gateway",
        "discovered_devices": len(discovered_devices),
        "connected_devices": len([d for d in discovered_devices.values() if d.get('status') == 'connected']),
        "timestamp": datetime.now().isoformat()
    }

@app.get("/api/status")
async def get_status():
    """Get server status and discovered devices"""
    return {
        "status": "online",
        "discovered_devices": list(discovered_devices.values()),
        "connected_count": len([d for d in discovered_devices.values() if d.get('status') == 'connected']),
        "timestamp": datetime.now().isoformat()
    }

@app.get("/api/devices")
async def get_devices():
    """Get list of all discovered devices"""
    return list(discovered_devices.values())

@app.get("/api/anchors")
async def get_anchors():
    """Get aggregated anchor data from all devices"""
    data = await get_aggregated_data()
    return data['anchors']

@app.get("/api/navigators")
async def get_navigators():
    """Get aggregated navigator data from all devices"""
    data = await get_aggregated_data()
    return data['navigators']

@app.get("/api/all")
async def get_all_data():
    """Get all aggregated data"""
    return await get_aggregated_data()

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time updates"""
    await websocket.accept()
    websocket_clients.append(websocket)
    
    # Send initial data
    await websocket.send_json({
        'type': 'initial',
        'data': await get_aggregated_data()
    })
    
    try:
        while True:
            # Keep connection alive and listen for client messages
            data = await websocket.receive_text()
            if data == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        websocket_clients.remove(websocket)
        logger.info("WebSocket client disconnected")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
        if websocket in websocket_clients:
            websocket_clients.remove(websocket)

@app.post("/api/refresh")
async def refresh_discovery():
    """Manually trigger device discovery refresh"""
    tasks = []
    for device_id in discovered_devices.keys():
        tasks.append(fetch_device_data(device_id))
    
    if tasks:
        await asyncio.gather(*tasks, return_exceptions=True)
    
    return {
        "status": "refreshed",
        "devices_checked": len(tasks),
        "timestamp": datetime.now().isoformat()
    }

@app.post("/api/register")
async def register_device(ip: str, port: int = 8080):
    """Manually register a device by IP address (fallback for Bonjour issues)"""
    try:
        # Test connection first
        async with httpx.AsyncClient(timeout=2.0) as client:
            response = await client.get(f"http://{ip}:{port}/api/status")
            if response.status_code == 200:
                status_data = response.json()
                
                # Create device entry
                device_id = status_data.get('email', f"manual-{ip}")
                device_info = {
                    'id': device_id,
                    'name': status_data.get('deviceName', 'Unknown Device'),
                    'email': status_data.get('email', 'unknown'),
                    'role': status_data.get('role', 'unknown'),
                    'ip': ip,
                    'port': port,
                    'service_name': f"manual-{ip}",
                    'last_seen': datetime.now().isoformat(),
                    'status': 'discovered',
                    'manual': True  # Mark as manually registered
                }
                
                discovered_devices[device_id] = device_info
                logger.info(f"✅ Manually registered device: {device_info['email']} ({device_info['role']}) at {ip}:{port}")
                
                # Fetch data immediately
                await fetch_device_data(device_id)
                
                return {
                    "status": "success",
                    "device": device_info,
                    "message": f"Device registered successfully"
                }
    except Exception as e:
        return {
            "status": "error",
            "message": f"Failed to register device: {str(e)}"
        }
    
    return {
        "status": "error",
        "message": "Could not connect to device"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")