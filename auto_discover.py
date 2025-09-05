#!/usr/bin/env python3
"""
Auto-discovery script for iOS devices that aren't being picked up by Bonjour
Continuously scans the network and registers any UWB Navigator devices
"""

import asyncio
import httpx
import json
import time
from typing import Set, Dict, Any

# Configuration
NETWORK_PREFIX = "10.1.10"  # Your network prefix
START_IP = 100
END_IP = 200
SCAN_INTERVAL = 30  # Seconds between scans
API_SERVER = "http://localhost:8000"

discovered_devices: Set[str] = set()

async def check_device(ip: str, port: int = 8080) -> Dict[str, Any]:
    """Check if a device is running UWB Navigator at the given IP"""
    try:
        async with httpx.AsyncClient(timeout=1.0) as client:
            response = await client.get(f"http://{ip}:{port}/api/status")
            if response.status_code == 200:
                data = response.json()
                return {
                    "ip": ip,
                    "port": port,
                    "email": data.get("email", "unknown"),
                    "role": data.get("role", "unknown"),
                    "battery": data.get("batteryLevel", 0) * 100,
                    "device_name": data.get("deviceName", "Unknown")
                }
    except:
        pass
    return None

async def register_device(ip: str, port: int = 8080) -> bool:
    """Register a device with the FastAPI server"""
    try:
        async with httpx.AsyncClient(timeout=2.0) as client:
            response = await client.post(f"{API_SERVER}/api/register?ip={ip}&port={port}")
            if response.status_code == 200:
                result = response.json()
                return result.get("status") == "success"
    except:
        pass
    return False

async def scan_network():
    """Scan the network for UWB Navigator devices"""
    tasks = []
    for i in range(START_IP, END_IP + 1):
        ip = f"{NETWORK_PREFIX}.{i}"
        tasks.append(check_device(ip))
    
    results = await asyncio.gather(*tasks)
    devices = [r for r in results if r is not None]
    
    return devices

async def main():
    """Main loop that continuously discovers and registers devices"""
    print(f"🔍 Starting auto-discovery for UWB Navigator devices")
    print(f"📡 Scanning network {NETWORK_PREFIX}.{START_IP}-{END_IP}")
    print(f"⏱  Scan interval: {SCAN_INTERVAL} seconds\n")
    
    while True:
        try:
            print(f"[{time.strftime('%H:%M:%S')}] Scanning network...")
            devices = await scan_network()
            
            for device in devices:
                device_key = f"{device['ip']}:{device['email']}"
                
                if device_key not in discovered_devices:
                    # New device found
                    print(f"  ✨ Found new device: {device['email']} ({device['role']}) at {device['ip']}")
                    
                    # Try to register it
                    registered = await register_device(device['ip'], device['port'])
                    if registered:
                        print(f"  ✅ Registered: {device['email']}")
                        discovered_devices.add(device_key)
                    else:
                        print(f"  ⚠️  Failed to register: {device['email']}")
            
            if devices:
                print(f"  📊 Total devices found: {len(devices)} (Anchors: {len([d for d in devices if d['role'] == 'anchor'])}, Navigators: {len([d for d in devices if d['role'] == 'navigator'])})")
            else:
                print(f"  ⏸  No devices found on network")
            
            # Wait before next scan
            await asyncio.sleep(SCAN_INTERVAL)
            
        except KeyboardInterrupt:
            print("\n👋 Stopping auto-discovery")
            break
        except Exception as e:
            print(f"  ❌ Error during scan: {e}")
            await asyncio.sleep(5)

if __name__ == "__main__":
    asyncio.run(main())