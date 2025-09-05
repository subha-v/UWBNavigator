#!/bin/bash

# Auto-discovery script for iOS devices
# Scans network and registers any UWB Navigator devices found

echo "🔍 Starting auto-discovery for UWB Navigator devices"
echo "📡 Scanning network 10.1.10.100-200 every 30 seconds"
echo ""

declare -A registered_devices

while true; do
    echo "[$(date '+%H:%M:%S')] Scanning network..."
    
    found_count=0
    anchor_count=0
    navigator_count=0
    
    # Scan IP range
    for i in {100..200}; do
        ip="10.1.10.$i"
        
        # Check if device responds
        if response=$(curl -s -m 0.5 "http://${ip}:8080/api/status" 2>/dev/null); then
            # Parse response
            email=$(echo "$response" | grep -o '"email":"[^"]*"' | cut -d'"' -f4)
            role=$(echo "$response" | grep -o '"role":"[^"]*"' | cut -d'"' -f4)
            
            if [ -n "$email" ] && [ "$email" != "unknown" ]; then
                device_key="${ip}:${email}"
                
                # Count device types
                ((found_count++))
                if [ "$role" = "anchor" ]; then
                    ((anchor_count++))
                elif [ "$role" = "navigator" ]; then
                    ((navigator_count++))
                fi
                
                # Register if not already registered
                if [ -z "${registered_devices[$device_key]}" ]; then
                    echo "  ✨ Found new device: $email ($role) at $ip"
                    
                    # Try to register
                    if curl -s -X POST "http://localhost:8000/api/register?ip=${ip}&port=8080" | grep -q '"status":"success"'; then
                        echo "  ✅ Registered: $email"
                        registered_devices[$device_key]=1
                    else
                        echo "  ⚠️  Already registered or failed: $email"
                    fi
                fi
            fi
        fi
    done
    
    if [ $found_count -gt 0 ]; then
        echo "  📊 Total: $found_count devices (Anchors: $anchor_count, Navigators: $navigator_count)"
    else
        echo "  ⏸  No devices found"
    fi
    
    # Wait before next scan
    sleep 30
done