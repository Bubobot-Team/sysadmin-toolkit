#!/bin/bash

#===============================================================================
# System Doctor - Intelligent System Health Check & Auto-Recovery
# Version: 1.0.0
# Author: Bubobot Community
# License: MIT
# 
# Description: Production-ready script for automated system health monitoring,
# diagnostics, and self-healing operations. Designed for use in monitoring
# workflows, CI/CD pipelines, and automated incident response.
#
# Usage: ./system-doctor.sh [options]
# Options:
#   --check-only        Run diagnostics without making changes
#   --aggressive-clean  Enable more aggressive cleanup operations
#   --service-restart   Allow automatic service restarts
#   --report-json       Output results in JSON format
#   --verbose           Enable verbose logging
#   --help              Show this help message
#===============================================================================

set -euo pipefail

# Configuration
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="System Doctor"
LOG_FILE="/var/log/system-doctor.log"
TEMP_DIR="/tmp/system-doctor-$$"
JSON_REPORT_FILE="/tmp/system-doctor-report.json"

# Thresholds (configurable via environment variables)
CPU_THRESHOLD=${CPU_THRESHOLD:-80}
MEMORY_THRESHOLD=${MEMORY_THRESHOLD:-85}
DISK_THRESHOLD=${DISK_THRESHOLD:-90}
LOAD_THRESHOLD=${LOAD_THRESHOLD:-10}
LOG_SIZE_THRESHOLD=${LOG_SIZE_THRESHOLD:-1048576}  # 1GB in KB

# Runtime flags
CHECK_ONLY=false
AGGRESSIVE_CLEAN=false
SERVICE_RESTART=false
REPORT_JSON=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Results tracking
declare -A RESULTS
declare -A ACTIONS_TAKEN
declare -a CRITICAL_ISSUES
declare -a WARNINGS

#===============================================================================
# Utility Functions
#===============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    
    if [[ "$VERBOSE" == true ]] || [[ "$level" == "ERROR" ]] || [[ "$level" == "CRITICAL" ]]; then
        case $level in
            "ERROR"|"CRITICAL") echo -e "${RED}[$level] $message${NC}" >&2 ;;
            "WARNING") echo -e "${YELLOW}[$level] $message${NC}" ;;
            "SUCCESS") echo -e "${GREEN}[$level] $message${NC}" ;;
            "INFO") echo -e "${BLUE}[$level] $message${NC}" ;;
            *) echo "[$level] $message" ;;
        esac
    fi
}

print_header() {
    echo "==============================================================================="
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo "Started: $(date)"
    echo "Hostname: $(hostname)"
    echo "==============================================================================="
}

