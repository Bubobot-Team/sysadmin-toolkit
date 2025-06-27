#!/bin/bash
#
# Script Name: resource-monitor.sh
# Description: Real-time system resource monitoring with alerting
# Author: SysAdmin Toolkit Team
# Version: 1.0.0
# License: MIT
#

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly LOG_FILE="/var/log/sysadmin-toolkit/${SCRIPT_NAME%.*}.log"
readonly CONFIG_FILE="/etc/sysadmin-toolkit/resource-monitor.conf"

# Default settings
readonly DEFAULT_INTERVAL=30
readonly DEFAULT_CPU_THRESHOLD=80
readonly DEFAULT_MEMORY_THRESHOLD=85
readonly DEFAULT_DISK_THRESHOLD=90
readonly DEFAULT_LOAD_THRESHOLD=5
readonly DEFAULT_DURATION=3600

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Global variables
INTERVAL=$DEFAULT_INTERVAL
CPU_THRESHOLD=$DEFAULT_CPU_THRESHOLD
MEMORY_THRESHOLD=$DEFAULT_MEMORY_THRESHOLD
DISK_THRESHOLD=$DEFAULT_DISK_THRESHOLD
LOAD_THRESHOLD=$DEFAULT_LOAD_THRESHOLD
DURATION=$DEFAULT_DURATION
VERBOSE=false
QUIET=false
JSON_OUTPUT=false
ALERT_WEBHOOK=""
ALERT_EMAIL=""
CONTINUOUS=false
PID_FILE="/var/run/sysadmin-toolkit/resource-monitor.pid"

# Alert tracking
declare -A alert_history
declare -A alert_counters

# Logging functions
log_info() {
    if [[ "$QUIET" == false ]]; then
        echo -e "${GREEN}[INFO]${NC} $*" | tee -a "$LOG_FILE"
    else
        echo "$*" >> "$LOG_FILE"
    fi
}

log_warn() {
    if [[ "$QUIET" == false ]]; then
        echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"
    else
        echo "$*" >> "$LOG_FILE"
    fi
}

log_error() {
    if [[ "$QUIET" == false ]]; then
        echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
    else
        echo "$*" >> "$LOG_FILE"
    fi
}

log_debug() {
    if [[ "$VERBOSE" == true ]] && [[ "$QUIET" == false ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*" | tee -a "$LOG_FILE"
    fi
}

# Initialize logging
init_logging() {
    local log_dir
    log_dir="$(dirname "$LOG_FILE")"
    
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir"
    fi
    
    touch "$LOG_FILE"
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_debug "Loading configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        log_debug "Using default configuration"
    fi
}

# Check if already running
check_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        
        if kill -0 "$pid" 2>/dev/null; then
            log_error "Resource monitor is already running (PID: $pid)"
            exit 1
        else
            log_warn "Removing stale PID file"
            rm -f "$PID_FILE"
        fi
    fi
}

# Create PID file
create_pid_file() {
    local pid_dir
    pid_dir="$(dirname "$PID_FILE")"
    
    if [[ ! -d "$pid_dir" ]]; then
        mkdir -p "$pid_dir"
    fi
    
    echo $$ > "$PID_FILE"
}

# Remove PID file
remove_pid_file() {
    rm -f "$PID_FILE"
}

# Get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Get CPU usage
get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1
}

# Get memory usage
get_memory_usage() {
    local mem_info
    local mem_usage
    
    mem_info=$(free | awk '/^Mem:/ {print $2, $3}')
    read -r mem_total mem_used <<< "$mem_info"
    
    mem_usage=$(echo "scale=2; ($mem_used / $mem_total) * 100" | bc -l)
    echo "$mem_usage"
}

# Get disk usage
get_disk_usage() {
    df -h / | awk 'NR==2 {print $5}' | sed 's/%//'
}

# Get system load
get_system_load() {
    uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ','
}

# Get network statistics
get_network_stats() {
    local interface="eth0"
    
    # Try to find the primary network interface
    if [[ -d "/sys/class/net" ]]; then
        interface=$(ls /sys/class/net/ | grep -E '^(eth|en|wlan)' | head -1)
    fi
    
    if [[ -n "$interface" ]]; then
        local rx_bytes tx_bytes
        rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo "0")
        tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo "0")
        
        echo "$interface:$rx_bytes:$tx_bytes"
    else
        echo "unknown:0:0"
    fi
}

