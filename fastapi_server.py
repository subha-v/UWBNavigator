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
                # Parse service info - handle both IPv4 and IPv6
                addresses = self._parse_addresses(info.addresses)
                ip = addresses.get('ipv4', addresses.get('ipv6'))  # Prefer IPv4 for compatibility
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
                
                # Check if this is an update to an existing device (same deviceId but different service name)
                existing_device = discovered_devices.get(device_id)
                if existing_device and existing_device.get('service_name') != name:
                    # Remove old service name entry if it exists
                    for did, dev in list(discovered_devices.items()):
                        if dev.get('service_name') == existing_device.get('service_name') and did != device_id:
                            del discovered_devices[did]
                            logger.debug(f"Removed duplicate entry for {did}")
                
                device_info = {
                    'id': device_id,
                    'name': txt_data.get('deviceName', 'Unknown Device'),
                    'email': txt_data.get('email', 'unknown'),
                    'role': txt_data.get('role', 'unknown'),
                    'addresses': addresses,  # Store all addresses
                    'ip': ip,  # Primary IP for backward compatibility
                    'port': port,
                    'service_name': name,
                    'last_seen': datetime.now().isoformat(),
                    'status': 'discovered',
                    'txt_data': txt_data
                }
                
                # Store discovered device (will overwrite if exists)
                discovered_devices[device_id] = device_info
                
                # Log appropriately
                if existing_device and (existing_device.get('email') != device_info['email'] or existing_device.get('role') != device_info['role']):
                    logger.info(f"📡 Updated device: {device_info['email']} ({device_info['role']}) at {ip}:{port}")
                else:
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
    
    def _parse_addresses(self, raw_addresses: List[bytes]) -> Dict[str, str]:
        """Parse both IPv4 and IPv6 addresses"""
        addresses = {}
        
        for addr_bytes in raw_addresses:
            try:
                # Try IPv4 first
                if len(addr_bytes) == 4:
                    addr = socket.inet_ntoa(addr_bytes)
                    addresses['ipv4'] = addr
                    logger.debug(f"  Found IPv4: {addr}")
                # Try IPv6
                elif len(addr_bytes) == 16:
                    addr = socket.inet_ntop(socket.AF_INET6, addr_bytes)
                    # Clean up IPv6 address (remove zone index if present)
                    if '%' in addr:
                        addr = addr.split('%')[0]
                    addresses['ipv6'] = addr
                    logger.debug(f"  Found IPv6: {addr}")
                else:
                    logger.warning(f"  Unknown address format: {len(addr_bytes)} bytes")
            except Exception as e:
                logger.error(f"  Error parsing address: {e}")
        
        return addresses

async def fetch_device_data(device_id: str) -> None:
    """Fetch data from a specific iOS device with IPv4/IPv6 support"""
    device = discovered_devices.get(device_id)
    if not device or device['status'] == 'offline':
        return
    
    # Get all available addresses to try
    addresses_to_try = []
    if device.get('addresses'):
        # Try IPv4 first if available (better compatibility)
        if 'ipv4' in device['addresses']:
            addresses_to_try.append(device['addresses']['ipv4'])
        if 'ipv6' in device['addresses']:
            # IPv6 addresses need brackets in URLs
            addresses_to_try.append(f"[{device['addresses']['ipv6']}]")
    elif device.get('ip'):
        addresses_to_try.append(device['ip'])
    
    if not addresses_to_try:
        logger.error(f"No addresses available for {device_id}")
        device['status'] = 'error'
        return
    
    # Try multiple ports if needed
    ports = [device['port']] if device.get('port') else [8080, 8081, 8082, 8083]
    
    async with httpx.AsyncClient(timeout=2.0) as client:
        for address in addresses_to_try:
            for port in ports:
                try:
                    base_url = f"http://{address}:{port}"
                    
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
                    device['working_address'] = address  # Save working address
                    
                    # Notify WebSocket clients
                    await broadcast_update()
                    
                    logger.info(f"✅ Connected to {device['email']} at {address}:{port}")
                    return
                    
                except Exception as e:
                    logger.debug(f"Failed to fetch from {address}:{port}: {e}")
                    continue
    
    # Mark as error if all addresses and ports failed
    device['status'] = 'error'
    logger.warning(f"⚠️ Could not fetch data from {device['email']} - tried addresses: {addresses_to_try}")

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
    
    # First, add all discovered devices (including those with errors)
    for device_id, device_info in discovered_devices.items():
        devices_info.append({
            'id': device_id,
            'name': device_info.get('name', 'Unknown'),
            'email': device_info.get('email', 'unknown'),
            'role': device_info.get('role', 'unknown'),
            'addresses': device_info.get('addresses', {}),  # Include all addresses
            'ip': device_info.get('ip'),  # Legacy support
            'port': device_info.get('port'),
            'status': device_info.get('status', 'unknown'),
            'last_seen': device_info.get('last_seen'),
            'battery': device_data_cache.get(device_id, {}).get('status', {}).get('batteryLevel')
        })
        
        # If device has error status but we know its role, add placeholder entry
        if device_info.get('status') in ['error', 'offline', 'stale'] and device_info.get('role'):
            if device_info['role'] == 'anchor':
                # Add placeholder anchor with error status
                # Try to get name from email field first (which contains Firebase UID)
                email_uid = device_info.get('email', '')
                display_name = get_display_name_for_uid(email_uid) if email_uid != 'unknown' else get_display_name_for_uid(device_id)
                destination = get_destination_for_uid(email_uid) if email_uid != 'unknown' else get_destination_for_uid(device_id)
                
                placeholder = {
                    'id': device_id,
                    'name': display_name,
                    'status': 'error',
                    'battery': None,
                    'connectedNavigators': 0,
                    'destination': destination,
                    'error_message': f"Device unreachable at {device_info.get('working_address', device_info.get('ip'))}",
                    'source_device': device_info.get('email', 'unknown'),
                    'source_ip': device_info.get('working_address', device_info.get('ip'))
                }
                all_anchors.append(placeholder)
            elif device_info['role'] == 'navigator':
                # Add placeholder navigator with error status
                placeholder = {
                    'id': device_id,
                    'name': get_display_name_for_uid(device_id),
                    'status': 'error',
                    'battery': None,
                    'connectedAnchors': 0,
                    'error_message': f"Device unreachable at {device_info.get('working_address', device_info.get('ip'))}",
                    'source_device': device_info.get('email', 'unknown'),
                    'source_ip': device_info.get('working_address', device_info.get('ip'))
                }
                all_navigators.append(placeholder)
    
    # Then process cached data for devices that are working
    for device_id, cached_data in device_data_cache.items():
        device_info = discovered_devices.get(device_id, {})
        
        # Aggregate anchors from cached data
        for anchor in cached_data.get('anchors', []):
            # Add source device info
            anchor['source_device'] = device_info.get('email', 'unknown')
            anchor['source_ip'] = device_info.get('working_address', device_info.get('ip'))
            # Don't add if we already added a placeholder
            if not any(a['id'] == anchor.get('id') for a in all_anchors):
                all_anchors.append(anchor)
        
        # Aggregate navigators from cached data
        for navigator in cached_data.get('navigators', []):
            # Add source device info
            navigator['source_device'] = device_info.get('email', 'unknown')
            navigator['source_ip'] = device_info.get('working_address', device_info.get('ip'))
            # Don't add if we already added a placeholder
            if not any(n['id'] == navigator.get('id') for n in all_navigators):
                all_navigators.append(navigator)
    
    return {
        'devices': devices_info,
        'anchors': all_anchors,
        'navigators': all_navigators,
        'timestamp': datetime.now().isoformat(),
        'connection_count': len([d for d in discovered_devices.values() if d.get('status') == 'connected'])
    }

