#!/usr/bin/env python3
"""
Diagnostic tool to identify UWB Navigator connection issues
Run this to test Bonjour discovery and API connectivity
"""

import socket
import time
import json
import sys
from datetime import datetime
from zeroconf import ServiceBrowser, ServiceListener, Zeroconf
import requests
from typing import Dict, List, Any

class DiagnosticListener(ServiceListener):
    def __init__(self):
        self.discovered_services = {}
        
    def add_service(self, zeroconf: Zeroconf, service_type: str, name: str) -> None:
        info = zeroconf.get_service_info(service_type, name, timeout=3000)
        if info:
            # Parse addresses
            addresses = []
            for addr_bytes in info.addresses:
                try:
                    if len(addr_bytes) == 4:
                        addresses.append(('IPv4', socket.inet_ntoa(addr_bytes)))
                    elif len(addr_bytes) == 16:
                        addr = socket.inet_ntop(socket.AF_INET6, addr_bytes)
                        if '%' in addr:
                            addr = addr.split('%')[0]
                        addresses.append(('IPv6', addr))
                except Exception as e:
                    addresses.append(('Error', str(e)))
            
            # Parse TXT record
            txt_data = {}
            if info.properties:
                for key, value in info.properties.items():
                    try:
                        key_str = key.decode('utf-8', errors='ignore') if isinstance(key, bytes) else str(key)
                        val_str = value.decode('utf-8', errors='ignore') if isinstance(value, bytes) else str(value)
                        txt_data[key_str] = val_str
                    except:
                        pass
            
            self.discovered_services[name] = {
                'addresses': addresses,
                'port': info.port,
                'txt_data': txt_data,
                'discovered_at': datetime.now().isoformat()
            }
            
            print(f"\n✅ Discovered: {name}")
            print(f"   Role: {txt_data.get('role', 'unknown')}")
            print(f"   Email: {txt_data.get('email', 'unknown')}")
            print(f"   Device: {txt_data.get('deviceName', 'unknown')}")
            print(f"   Addresses:")
            for addr_type, addr in addresses:
                print(f"      {addr_type}: {addr}")
            print(f"   Port: {info.port}")

def test_api_connection(ip: str, port: int, ip_version: str = "IPv4") -> Dict[str, Any]:
    """Test API connection to a device"""
    results = {
        'ip': ip,
        'port': port,
        'ip_version': ip_version,
        'endpoints': {}
    }
    
    # Format URL based on IP version
    if ip_version == "IPv6":
        base_url = f"http://[{ip}]:{port}"
    else:
        base_url = f"http://{ip}:{port}"
    
    print(f"\n🔌 Testing connection to {base_url}")
    
    endpoints = ['/api/status', '/api/anchors', '/api/navigators', '/api/distances']
    
    for endpoint in endpoints:
        url = base_url + endpoint
        try:
            start_time = time.time()
            response = requests.get(url, timeout=5)
            elapsed = time.time() - start_time
            
            if response.status_code == 200:
                try:
                    data = response.json()
                    results['endpoints'][endpoint] = {
                        'status': 'success',
                        'status_code': 200,
                        'response_time': elapsed,
                        'data_preview': str(data)[:100] if data else None
                    }
                    print(f"   ✅ {endpoint}: OK ({elapsed:.2f}s)")
                except json.JSONDecodeError:
                    results['endpoints'][endpoint] = {
                        'status': 'json_error',
                        'status_code': response.status_code,
                        'response_time': elapsed
                    }
                    print(f"   ⚠️ {endpoint}: JSON decode error")
            else:
                results['endpoints'][endpoint] = {
                    'status': 'http_error',
                    'status_code': response.status_code,
                    'response_time': elapsed
                }
                print(f"   ❌ {endpoint}: HTTP {response.status_code}")
                
        except requests.exceptions.Timeout:
            results['endpoints'][endpoint] = {'status': 'timeout'}
            print(f"   ⏱️ {endpoint}: Timeout")
        except requests.exceptions.ConnectionError as e:
            results['endpoints'][endpoint] = {'status': 'connection_error', 'error': str(e)}
            print(f"   🔌 {endpoint}: Connection failed")
        except Exception as e:
            results['endpoints'][endpoint] = {'status': 'error', 'error': str(e)}
            print(f"   ❌ {endpoint}: {str(e)}")
    
    return results