# Get process statistics
get_process_stats() {
    local total_processes
    local running_processes
    local sleeping_processes
    
    total_processes=$(ps aux | wc -l)
    running_processes=$(ps aux | grep -c " R ")
    sleeping_processes=$(ps aux | grep -c " S ")
    
    echo "$total_processes:$running_processes:$sleeping_processes"
}

# Check if value exceeds threshold
check_threshold() {
    local value="$1"
    local threshold="$2"
    local metric="$3"
    
    if (( $(echo "$value > $threshold" | bc -l) )); then
        return 0  # Threshold exceeded
    else
        return 1  # Threshold not exceeded
    fi
}

# Send alert
send_alert() {
    local metric="$1"
    local value="$2"
    local threshold="$3"
    local message="$4"
    
    local alert_key="${metric}_${threshold}"
    local current_time
    current_time=$(date +%s)
    
    # Check if we've already alerted recently (within 5 minutes)
    if [[ -n "${alert_history[$alert_key]:-}" ]]; then
        local last_alert_time="${alert_history[$alert_key]}"
        if (( current_time - last_alert_time < 300 )); then
            return 0  # Skip alert, too recent
        fi
    fi
    
    # Update alert history
    alert_history[$alert_key]=$current_time
    
    # Increment alert counter
    alert_counters[$alert_key]=$((${alert_counters[$alert_key]:-0} + 1))
    
    log_warn "$message"
    
    # Send webhook alert
    if [[ -n "$ALERT_WEBHOOK" ]]; then
        send_webhook_alert "$metric" "$value" "$threshold" "$message"
    fi
    
    # Send email alert
    if [[ -n "$ALERT_EMAIL" ]]; then
        send_email_alert "$metric" "$value" "$threshold" "$message"
    fi
}

# Send webhook alert
send_webhook_alert() {
    local metric="$1"
    local value="$2"
    local threshold="$3"
    local message="$4"
    
    local payload
    payload=$(cat << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "hostname": "$(hostname)",
    "metric": "$metric",
    "value": "$value",
    "threshold": "$threshold",
    "message": "$message",
    "alert_count": "${alert_counters[${metric}_${threshold}]:-1}"
}
EOF
)
    
    if curl -s -X POST -H "Content-Type: application/json" \
        -d "$payload" "$ALERT_WEBHOOK" >/dev/null 2>&1; then
        log_debug "Webhook alert sent successfully"
    else
        log_error "Failed to send webhook alert"
    fi
}

# Send email alert
send_email_alert() {
    local metric="$1"
    local value="$2"
    local threshold="$3"
    local message="$4"
    
    local subject="Resource Monitor Alert - $(hostname)"
    local body
    body=$(cat << EOF
Resource Monitor Alert

Hostname: $(hostname)
Timestamp: $(date)
Metric: $metric
Value: $value
Threshold: $threshold
Message: $message
Alert Count: ${alert_counters[${metric}_${threshold}]:-1}

This is an automated alert from the SysAdmin Toolkit Resource Monitor.
EOF
)
    
    if command -v mail >/dev/null 2>&1; then
        echo "$body" | mail -s "$subject" "$ALERT_EMAIL"
        log_debug "Email alert sent successfully"
    else
        log_error "mail command not available for email alerts"
    fi
}

# Display resource information
display_resources() {
    local timestamp="$1"
    local cpu_usage="$2"
    local memory_usage="$3"
    local disk_usage="$4"
    local load_avg="$5"
    local network_stats="$6"
    local process_stats="$7"
    
    if [[ "$JSON_OUTPUT" == true ]]; then
        display_json_output "$timestamp" "$cpu_usage" "$memory_usage" "$disk_usage" "$load_avg" "$network_stats" "$process_stats"
    else
        display_human_output "$timestamp" "$cpu_usage" "$memory_usage" "$disk_usage" "$load_avg" "$network_stats" "$process_stats"
    fi
}

