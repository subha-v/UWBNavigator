"""
Enhanced FastAPI server with IPv6 support, thread safety, and comprehensive logging
"""

import asyncio
import json
import logging
import socket
import time
import threading
from typing import Dict, List, Any, Optional, Set
from datetime import datetime, timedelta
from contextlib import asynccontextmanager
from ipaddress import ip_address, IPv4Address, IPv6Address

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import httpx
from zeroconf import ServiceBrowser, ServiceListener, Zeroconf

# Configure comprehensive logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('fastapi_detailed.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Thread-safe global state with locks
discovered_devices_lock = threading.RLock()
discovered_devices: Dict[str, Dict[str, Any]] = {}

device_data_cache_lock = threading.RLock()
device_data_cache: Dict[str, Dict[str, Any]] = {}

websocket_clients_lock = threading.RLock()
websocket_clients: List[WebSocket] = []

# Track device connection attempts
connection_attempts: Dict[str, List[Dict[str, Any]]] = {}
connection_attempts_lock = threading.RLock()

# Global Zeroconf instances
zeroconf_instance: Optional[Zeroconf] = None
service_browser: Optional[ServiceBrowser] = None

class EnhancedIOSDeviceListener(ServiceListener):
    """Enhanced listener with IPv6 support and thread safety"""
    
    def __init__(self):
        self.discovered_count = 0
        self.last_discovery_time = None
    
    def add_service(self, zeroconf: Zeroconf, service_type: str, name: str) -> None:
        """Called when a new service is discovered"""
        try:
            logger.info(f"🔍 Discovering service: {name}")
            info = zeroconf.get_service_info(service_type, name, timeout=3000)
            
            if not info:
                logger.warning(f"⚠️ Could not get service info for {name}")
                return
            
            # Parse all addresses (IPv4 and IPv6)
            addresses = self._parse_addresses(info.addresses)
            if not addresses:
                logger.error(f"❌ No valid addresses found for {name}")
                return
            
            port = info.port
            
            # Parse TXT record for metadata
            txt_data = self._parse_txt_record(info.properties)
            
            # Extract device info
            device_id = txt_data.get('deviceId', name)
            
            # Create device info with all addresses
            device_info = {
                'id': device_id,
                'name': txt_data.get('deviceName', 'Unknown Device'),
                'email': txt_data.get('email', 'unknown'),
                'role': txt_data.get('role', 'unknown'),
                'addresses': addresses,  # Store all addresses
                'ip': addresses.get('ipv4', addresses.get('ipv6')),  # Primary IP (prefer IPv4)
                'port': port,
                'service_name': name,
                'last_seen': datetime.now().isoformat(),
                'status': 'discovered',
                'txt_data': txt_data,
                'discovery_time': datetime.now().isoformat()
            }
            
            # Thread-safe update
            with discovered_devices_lock:
                existing_device = discovered_devices.get(device_id)
                
                # Check for duplicates and clean up
                if existing_device and existing_device.get('service_name') != name:
                    self._cleanup_duplicate_devices(device_id, existing_device['service_name'])
                
                # Store discovered device
                discovered_devices[device_id] = device_info
                self.discovered_count += 1
                self.last_discovery_time = datetime.now()
            
            # Log discovery details
            self._log_discovery(device_info, existing_device)
            
            # Trigger immediate data fetch
            self._trigger_data_fetch(device_id)
            
        except Exception as e:
            logger.error(f"❌ Error adding service {name}: {e}", exc_info=True)
    
    def remove_service(self, zeroconf: Zeroconf, service_type: str, name: str) -> None:
        """Called when a service is removed"""
        logger.info(f"📴 Service removed: {name}")
        
        with discovered_devices_lock:
            for device_id, device in list(discovered_devices.items()):
                if device.get('service_name') == name:
                    device['status'] = 'offline'
                    device['offline_time'] = datetime.now().isoformat()
                    logger.info(f"❌ Device went offline: {device['email']} ({device['role']})")
                    break
    
    def update_service(self, zeroconf: Zeroconf, service_type: str, name: str) -> None:
        """Called when a service is updated"""
        logger.info(f"🔄 Service updated: {name}")
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
    
    def _parse_txt_record(self, properties: Dict[bytes, bytes]) -> Dict[str, str]:
        """Parse TXT record properties"""
        txt_data = {}
        
        if properties:
            for key, value in properties.items():
                try:
                    key_str = key.decode('utf-8', errors='ignore') if isinstance(key, bytes) else str(key)
                    val_str = value.decode('utf-8', errors='ignore') if isinstance(value, bytes) else str(value)
                    txt_data[key_str] = val_str
                except Exception as e:
                    logger.warning(f"Error parsing TXT record: {e}")
        
        return txt_data
    
    def _cleanup_duplicate_devices(self, device_id: str, old_service_name: str):
        """Remove duplicate device entries"""
        for did, dev in list(discovered_devices.items()):
            if dev.get('service_name') == old_service_name and did != device_id:
                del discovered_devices[did]
                logger.debug(f"🧹 Removed duplicate entry for {did}")
    
    def _log_discovery(self, device_info: Dict[str, Any], existing_device: Optional[Dict[str, Any]]):
        """Log device discovery with details"""
        addresses_str = ", ".join([f"{k}: {v}" for k, v in device_info.get('addresses', {}).items()])
        
        if existing_device:
            if (existing_device.get('email') != device_info['email'] or 
                existing_device.get('role') != device_info['role']):
                logger.info(f"📡 Updated device: {device_info['email']} ({device_info['role']})")
            else:
                logger.debug(f"🔄 Refreshed device: {device_info['email']} ({device_info['role']})")
        else:
            logger.info(f"✅ NEW device discovered:")
            logger.info(f"   Email: {device_info['email']}")
            logger.info(f"   Role: {device_info['role']}")
            logger.info(f"   Addresses: {addresses_str}")
            logger.info(f"   Port: {device_info['port']}")
    
    def _trigger_data_fetch(self, device_id: str):
        """Trigger immediate data fetch for device"""
        try:
            loop = asyncio.get_running_loop()
            loop.create_task(fetch_device_data_enhanced(device_id))
            logger.debug(f"📊 Triggered data fetch for {device_id}")
        except RuntimeError:
            logger.debug(f"⏰ Device {device_id} will be fetched in next periodic cycle")

