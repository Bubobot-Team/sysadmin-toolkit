# Disk Monitor Heartbeat Setup

## Overview
This script monitors disk usage and uses heartbeat monitoring to alert when disk usage exceeds 90%. It works by **NOT** sending a heartbeat when there's a problem, causing your monitoring service to detect the failure.

## Setup

1. **Configure Heartbeat URL**
   ```bash
   # Edit the script and replace the placeholder URL
   HEARTBEAT_URL="https://uptime-api.bubobot.com/api/heartbeat/{{YOUR_HEARTBEAT_TOKEN}"
   ```

2. **Set up Cron Job**
   ```bash
   # Run every 5 minutes
   */5 * * * * /path/to/disk_monitor.sh >> /var/log/disk_monitor.log 2>&1
   ```

3. **Configure Monitoring Service**
   - Set heartbeat interval to match your cron schedule (e.g., 5 minutes)
   - Configure alert notifications

## How It Works

- **Normal operation** (disk < 90%): Sends heartbeat → No alerts
- **Critical state** (disk ≥ 90%): Skips heartbeat → Monitoring service detects failure and alerts

## Testing

```bash
# Test the script manually
./disk_monitor.sh

# Check logs
tail -f /var/log/disk_monitor.log
```