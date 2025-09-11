#!/bin/bash

# Bubobot heartbeat URL - replace with your actual heartbeat URL
HEARTBEAT_URL="https://uptime-api.bubobot.com/api/heartbeat/xxx"

# Get disk usage percentage for root filesystem (you can change "/" to monitor other partitions)
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')

# Check if disk usage is under 90%
if [ "$DISK_USAGE" -lt 90 ]; then
    # Disk usage is normal, send heartbeat (monitoring is working)
    curl -s "$HEARTBEAT_URL" > /dev/null
    echo "$(date): Disk usage is ${DISK_USAGE}% - Normal, heartbeat sent"
else
    # Disk usage is over 90%, DON'T send heartbeat 
    # This will cause Bubobot to detect "monitoring failure" and alert
    echo "$(date): CRITICAL! Disk usage is ${DISK_USAGE}% - No heartbeat sent, Bubobot will alert"
fi