async def fetch_device_data_enhanced(device_id: str) -> None:
    """Enhanced fetch with IPv6 support and multiple retry strategies"""
    
    with discovered_devices_lock:
        device = discovered_devices.get(device_id)
        if not device or device['status'] == 'offline':
            logger.debug(f"⏭️ Skipping fetch for {device_id} (offline or not found)")
            return
    
    # Track this connection attempt
    attempt_info = {
        'timestamp': datetime.now().isoformat(),
        'addresses_tried': [],
        'ports_tried': [],
        'errors': []
    }
    
    # Get all available addresses
    addresses_to_try = []
    if device.get('addresses'):
        # Try IPv4 first if available (better compatibility)
        if 'ipv4' in device['addresses']:
            addresses_to_try.append(device['addresses']['ipv4'])
        if 'ipv6' in device['addresses']:
            addresses_to_try.append(f"[{device['addresses']['ipv6']}]")  # IPv6 URL format
    elif device.get('ip'):
        addresses_to_try.append(device['ip'])
    
    if not addresses_to_try:
        logger.error(f"❌ No addresses available for {device_id}")
        with discovered_devices_lock:
            discovered_devices[device_id]['status'] = 'error'
            discovered_devices[device_id]['error'] = 'No addresses available'
        return
    
    # Try multiple ports
    primary_port = device.get('port', 8080)
    ports_to_try = [primary_port] + [p for p in [8080, 8081, 8082, 8083] if p != primary_port]
    
    logger.info(f"🔌 Attempting to connect to {device['email']} ({device['role']})")
    logger.debug(f"   Addresses: {addresses_to_try}")
    logger.debug(f"   Ports: {ports_to_try}")
    
    async with httpx.AsyncClient(timeout=httpx.Timeout(5.0)) as client:
        for address in addresses_to_try:
            attempt_info['addresses_tried'].append(address)
            
            for port in ports_to_try:
                attempt_info['ports_tried'].append(port)
                
                try:
                    base_url = f"http://{address}:{port}"
                    logger.debug(f"   Trying: {base_url}")
                    
                    # Test connection with status endpoint
                    status_response = await client.get(f"{base_url}/api/status")
                    
                    if status_response.status_code != 200:
                        error_msg = f"Status code {status_response.status_code}"
                        attempt_info['errors'].append(error_msg)
                        logger.debug(f"   ❌ {error_msg}")
                        continue
                    
                    # Success! Fetch all data
                    logger.info(f"✅ Connected to {device['email']} at {base_url}")
                    
                    # Fetch all endpoints in parallel
                    tasks = [
                        client.get(f"{base_url}/api/status"),
                        client.get(f"{base_url}/api/anchors"),
                        client.get(f"{base_url}/api/navigators"),
                        client.get(f"{base_url}/api/distances")
                    ]
                    
                    responses = await asyncio.gather(*tasks, return_exceptions=True)
                    
                    # Process responses
                    data = {
                        'status': {},
                        'anchors': [],
                        'navigators': [],
                        'distances': {}
                    }
                    
                    endpoints = ['status', 'anchors', 'navigators', 'distances']
                    for i, response in enumerate(responses):
                        if isinstance(response, Exception):
                            logger.warning(f"   ⚠️ Error fetching {endpoints[i]}: {response}")
                        elif hasattr(response, 'status_code') and response.status_code == 200:
                            try:
                                data[endpoints[i]] = response.json()
                            except Exception as e:
                                logger.warning(f"   ⚠️ Error parsing {endpoints[i]}: {e}")
                    
                    # Update cache and device status
                    with device_data_cache_lock:
                        device_data_cache[device_id] = {
                            **data,
                            'last_updated': datetime.now().isoformat(),
                            'fetch_address': address,
                            'fetch_port': port
                        }
                    
                    with discovered_devices_lock:
                        discovered_devices[device_id]['status'] = 'connected'
                        discovered_devices[device_id]['last_successful_fetch'] = datetime.now().isoformat()
                        discovered_devices[device_id]['working_address'] = address
                        discovered_devices[device_id]['working_port'] = port
                    
                    # Store successful attempt
                    with connection_attempts_lock:
                        if device_id not in connection_attempts:
                            connection_attempts[device_id] = []
                        attempt_info['success'] = True
                        attempt_info['working_url'] = base_url
                        connection_attempts[device_id].append(attempt_info)
                        # Keep only last 10 attempts
                        connection_attempts[device_id] = connection_attempts[device_id][-10:]
                    
                    # Broadcast update
                    await broadcast_update()
                    
                    return  # Success, exit function
                    
                except httpx.TimeoutException:
                    error_msg = f"Timeout at {address}:{port}"
                    attempt_info['errors'].append(error_msg)
                    logger.debug(f"   ⏱️ {error_msg}")
                except httpx.ConnectError as e:
                    error_msg = f"Connection failed at {address}:{port}: {str(e)}"
                    attempt_info['errors'].append(error_msg)
                    logger.debug(f"   🔌 {error_msg}")
                except Exception as e:
                    error_msg = f"Unexpected error at {address}:{port}: {str(e)}"
                    attempt_info['errors'].append(error_msg)
                    logger.error(f"   ❌ {error_msg}")
    
    # All attempts failed
    logger.error(f"❌ Failed to connect to {device['email']} after trying:")
    logger.error(f"   Addresses: {attempt_info['addresses_tried']}")
    logger.error(f"   Ports: {attempt_info['ports_tried']}")
    logger.error(f"   Errors: {attempt_info['errors']}")
    
    with discovered_devices_lock:
        discovered_devices[device_id]['status'] = 'error'
        discovered_devices[device_id]['last_error'] = datetime.now().isoformat()
        discovered_devices[device_id]['error_details'] = attempt_info['errors']
    
    # Store failed attempt
    with connection_attempts_lock:
        if device_id not in connection_attempts:
            connection_attempts[device_id] = []
        attempt_info['success'] = False
        connection_attempts[device_id].append(attempt_info)
        connection_attempts[device_id] = connection_attempts[device_id][-10:]

