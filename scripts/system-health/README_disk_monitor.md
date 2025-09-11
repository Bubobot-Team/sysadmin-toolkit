# Disk Monitor Heartbeat Setup

## Overview
This script monitors disk usage and uses heartbeat monitoring to alert when disk usage exceeds 90%. It works by **NOT** sending a heartbeat when there's a problem, causing your monitoring service to detect the failure.

## Setup

1. **Create Bubobot Monitor**
   - Go to https://app.bubobot.com/
   - Click **Create monitor**
   - In **Select category**, choose **Server**
   - In **Send alert when**, choose **Heartbeat missed**
   - Copy the generated heartbeat URL
   - Configure heartbeat interval to match your cron schedule (e.g., 5 minutes)
   - Save monitor

2. **Configure Heartbeat URL**
   ```bash
   # Edit the script (https://github.com/Bubobot-Team/sysadmin-toolkit/blob/main/scripts/system-health/disk_monitor.sh)
   # and paste the full heartbeat URL from Bubobot
   HEARTBEAT_URL="paste_your_full_heartbeat_url_here"
   ```

3. **Set up Cron Job**
   ```bash
   # Run every 5 minutes
   */5 * * * * /path/to/disk_monitor.sh >> /var/log/disk_monitor.log 2>&1
   ```


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