# Display human-readable output
display_human_output() {
    local timestamp="$1"
    local cpu_usage="$2"
    local memory_usage="$3"
    local disk_usage="$4"
    local load_avg="$5"
    local network_stats="$6"
    local process_stats="$7"
    
    # Parse network stats
    IFS=':' read -r interface rx_bytes tx_bytes <<< "$network_stats"
    
    # Parse process stats
    IFS=':' read -r total_procs running_procs sleeping_procs <<< "$process_stats"
    
    # Clear screen if not quiet
    if [[ "$QUIET" == false ]]; then
        clear
    fi
    
    cat << EOF
${CYAN}=== System Resource Monitor ===${NC}
${BLUE}Timestamp:${NC} $timestamp
${BLUE}Hostname:${NC} $(hostname)

${YELLOW}CPU Usage:${NC} ${cpu_usage}%
${YELLOW}Memory Usage:${NC} ${memory_usage}%
${YELLOW}Disk Usage:${NC} ${disk_usage}%
${YELLOW}Load Average:${NC} $load_avg

${PURPLE}Network Interface:${NC} $interface
${PURPLE}Processes:${NC} Total: $total_procs, Running: $running_procs, Sleeping: $sleeping_procs

${GREEN}Monitoring Interval:${NC} ${INTERVAL}s
${GREEN}Thresholds:${NC} CPU: ${CPU_THRESHOLD}%, Memory: ${MEMORY_THRESHOLD}%, Disk: ${DISK_THRESHOLD}%, Load: ${LOAD_THRESHOLD}

EOF
}

# Display JSON output
display_json_output() {
    local timestamp="$1"
    local cpu_usage="$2"
    local memory_usage="$3"
    local disk_usage="$4"
    local load_avg="$5"
    local network_stats="$6"
    local process_stats="$7"
    
    # Parse network stats
    IFS=':' read -r interface rx_bytes tx_bytes <<< "$network_stats"
    
    # Parse process stats
    IFS=':' read -r total_procs running_procs sleeping_procs <<< "$process_stats"
    
    cat << EOF
{
    "timestamp": "$timestamp",
    "hostname": "$(hostname)",
    "resources": {
        "cpu_usage": $cpu_usage,
        "memory_usage": $memory_usage,
        "disk_usage": $disk_usage,
        "load_average": $load_avg
    },
    "network": {
        "interface": "$interface",
        "rx_bytes": $rx_bytes,
        "tx_bytes": $tx_bytes
    },
    "processes": {
        "total": $total_procs,
        "running": $running_procs,
        "sleeping": $sleeping_procs
    },
    "thresholds": {
        "cpu": $CPU_THRESHOLD,
        "memory": $MEMORY_THRESHOLD,
        "disk": $DISK_THRESHOLD,
        "load": $LOAD_THRESHOLD
    }
}
EOF
}

# Monitor loop
monitor_loop() {
    local start_time
    local end_time
    local current_time
    
    start_time=$(date +%s)
    end_time=$((start_time + DURATION))
    
    log_info "Starting resource monitoring (duration: ${DURATION}s, interval: ${INTERVAL}s)"
    
    while true; do
        current_time=$(date +%s)
        
        # Check if duration exceeded
        if [[ "$CONTINUOUS" == false ]] && [[ $current_time -ge $end_time ]]; then
            log_info "Monitoring duration completed"
            break
        fi
        
        # Get current resource values
        local timestamp
        local cpu_usage
        local memory_usage
        local disk_usage
        local load_avg
        local network_stats
        local process_stats
        
        timestamp=$(get_timestamp)
        cpu_usage=$(get_cpu_usage)
        memory_usage=$(get_memory_usage)
        disk_usage=$(get_disk_usage)
        load_avg=$(get_system_load)
        network_stats=$(get_network_stats)
        process_stats=$(get_process_stats)
        
        # Check thresholds and send alerts
        if check_threshold "$cpu_usage" "$CPU_THRESHOLD" "cpu"; then
            send_alert "cpu" "$cpu_usage" "$CPU_THRESHOLD" "High CPU usage detected: ${cpu_usage}% (threshold: ${CPU_THRESHOLD}%)"
        fi
        
        if check_threshold "$memory_usage" "$MEMORY_THRESHOLD" "memory"; then
            send_alert "memory" "$memory_usage" "$MEMORY_THRESHOLD" "High memory usage detected: ${memory_usage}% (threshold: ${MEMORY_THRESHOLD}%)"
        fi
        
        if check_threshold "$disk_usage" "$DISK_THRESHOLD" "disk"; then
            send_alert "disk" "$disk_usage" "$DISK_THRESHOLD" "High disk usage detected: ${disk_usage}% (threshold: ${DISK_THRESHOLD}%)"
        fi
        
        if check_threshold "$load_avg" "$LOAD_THRESHOLD" "load"; then
            send_alert "load" "$load_avg" "$LOAD_THRESHOLD" "High system load detected: $load_avg (threshold: ${LOAD_THRESHOLD})"
        fi
        
        # Display current status
        display_resources "$timestamp" "$cpu_usage" "$memory_usage" "$disk_usage" "$load_avg" "$network_stats" "$process_stats"
        
        # Sleep until next interval
        sleep "$INTERVAL"
    done
}