async def periodic_fetch():
    """Periodically fetch data from all discovered devices"""
    while True:
        try:
            await asyncio.sleep(2)  # Fetch every 2 seconds
            
            # Get current device list (thread-safe)
            with discovered_devices_lock:
                device_ids = list(discovered_devices.keys())
            
            logger.debug(f"⏰ Periodic fetch for {len(device_ids)} devices")
            
            # Fetch data from all devices concurrently
            tasks = []
            for device_id in device_ids:
                with discovered_devices_lock:
                    device = discovered_devices.get(device_id)
                    if device and device.get('status') != 'offline':
                        tasks.append(fetch_device_data_enhanced(device_id))
            
            if tasks:
                await asyncio.gather(*tasks, return_exceptions=True)
            
        except Exception as e:
            logger.error(f"Error in periodic fetch: {e}", exc_info=True)

async def cleanup_stale_devices():
    """Mark devices as stale if not seen recently"""
    while True:
        try:
            await asyncio.sleep(30)  # Check every 30 seconds
            
            now = datetime.now()
            stale_threshold = timedelta(minutes=2)
            
            with discovered_devices_lock:
                for device_id, device in discovered_devices.items():
                    if device.get('last_seen'):
                        last_seen = datetime.fromisoformat(device['last_seen'])
                        if now - last_seen > stale_threshold and device.get('status') != 'offline':
                            device['status'] = 'stale'
                            logger.warning(f"⏰ Device marked as stale: {device['email']}")
            
        except Exception as e:
            logger.error(f"Error in cleanup task: {e}", exc_info=True)