def check_port_availability(port: int) -> bool:
    """Check if a port is available for binding"""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind(('', port))
            return True
    except:
        return False

def get_network_interfaces() -> List[Dict[str, str]]:
    """Get all network interfaces and their IPs"""
    interfaces = []
    
    # Get hostname
    hostname = socket.gethostname()
    
    # Get all IPs
    try:
        # IPv4
        ipv4_addrs = socket.gethostbyname_ex(hostname)[2]
        for addr in ipv4_addrs:
            if not addr.startswith("127."):
                interfaces.append({'type': 'IPv4', 'address': addr, 'interface': 'unknown'})
    except:
        pass
    
    # Try to get IPv6
    try:
        info = socket.getaddrinfo(hostname, None, socket.AF_INET6)
        for item in info:
            addr = item[4][0]
            if not addr.startswith("::1") and not addr.startswith("fe80"):
                interfaces.append({'type': 'IPv6', 'address': addr, 'interface': 'unknown'})
    except:
        pass
    
    return interfaces

def main():
    print("=" * 60)
    print("UWB Navigator Connection Diagnostic Tool")
    print("=" * 60)
    
    # 1. Check network interfaces
    print("\n1️⃣ Network Interfaces:")
    interfaces = get_network_interfaces()
    if interfaces:
        for iface in interfaces:
            print(f"   {iface['type']}: {iface['address']}")
    else:
        print("   ❌ No network interfaces found")
    
    # 2. Check common ports
    print("\n2️⃣ Port Availability Check:")
    ports_to_check = [8000, 8080, 8081, 8082, 8083]
    for port in ports_to_check:
        available = check_port_availability(port)
        status = "✅ Available" if available else "❌ In use"
        print(f"   Port {port}: {status}")
    
    # 3. Discover devices via Bonjour
    print("\n3️⃣ Discovering UWB devices via Bonjour...")
    print("   (Waiting 5 seconds for discovery...)")
    
    zeroconf = Zeroconf()
    listener = DiagnosticListener()
    browser = ServiceBrowser(zeroconf, "_uwbnav._tcp.local.", listener)
    
    # Wait for discovery
    time.sleep(5)
    
    # 4. Test connections to discovered devices
    if listener.discovered_services:
        print(f"\n4️⃣ Testing API connections to {len(listener.discovered_services)} devices...")
        
        all_results = []
        for service_name, service_info in listener.discovered_services.items():
            print(f"\n📱 Testing: {service_name}")
            
            for addr_type, addr in service_info['addresses']:
                if addr_type in ['IPv4', 'IPv6']:
                    result = test_api_connection(addr, service_info['port'], addr_type)
                    all_results.append(result)
        
        # 5. Summary
        print("\n5️⃣ Summary:")
        successful_devices = 0
        failed_devices = 0
        
        for result in all_results:
            success_count = sum(1 for e in result['endpoints'].values() if e.get('status') == 'success')
            if success_count > 0:
                successful_devices += 1
                print(f"   ✅ {result['ip']}:{result['port']} ({result['ip_version']}): {success_count}/4 endpoints working")
            else:
                failed_devices += 1
                print(f"   ❌ {result['ip']}:{result['port']} ({result['ip_version']}): No endpoints working")
        
        print(f"\n📊 Final Results:")
        print(f"   Devices discovered: {len(listener.discovered_services)}")
        print(f"   Successful connections: {successful_devices}")
        print(f"   Failed connections: {failed_devices}")
        
        # Save detailed results
        with open('diagnostic_results.json', 'w') as f:
            json.dump({
                'timestamp': datetime.now().isoformat(),
                'discovered_services': listener.discovered_services,
                'connection_tests': all_results,
                'network_interfaces': interfaces
            }, f, indent=2)
        print(f"\n💾 Detailed results saved to diagnostic_results.json")
        
    else:
        print("\n❌ No UWB devices discovered!")
        print("\nPossible issues:")
        print("   1. iOS app not running or API server not started")
        print("   2. Devices not on the same network")
        print("   3. Firewall blocking mDNS/Bonjour")
        print("   4. iOS app needs to be restarted")
    
    # Cleanup
    browser.cancel()
    zeroconf.close()
    
    print("\n✅ Diagnostic complete!")

if __name__ == "__main__":
    main()