# Stop monitoring
stop_monitoring() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        
        if kill -0 "$pid" 2>/dev/null; then
            log_info "Stopping resource monitor (PID: $pid)"
            kill "$pid"
            remove_pid_file
        else
            log_warn "Process not running, removing stale PID file"
            remove_pid_file
        fi
    else
        log_error "PID file not found"
        exit 1
    fi
}

# Show status
show_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        
        if kill -0 "$pid" 2>/dev/null; then
            log_info "Resource monitor is running (PID: $pid)"
            ps -p "$pid" -o pid,ppid,cmd,etime
        else
            log_warn "PID file exists but process is not running"
            remove_pid_file
        fi
    else
        log_info "Resource monitor is not running"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -j|--json)
                JSON_OUTPUT=true
                shift
                ;;
            -c|--continuous)
                CONTINUOUS=true
                shift
                ;;
            --stop)
                stop_monitoring
                exit 0
                ;;
            --status)
                show_status
                exit 0
                ;;
            -i|--interval)
                INTERVAL="$2"
                shift 2
                ;;
            -d|--duration)
                DURATION="$2"
                shift 2
                ;;
            --cpu-threshold)
                CPU_THRESHOLD="$2"
                shift 2
                ;;
            --memory-threshold)
                MEMORY_THRESHOLD="$2"
                shift 2
                ;;
            --disk-threshold)
                DISK_THRESHOLD="$2"
                shift 2
                ;;
            --load-threshold)
                LOAD_THRESHOLD="$2"
                shift 2
                ;;
            --webhook)
                ALERT_WEBHOOK="$2"
                shift 2
                ;;
            --email)
                ALERT_EMAIL="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help information
show_help() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Description: Real-time system resource monitoring with alerting

Options:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -q, --quiet             Suppress output (only log to file)
    -j, --json              Output results in JSON format
    -c, --continuous        Run continuously (ignore duration)
    --stop                  Stop running monitor
    --status                Show monitor status
    -i, --interval N        Set monitoring interval in seconds (default: $DEFAULT_INTERVAL)
    -d, --duration N        Set monitoring duration in seconds (default: $DEFAULT_DURATION)
    --cpu-threshold N       Set CPU usage threshold (default: $DEFAULT_CPU_THRESHOLD)
    --memory-threshold N    Set memory usage threshold (default: $DEFAULT_MEMORY_THRESHOLD)
    --disk-threshold N      Set disk usage threshold (default: $DEFAULT_DISK_THRESHOLD)
    --load-threshold N      Set load average threshold (default: $DEFAULT_LOAD_THRESHOLD)
    --webhook URL           Set webhook URL for alerts
    --email ADDRESS         Set email address for alerts

Examples:
    ${SCRIPT_NAME}
    ${SCRIPT_NAME} --interval 10 --duration 1800
    ${SCRIPT_NAME} --continuous --webhook https://hooks.slack.com/your-webhook
    ${SCRIPT_NAME} --stop
    ${SCRIPT_NAME} --status

Exit Codes:
    0 - Success
    1 - Error occurred
    2 - Already running

EOF
}

# Cleanup function
cleanup() {
    log_debug "Cleaning up..."
    remove_pid_file
}

# Set up trap for cleanup
trap cleanup EXIT

# Main function
main() {
    init_logging
    load_config
    
    log_info "Starting ${SCRIPT_NAME}"
    
    # Check if already running
    check_running
    
    # Create PID file
    create_pid_file
    
    # Start monitoring
    monitor_loop
    
    log_info "Completed ${SCRIPT_NAME}"
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_args "$@"
    main "$@"
fi 