async def broadcast_update():
    """Broadcast updates to all WebSocket clients"""
    data = await get_aggregated_data()
    
    message = {
        'type': 'update',
        'data': data,
        'timestamp': datetime.now().isoformat()
    }
    
    with websocket_clients_lock:
        disconnected = []
        for client in websocket_clients:
            try:
                await client.send_json(message)
            except:
                disconnected.append(client)
        
        # Remove disconnected clients
        for client in disconnected:
            websocket_clients.remove(client)
            logger.debug(f"🔌 Removed disconnected WebSocket client")

async def get_aggregated_data() -> Dict[str, Any]:
    """Aggregate data from all connected devices (thread-safe)"""
    all_anchors = []
    all_navigators = []
    devices_info = []
    
    with discovered_devices_lock:
        devices_copy = discovered_devices.copy()
    
    with device_data_cache_lock:
        cache_copy = device_data_cache.copy()
    
    # Process discovered devices
    for device_id, device_info in devices_copy.items():
        devices_info.append({
            'id': device_id,
            'name': device_info.get('name', 'Unknown'),
            'email': device_info.get('email', 'unknown'),
            'role': device_info.get('role', 'unknown'),
            'addresses': device_info.get('addresses', {}),
            'port': device_info.get('port'),
            'status': device_info.get('status', 'unknown'),
            'last_seen': device_info.get('last_seen'),
            'battery': cache_copy.get(device_id, {}).get('status', {}).get('batteryLevel')
        })
    
    # Process cached data
    for device_id, cached_data in cache_copy.items():
        device_info = devices_copy.get(device_id, {})
        
        # Aggregate anchors
        for anchor in cached_data.get('anchors', []):
            anchor['source_device'] = device_info.get('email', 'unknown')
            anchor['source_ip'] = device_info.get('working_address', device_info.get('ip'))
            all_anchors.append(anchor)
        
        # Aggregate navigators
        for navigator in cached_data.get('navigators', []):
            navigator['source_device'] = device_info.get('email', 'unknown')
            navigator['source_ip'] = device_info.get('working_address', device_info.get('ip'))
            all_navigators.append(navigator)
    
    return {
        'devices': devices_info,
        'anchors': all_anchors,
        'navigators': all_navigators,
        'timestamp': datetime.now().isoformat(),
        'connection_count': len([d for d in devices_copy.values() if d.get('status') == 'connected'])
    }

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifecycle"""
    global zeroconf_instance, service_browser
    
    logger.info("🚀 Starting Enhanced FastAPI server with IPv6 support")
    
    # Initialize Zeroconf
    zeroconf_instance = Zeroconf()
    listener = EnhancedIOSDeviceListener()
    service_browser = ServiceBrowser(zeroconf_instance, "_uwbnav-http._tcp.local.", listener)
    
    logger.info("📡 Started Bonjour service discovery")
    
    # Start background tasks
    asyncio.create_task(periodic_fetch())
    asyncio.create_task(cleanup_stale_devices())
    
    yield
    
    # Cleanup
    logger.info("🛑 Shutting down...")
    if service_browser:
        service_browser.cancel()
    if zeroconf_instance:
        zeroconf_instance.close()

# Create FastAPI app
app = FastAPI(title="UWB Navigator Enhanced Gateway", lifespan=lifespan)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "UWB Navigator Enhanced Gateway",
        "version": "2.0",
        "features": [
            "IPv6 support",
            "Thread-safe operations",
            "Multiple retry strategies",
            "Comprehensive logging",
            "Connection attempt tracking"
        ],
        "status": "online"
    }

@app.get("/api/devices")
async def get_devices():
    """Get all discovered devices with details"""
    with discovered_devices_lock:
        devices = discovered_devices.copy()
    
    return {
        "count": len(devices),
        "devices": devices,
        "timestamp": datetime.now().isoformat()
    }

@app.get("/api/aggregated")
async def get_aggregated():
    """Get aggregated data from all devices"""
    return await get_aggregated_data()

@app.get("/api/diagnostics")
async def get_diagnostics():
    """Get diagnostic information"""
    with discovered_devices_lock:
        devices = discovered_devices.copy()
    
    with connection_attempts_lock:
        attempts = connection_attempts.copy()
    
    diagnostics = {
        "discovered_devices": len(devices),
        "connected_devices": len([d for d in devices.values() if d.get('status') == 'connected']),
        "error_devices": len([d for d in devices.values() if d.get('status') == 'error']),
        "offline_devices": len([d for d in devices.values() if d.get('status') == 'offline']),
        "connection_attempts": {
            device_id: {
                "total_attempts": len(device_attempts),
                "successful": len([a for a in device_attempts if a.get('success')]),
                "failed": len([a for a in device_attempts if not a.get('success')]),
                "last_attempt": device_attempts[-1] if device_attempts else None
            }
            for device_id, device_attempts in attempts.items()
        }
    }
    
    return diagnostics

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time updates"""
    await websocket.accept()
    
    with websocket_clients_lock:
        websocket_clients.append(websocket)
    
    logger.info(f"📱 New WebSocket client connected (total: {len(websocket_clients)})")
    
    try:
        # Send initial data
        initial_data = await get_aggregated_data()
        await websocket.send_json({
            'type': 'initial',
            'data': initial_data
        })
        
        # Keep connection alive
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        with websocket_clients_lock:
            if websocket in websocket_clients:
                websocket_clients.remove(websocket)
        logger.info(f"📱 WebSocket client disconnected (remaining: {len(websocket_clients)})")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)