cleanup_on_exit() {
    log "INFO" "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}

#===============================================================================
# System Resource Monitoring
#===============================================================================

check_cpu_usage() {
    log "INFO" "Checking CPU usage..."
    
    # Get CPU usage (average over 1 second)
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    cpu_usage=${cpu_usage%.*}  # Remove decimal part
    
    RESULTS["cpu_usage"]=$cpu_usage
    
    if [[ $cpu_usage -gt $CPU_THRESHOLD ]]; then
        CRITICAL_ISSUES+=("High CPU usage: ${cpu_usage}%")
        log "ERROR" "CPU usage is critically high: ${cpu_usage}%"
        
        # Find top CPU consuming processes
        local top_processes=$(ps aux --sort=-%cpu | head -6 | tail -5)
        log "INFO" "Top CPU consuming processes:\n$top_processes"
        
        return 1
    elif [[ $cpu_usage -gt $((CPU_THRESHOLD - 10)) ]]; then
        WARNINGS+=("Elevated CPU usage: ${cpu_usage}%")
        log "WARNING" "CPU usage is elevated: ${cpu_usage}%"
    else
        log "SUCCESS" "CPU usage is normal: ${cpu_usage}%"
    fi
    
    return 0
}

check_memory_usage() {
    log "INFO" "Checking memory usage..."
    
    # Get memory info
    local mem_info=$(free | grep Mem)
    local total_mem=$(echo $mem_info | awk '{print $2}')
    local used_mem=$(echo $mem_info | awk '{print $3}')
    local memory_percent=$((used_mem * 100 / total_mem))
    
    RESULTS["memory_usage"]=$memory_percent
    RESULTS["memory_total_gb"]=$((total_mem / 1024 / 1024))
    RESULTS["memory_used_gb"]=$((used_mem / 1024 / 1024))
    
    if [[ $memory_percent -gt $MEMORY_THRESHOLD ]]; then
        CRITICAL_ISSUES+=("High memory usage: ${memory_percent}%")
        log "ERROR" "Memory usage is critically high: ${memory_percent}%"
        
        # Find top memory consuming processes
        local top_processes=$(ps aux --sort=-%mem | head -6 | tail -5)
        log "INFO" "Top memory consuming processes:\n$top_processes"
        
        # Check for memory leaks or runaway processes
        check_memory_leaks
        
        return 1
    elif [[ $memory_percent -gt $((MEMORY_THRESHOLD - 10)) ]]; then
        WARNINGS+=("Elevated memory usage: ${memory_percent}%")
        log "WARNING" "Memory usage is elevated: ${memory_percent}%"
    else
        log "SUCCESS" "Memory usage is normal: ${memory_percent}%"
    fi
    
    return 0
}

check_disk_usage() {
    log "INFO" "Checking disk usage..."
    
    local critical_disks=()
    local warning_disks=()
    
    # Check all mounted filesystems
    while IFS= read -r line; do
        local filesystem=$(echo "$line" | awk '{print $1}')
        local usage_percent=$(echo "$line" | awk '{print $5}' | sed 's/%//')
        local mount_point=$(echo "$line" | awk '{print $6}')
        
        # Skip special filesystems
        if [[ "$filesystem" =~ ^(tmpfs|devtmpfs|proc|sysfs|cgroup) ]]; then
            continue
        fi
        
        if [[ $usage_percent -gt $DISK_THRESHOLD ]]; then
            critical_disks+=("$mount_point: ${usage_percent}%")
            log "ERROR" "Disk usage critical on $mount_point: ${usage_percent}%"
        elif [[ $usage_percent -gt $((DISK_THRESHOLD - 10)) ]]; then
            warning_disks+=("$mount_point: ${usage_percent}%")
            log "WARNING" "Disk usage elevated on $mount_point: ${usage_percent}%"
        fi
        
    done < <(df -h | grep -E '^/dev/')
    
    RESULTS["disk_critical"]="${#critical_disks[@]}"
    RESULTS["disk_warnings"]="${#warning_disks[@]}"
    
    if [[ ${#critical_disks[@]} -gt 0 ]]; then
        CRITICAL_ISSUES+=("Critical disk usage: ${critical_disks[*]}")
        return 1
    elif [[ ${#warning_disks[@]} -gt 0 ]]; then
        WARNINGS+=("Elevated disk usage: ${warning_disks[*]}")
    else
        log "SUCCESS" "Disk usage is normal on all filesystems"
    fi
    
    return 0
}

check_system_load() {
    log "INFO" "Checking system load average..."
    
    # Get load averages
    local load_avg=$(uptime | awk -F'load average:' '{ print $2 }' | awk -F',' '{ print $1 }' | tr -d ' ')
    local load_1min=${load_avg%.*}
    
    # Get number of CPU cores
    local cpu_cores=$(nproc)
    local load_per_core=$((${load_1min%.*} / cpu_cores))
    
    RESULTS["load_average"]=$load_avg
    RESULTS["cpu_cores"]=$cpu_cores
    RESULTS["load_per_core"]=$load_per_core
    
    if [[ $load_per_core -gt $LOAD_THRESHOLD ]]; then
        CRITICAL_ISSUES+=("High system load: $load_avg (${load_per_core}x per core)")
        log "ERROR" "System load is critically high: $load_avg"
        return 1
    elif [[ $load_per_core -gt $((LOAD_THRESHOLD / 2)) ]]; then
        WARNINGS+=("Elevated system load: $load_avg")
        log "WARNING" "System load is elevated: $load_avg"
    else
        log "SUCCESS" "System load is normal: $load_avg"
    fi
    
    return 0
}

check_network_connectivity() {
    log "INFO" "Checking network connectivity..."
    
    local dns_check=true
    local internet_check=true
    
    # Check DNS resolution
    if ! nslookup google.com >/dev/null 2>&1; then
        dns_check=false
        CRITICAL_ISSUES+=("DNS resolution failure")
        log "ERROR" "DNS resolution is not working"
    fi
    
    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        internet_check=false
        CRITICAL_ISSUES+=("Internet connectivity failure")
        log "ERROR" "Internet connectivity is not working"
    fi
    
    RESULTS["dns_working"]=$dns_check
    RESULTS["internet_working"]=$internet_check
    
    if [[ "$dns_check" == true ]] && [[ "$internet_check" == true ]]; then
        log "SUCCESS" "Network connectivity is working"
        return 0
    else
        return 1
    fi
}

#===============================================================================
# Service Health Checks
#===============================================================================

check_critical_services() {
    log "INFO" "Checking critical system services..."
    
    # Common critical services to check
    local critical_services=(
        "sshd"
        "systemd-resolved"
        "cron"
        "rsyslog"
    )
    
    # Add web servers if detected
    if systemctl list-units --type=service | grep -q nginx; then
        critical_services+=("nginx")
    fi
    if systemctl list-units --type=service | grep -q apache2; then
        critical_services+=("apache2")
    fi
    if systemctl list-units --type=service | grep -q httpd; then
        critical_services+=("httpd")
    fi
    
    # Add database services if detected
    if systemctl list-units --type=service | grep -q mysql; then
        critical_services+=("mysql")
    fi
    if systemctl list-units --type=service | grep -q postgresql; then
        critical_services+=("postgresql")
    fi
    if systemctl list-units --type=service | grep -q redis; then
        critical_services+=("redis")
    fi
    
    local failed_services=()
    local inactive_services=()
    
    for service in "${critical_services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            log "SUCCESS" "Service $service is active"
        elif systemctl list-units --type=service | grep -q "$service"; then
            if systemctl is-failed "$service" >/dev/null 2>&1; then
                failed_services+=("$service")
                log "ERROR" "Service $service has failed"
            else
                inactive_services+=("$service")
                log "WARNING" "Service $service is inactive"
            fi
        fi
    done
    
    RESULTS["failed_services"]="${#failed_services[@]}"
    RESULTS["inactive_services"]="${#inactive_services[@]}"
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        CRITICAL_ISSUES+=("Failed services: ${failed_services[*]}")
        
        # Attempt to restart failed services if allowed
        if [[ "$SERVICE_RESTART" == true ]] && [[ "$CHECK_ONLY" == false ]]; then
            restart_failed_services "${failed_services[@]}"
        fi
        
        return 1
    elif [[ ${#inactive_services[@]} -gt 0 ]]; then
        WARNINGS+=("Inactive services: ${inactive_services[*]}")
    fi
    
    return 0
}

restart_failed_services() {
    local services=("$@")
    
    for service in "${services[@]}"; do
        log "INFO" "Attempting to restart service: $service"
        
        if systemctl restart "$service" 2>/dev/null; then
            log "SUCCESS" "Successfully restarted service: $service"
            ACTIONS_TAKEN["restart_$service"]="success"
        else
            log "ERROR" "Failed to restart service: $service"
            ACTIONS_TAKEN["restart_$service"]="failed"
        fi
    done
}

#===============================================================================
# Log Management and Cleanup
#===============================================================================

cleanup_system_logs() {
    log "INFO" "Starting system log cleanup..."
    
    local total_freed=0
    
    # Clean journal logs (keep last 7 days)
    if command -v journalctl >/dev/null 2>&1; then
        log "INFO" "Cleaning journalctl logs older than 7 days..."
        local journal_size_before=$(journalctl --disk-usage | awk '{print $6}' | sed 's/[^0-9.]//g')
        
        if [[ "$CHECK_ONLY" == false ]]; then
            journalctl --vacuum-time=7d >/dev/null 2>&1 || true
            local journal_size_after=$(journalctl --disk-usage | awk '{print $6}' | sed 's/[^0-9.]//g')
            local journal_freed=$(echo "$journal_size_before - $journal_size_after" | bc 2>/dev/null || echo "0")
            total_freed=$(echo "$total_freed + $journal_freed" | bc 2>/dev/null || echo "$total_freed")
            ACTIONS_TAKEN["journal_cleanup"]="freed ${journal_freed}MB"
        fi
    fi
    
    # Clean common log directories
    local log_dirs=(
        "/var/log"
        "/var/log/nginx"
        "/var/log/apache2"
        "/var/log/httpd"
        "/tmp"
    )
    
    for log_dir in "${log_dirs[@]}"; do
        if [[ -d "$log_dir" ]]; then
            cleanup_directory_logs "$log_dir"
        fi
    done
    
    # Clean package manager caches
    cleanup_package_cache
    
    RESULTS["disk_space_freed"]="$total_freed MB"
    log "SUCCESS" "Log cleanup completed. Total space freed: $total_freed MB"
}

cleanup_directory_logs() {
    local dir="$1"
    log "INFO" "Cleaning logs in directory: $dir"
    
    # Find and clean large log files
    while IFS= read -r -d '' file; do
        local size_kb=$(du -k "$file" | cut -f1)
        
        if [[ $size_kb -gt $LOG_SIZE_THRESHOLD ]]; then
            local filename=$(basename "$file")
            log "INFO" "Large log file detected: $file (${size_kb}KB)"
            
            if [[ "$CHECK_ONLY" == false ]]; then
                # Safely truncate active log files, remove old ones
                if [[ "$file" =~ \.(log|out)$ ]] && ! [[ "$file" =~ \.[0-9]+$ ]]; then
                    # Active log file - truncate
                    > "$file"
                    log "INFO" "Truncated active log file: $file"
                    ACTIONS_TAKEN["truncate_$(basename "$file")"]="truncated"
                elif [[ "$AGGRESSIVE_CLEAN" == true ]] && [[ "$file" =~ \.(log|out)\.[0-9]+$ ]]; then
                    # Old rotated log file - remove if aggressive cleanup is enabled
                    rm -f "$file"
                    log "INFO" "Removed old log file: $file"
                    ACTIONS_TAKEN["remove_$(basename "$file")"]="removed"
                fi
            fi
        fi
    done < <(find "$dir" -type f \( -name "*.log" -o -name "*.out" -o -name "*.log.*" \) -print0 2>/dev/null)
    
    # Clean temporary files in /tmp
    if [[ "$dir" == "/tmp" ]] && [[ "$AGGRESSIVE_CLEAN" == true ]] && [[ "$CHECK_ONLY" == false ]]; then
        find /tmp -type f -mtime +7 -delete 2>/dev/null || true
        log "INFO" "Cleaned temporary files older than 7 days from /tmp"
        ACTIONS_TAKEN["temp_cleanup"]="completed"
    fi
}

cleanup_package_cache() {
    log "INFO" "Cleaning package manager caches..."
    
    if [[ "$CHECK_ONLY" == false ]]; then
        # Clean APT cache (Debian/Ubuntu)
        if command -v apt-get >/dev/null 2>&1; then
            apt-get clean >/dev/null 2>&1 || true
            apt-get autoremove -y >/dev/null 2>&1 || true
            ACTIONS_TAKEN["apt_cleanup"]="completed"
        fi
        
        # Clean YUM/DNF cache (RHEL/CentOS/Fedora)
        if command -v yum >/dev/null 2>&1; then
            yum clean all >/dev/null 2>&1 || true
            ACTIONS_TAKEN["yum_cleanup"]="completed"
        elif command -v dnf >/dev/null 2>&1; then
            dnf clean all >/dev/null 2>&1 || true
            ACTIONS_TAKEN["dnf_cleanup"]="completed"
        fi
    fi
}

#===============================================================================
# Advanced Diagnostics
#===============================================================================

check_memory_leaks() {
    log "INFO" "Checking for potential memory leaks..."
    
    # Look for processes with excessive memory growth
    local suspicious_processes=$(ps aux --sort=-%mem | head -10 | awk '$4 > 10 {print $11 " " $4"%"}')
    
    if [[ -n "$suspicious_processes" ]]; then
        log "WARNING" "Processes with high memory usage:\n$suspicious_processes"
        WARNINGS+=("High memory processes detected")
    fi
}

check_disk_io() {
    log "INFO" "Checking disk I/O performance..."
    
    if command -v iostat >/dev/null 2>&1; then
        # Get I/O statistics for 2 seconds
        local io_stats=$(iostat -x 1 2 | tail -n +4)
        log "INFO" "Current I/O statistics:\n$io_stats"
    else
        log "WARNING" "iostat not available, skipping I/O check"
    fi
}

#===============================================================================
# Reporting
#===============================================================================

generate_report() {
    local report_file="/tmp/system-doctor-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        print_header
        echo ""
        echo "=== SYSTEM HEALTH SUMMARY ==="
        echo "Critical Issues: ${#CRITICAL_ISSUES[@]}"
        echo "Warnings: ${#WARNINGS[@]}"
        echo "Actions Taken: ${#ACTIONS_TAKEN[@]}"
        echo ""
        
        if [[ ${#CRITICAL_ISSUES[@]} -gt 0 ]]; then
            echo "=== CRITICAL ISSUES ==="
            for issue in "${CRITICAL_ISSUES[@]}"; do
                echo "❌ $issue"
            done
            echo ""
        fi
        
        if [[ ${#WARNINGS[@]} -gt 0 ]]; then
            echo "=== WARNINGS ==="
            for warning in "${WARNINGS[@]}"; do
                echo "⚠️  $warning"
            done
            echo ""
        fi
        
        if [[ ${#ACTIONS_TAKEN[@]} -gt 0 ]]; then
            echo "=== ACTIONS TAKEN ==="
            for action in "${!ACTIONS_TAKEN[@]}"; do
                echo "🔧 $action: ${ACTIONS_TAKEN[$action]}"
            done
            echo ""
        fi
        
        echo "=== SYSTEM METRICS ==="
        for metric in "${!RESULTS[@]}"; do
            echo "$metric: ${RESULTS[$metric]}"
        done
        
    } > "$report_file"
    
    echo "Report saved to: $report_file"
    
    if [[ "$REPORT_JSON" == true ]]; then
        generate_json_report
    fi
}

generate_json_report() {
    local json_output="{
        \"timestamp\": \"$(date -Iseconds)\",
        \"hostname\": \"$(hostname)\",
        \"version\": \"$SCRIPT_VERSION\",
        \"status\": \"$([ ${#CRITICAL_ISSUES[@]} -eq 0 ] && echo "healthy" || echo "unhealthy")\",
        \"critical_issues\": $(printf '%s\n' "${CRITICAL_ISSUES[@]}" | jq -R . | jq -s .),
        \"warnings\": $(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s .),
        \"actions_taken\": $(for k in "${!ACTIONS_TAKEN[@]}"; do echo "\"$k\": \"${ACTIONS_TAKEN[$k]}\""; done | paste -sd, | sed 's/^/{/' | sed 's/$/}/'),
        \"metrics\": $(for k in "${!RESULTS[@]}"; do echo "\"$k\": \"${RESULTS[$k]}\""; done | paste -sd, | sed 's/^/{/' | sed 's/$/)/')
    }"
    
    echo "$json_output" | jq . > "$JSON_REPORT_FILE" 2>/dev/null || echo "$json_output" > "$JSON_REPORT_FILE"
    echo "JSON report saved to: $JSON_REPORT_FILE"
}

#===============================================================================
# Main Execution
#===============================================================================

show_help() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION - Intelligent System Health Check & Auto-Recovery

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --check-only        Run diagnostics without making changes
    --aggressive-clean  Enable more aggressive cleanup operations
    --service-restart   Allow automatic service restarts
    --report-json       Output results in JSON format
    --verbose           Enable verbose logging
    --help              Show this help message

ENVIRONMENT VARIABLES:
    CPU_THRESHOLD       CPU usage threshold percentage (default: 80)
    MEMORY_THRESHOLD    Memory usage threshold percentage (default: 85)
    DISK_THRESHOLD      Disk usage threshold percentage (default: 90)
    LOAD_THRESHOLD      Load average threshold per core (default: 10)
    LOG_SIZE_THRESHOLD  Log file size threshold in KB (default: 1048576)

EXAMPLES:
    # Basic health check with automatic fixes
    $0

    # Check only mode (no changes)
    $0 --check-only

    # Aggressive cleanup with service restarts
    $0 --aggressive-clean --service-restart

    # Generate JSON report for monitoring systems
    $0 --report-json --verbose

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --check-only)
                CHECK_ONLY=true
                shift
                ;;
            --aggressive-clean)
                AGGRESSIVE_CLEAN=true
                shift
                ;;
            --service-restart)
                SERVICE_RESTART=true
                shift
                ;;
            --report-json)
                REPORT_JSON=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

main() {
    parse_arguments "$@"
    
    # Setup
    mkdir -p "$TEMP_DIR"
    trap cleanup_on_exit EXIT
    
    print_header
    
    if [[ "$CHECK_ONLY" == true ]]; then
        log "INFO" "Running in CHECK-ONLY mode - no changes will be made"
    fi
    
    # Initialize log file
    touch "$LOG_FILE"
    
    # Run system checks
    local exit_code=0
    
    check_cpu_usage || exit_code=1
    check_memory_usage || exit_code=1
    check_disk_usage || exit_code=1
    check_system_load || exit_code=1
    check_network_connectivity || exit_code=1
    check_critical_services || exit_code=1
    
    # Advanced diagnostics
    check_disk_io
    
    # Cleanup operations
    if [[ "$CHECK_ONLY" == false ]]; then
        cleanup_system_logs
    fi
    
    # Generate report
    generate_report
    
    # Final status
    if [[ $exit_code -eq 0 ]]; then
        log "SUCCESS" "System health check completed successfully"
        echo -e "\n${GREEN}✅ System is healthy${NC}"
    else
        log "WARNING" "System health check completed with issues"
        echo -e "\n${YELLOW}⚠️  System has issues that require attention${NC}"
    fi
    
    echo "Critical issues: ${#CRITICAL_ISSUES[@]}"
    echo "Warnings: ${#WARNINGS[@]}"
    echo "Actions taken: ${#ACTIONS_TAKEN[@]}"
    
    exit $exit_code
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi