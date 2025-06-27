# System Doctor JSON Integration Guide

## Overview

The `system-doctor.sh` script now supports JSON output for easy integration with monitoring systems, webhooks, databases, and other automation tools.

## JSON Output Options

### 1. `--report-json` Flag
Generates a JSON report file in addition to the normal text output.

```bash
./system-doctor.sh --report-json
```

This will:
- Run the normal health check
- Save a JSON report to `/tmp/system-doctor-report.json`
- Display normal text output

### 2. `--json-only` Flag
Outputs JSON directly to stdout for easy integration with other tools.

```bash
./system-doctor.sh --json-only
```

This will:
- Run the health check silently (no text output)
- Output JSON directly to stdout
- Perfect for piping to other tools or scripts

### 3. Combined with Other Flags

```bash
# Check-only mode with JSON output
./system-doctor.sh --check-only --json-only

# Aggressive cleanup with JSON report
./system-doctor.sh --aggressive-clean --report-json

# Verbose JSON output
./system-doctor.sh --verbose --json-only
```

## JSON Output Structure

The JSON output contains the following structure:

```json
{
  "timestamp": "2025-01-27T11:00:42+00:00",
  "hostname": "server.example.com",
  "version": "1.0.0",
  "status": "healthy|unhealthy",
  "critical_issues": [
    "High CPU usage: 95%",
    "Critical disk usage: /var: 95%"
  ],
  "warnings": [
    "Elevated memory usage: 75%",
    "Large log files detected: /var/log/nginx/access.log (150MB)"
  ],
  "actions_taken": {
    "journal_cleanup": "freed 50MB from systemd journal logs",
    "truncate_/var/log/nginx/access.log": "truncated 150MB from /var/log/nginx/access.log"
  },
  "metrics": {
    "cpu_usage": "25",
    "memory_usage": "65",
    "memory_total_gb": "16",
    "memory_used_gb": "10",
    "disk_critical": "0",
    "disk_warnings": "1",
    "load_average": "2.5",
    "cpu_cores": "8",
    "load_per_core": "0.3",
    "dns_working": "true",
    "internet_working": "true",
    "failed_services": "0",
    "inactive_services": "1",
    "large_log_files": "2",
    "large_tmp_files": "0",
    "disk_space_freed": "200 MB"
  },
  "summary": {
    "critical_issues_count": 0,
    "warnings_count": 2,
    "actions_taken_count": 2,
    "exit_code": 0
  }
}
```

## Integration Examples

### 1. Basic JSON Parsing

```bash
# Get just the summary
./system-doctor.sh --json-only | jq '.summary'

# Check if system is healthy
./system-doctor.sh --json-only | jq -r '.status'

# Get critical issues count
./system-doctor.sh --json-only | jq -r '.summary.critical_issues_count'
```

### 2. Monitoring Integration

```bash
# Create Prometheus-style metrics
./system-doctor.sh --json-only | jq -r '
  "# HELP system_doctor_cpu_usage CPU usage percentage\n" +
  "# TYPE system_doctor_cpu_usage gauge\n" +
  "system_doctor_cpu_usage{hostname=\"" + .hostname + "\"} " + .metrics.cpu_usage + "\n" +
  "# HELP system_doctor_memory_usage Memory usage percentage\n" +
  "# TYPE system_doctor_memory_usage gauge\n" +
  "system_doctor_memory_usage{hostname=\"" + .hostname + "\"} " + .metrics.memory_usage
'
```

### 3. Webhook Integration

```bash
# Send to webhook if system is unhealthy
json_output=$(./system-doctor.sh --json-only)
status=$(echo "$json_output" | jq -r '.status')

if [[ "$status" == "unhealthy" ]]; then
    curl -X POST -H "Content-Type: application/json" \
         -d "$json_output" \
         https://your-webhook-url.com/alert
fi
```

### 4. Database Logging

```bash
# Log to database
json_output=$(./system-doctor.sh --json-only)
timestamp=$(echo "$json_output" | jq -r '.timestamp')
hostname=$(echo "$json_output" | jq -r '.hostname')
status=$(echo "$json_output" | jq -r '.status')

mysql -u user -p database -e "
INSERT INTO system_health_checks (timestamp, hostname, status, raw_data)
VALUES ('$timestamp', '$hostname', '$status', '$(echo "$json_output" | jq -c .)');
"
```

### 5. Alerting Script

```bash
#!/bin/bash
json_output=$(./system-doctor.sh --json-only)
critical_count=$(echo "$json_output" | jq -r '.summary.critical_issues_count')

if [[ $critical_count -gt 0 ]]; then
    echo "ALERT: $critical_count critical issues detected!"
    echo "$json_output" | jq -r '.critical_issues[]'
    # Send email, SMS, or other alert
fi
```

## Example Integration Script

Run the provided example script to see various integration patterns:

```bash
./example-json-integration.sh
```

This script demonstrates:
- Basic JSON parsing
- Status-based decision making
- Prometheus metrics generation
- Webhook payload creation
- Database logging examples

## Requirements

- `jq` (optional but recommended for JSON parsing)
  - Install on Ubuntu/Debian: `sudo apt-get install jq`
  - Install on macOS: `brew install jq`
  - Install on CentOS/RHEL: `sudo yum install jq`

## Environment Variables

You can customize thresholds via environment variables:

```bash
export CPU_THRESHOLD=70
export MEMORY_THRESHOLD=80
export DISK_THRESHOLD=85
export LOG_SIZE_THRESHOLD=51200  # 50MB in KB

./system-doctor.sh --json-only
```

## Error Handling

The script returns appropriate exit codes:
- `0`: System is healthy
- `1`: System has critical issues

This makes it easy to integrate with monitoring systems:

```bash
./system-doctor.sh --json-only
exit_code=$?

if [[ $exit_code -ne 0 ]]; then
    echo "System health check failed with exit code $exit_code"
    # Handle failure
fi
```

## Best Practices

1. **Use `--check-only` for monitoring**: Avoid making changes during monitoring runs
2. **Parse exit codes**: Check the exit code for quick health status
3. **Handle missing jq**: Provide fallback parsing when jq is not available
4. **Log raw JSON**: Store the complete JSON output for debugging
5. **Set appropriate thresholds**: Adjust thresholds based on your system requirements
6. **Use JSON-only for automation**: Use `--json-only` when integrating with other tools

## Troubleshooting

### JSON Output Issues
- Ensure the script has execute permissions: `chmod +x system-doctor.sh`
- Check if `jq` is installed for pretty-printed JSON
- Verify the script runs without errors in normal mode first

### Integration Issues
- Test JSON parsing with `jq` before implementing
- Handle cases where metrics might be missing (use `// "default"` in jq)
- Consider the exit code for automated decision making
- Log both the JSON output and any parsing errors 