# Helper functions for device name mapping
def get_display_name_for_uid(uid: str) -> str:
    """Get display name for a device UID or email"""
    known_devices = {
        '0o3RPyMtuvSwy1G67WebWQNEQDg2': 'subhavee1',
        'r11EHbHmQYONTjVBXwWp54fi5Ut1': 'akshata',
        'sk8ZPKzrHZcmabLXtEMxZJ6fpF13': 'elena',
        'lTgHZ1VtdHM2EEPqpDLsPER1gnJ2': 'adpatil989',
        # Device IDs that appear in Bonjour
        '4061215B-9D0D-4532-B593-04A214A7AF06': 'subhavee1',
        'AFE370FE-2C4C-4752-A73B-B479EAA892B0': 'akshata',
        '794E13A3-0B3F-4834-B94C-9E7CFF960B1C': 'elena',
        'F6A209A8-53D3-4D76-B84D-77B08ACACB83': 'adpatil989'
    }
    # Also check if the uid itself is one of our Firebase UIDs (used as email field)
    if uid.startswith('0o3RPyMtuvSwy1G'):
        return 'subhavee1'
    elif uid.startswith('r11EHbHmQYONTjV'):
        return 'akshata'
    elif uid.startswith('sk8ZPKzrHZcmabL'):
        return 'elena'
    elif uid.startswith('lTgHZ1VtdHM2EEP'):
        return 'adpatil989'
    
    return known_devices.get(uid, uid[:8] + '...')

def get_destination_for_uid(uid: str) -> str:
    """Get destination for an anchor UID or email"""
    destinations = {
        '0o3RPyMtuvSwy1G67WebWQNEQDg2': 'Window',
        'r11EHbHmQYONTjVBXwWp54fi5Ut1': 'Kitchen', 
        'sk8ZPKzrHZcmabLXtEMxZJ6fpF13': 'Meeting Room',
        # Device IDs
        '4061215B-9D0D-4532-B593-04A214A7AF06': 'Window',
        'AFE370FE-2C4C-4752-A73B-B479EAA892B0': 'Kitchen',
        '794E13A3-0B3F-4834-B94C-9E7CFF960B1C': 'Meeting Room'
    }
    # Check partial UIDs
    if uid.startswith('0o3RPyMtuvSwy1G') or uid == '4061215B-9D0D-4532-B593-04A214A7AF06':
        return 'Window'
    elif uid.startswith('r11EHbHmQYONTjV') or uid == 'AFE370FE-2C4C-4752-A73B-B479EAA892B0':
        return 'Kitchen'
    elif uid.startswith('sk8ZPKzrHZcmabL') or uid == '794E13A3-0B3F-4834-B94C-9E7CFF960B1C':
        return 'Meeting Room'
        
    return destinations.get(uid, 'Unknown')

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