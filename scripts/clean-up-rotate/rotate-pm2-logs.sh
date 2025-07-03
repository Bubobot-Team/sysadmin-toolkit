#!/bin/bash

#===============================================================================
# PM2 Log Cleanup Script
# Version: 1.0.0
# Author: Bubobot Community
# License: MIT
# 
# Description: This script cleans up PM2 logs that are too large
#
# Usage: ./rotate-pm2-logs.sh
#
#===============================================================================

LOG_FILE="/var/log/pm2-cleanup.log"
MAX_SIZE_MB=100  # Maximum log file size in MB before cleanup

# Parse command line arguments
ANALYZE_ONLY=false
EXECUTE_MODE=false

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -a, --analyze     Only analyze and report log sizes (no cleanup)"
    echo "  -e, --execute     Execute cleanup operations"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --analyze      # Just analyze current log sizes"
    echo "  $0 --execute      # Execute the cleanup"
    echo "  $0 -a             # Short form for analyze"
    echo "  $0 -e             # Short form for execute"
    echo ""
    echo "If no option is provided, analyze mode will be used by default."
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--analyze)
            ANALYZE_ONLY=true
            shift
            ;;
        -e|--execute)
            EXECUTE_MODE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Set default mode if no arguments provided
if [ "$ANALYZE_ONLY" = false ] && [ "$EXECUTE_MODE" = false ]; then
    ANALYZE_ONLY=true
fi

# Validate that only one mode is selected
if [ "$ANALYZE_ONLY" = true ] && [ "$EXECUTE_MODE" = true ]; then
    echo "Error: Cannot use both --analyze and --execute modes simultaneously"
    show_usage
    exit 1
fi

# Function to log messages
log_message() {
    local message="$1"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    if [ "$ANALYZE_ONLY" = true ]; then
        echo "$timestamp - [ANALYZE] $message"
    else
        echo "$timestamp - [EXECUTE] $message" | tee -a "$LOG_FILE"
    fi
}

# Function to get all users with home directories
get_all_users() {
    local users=()
    
    # Add root user
    users+=("/root")
    
    # Find all users in /home/
    if [ -d "/home" ]; then
        for user_dir in /home/*; do
            if [ -d "$user_dir" ]; then
                users+=("$user_dir")
            fi
        done
    fi
    
    printf '%s\n' "${users[@]}"
}

# Function to clean logs for a specific user
clean_user_logs() {
    local user_home="$1"
    local pm2_logs_dir="$user_home/.pm2/logs"
    local username=$(basename "$user_home")
    
    if [ ! -d "$pm2_logs_dir" ]; then
        log_message "📂 PM2 logs directory not found for user '$username': $pm2_logs_dir"
        return
    fi
    
    log_message "👤 Processing PM2 logs for user '$username' at: $user_home"
    
    local cleaned_count=0
    local total_size_before=0
    local total_size_after=0
    local files_to_clean=()
    
    # Find and analyze log files
    while IFS= read -r -d '' logfile; do
        if [ -f "$logfile" ]; then
            # Get file size in MB and bytes
            size_mb=$(du -m "$logfile" | cut -f1)
            size_bytes=$(stat -c%s "$logfile" 2>/dev/null || echo 0)
            total_size_before=$((total_size_before + size_bytes))
            
            if [ "$size_mb" -gt "$MAX_SIZE_MB" ]; then
                files_to_clean+=("$logfile")
                if [ "$ANALYZE_ONLY" = true ]; then
                    log_message "  ⚠️  LARGE FILE (needs cleanup): $logfile (${size_mb}MB)"
                else
                    log_message "  🔧 PROCESSING LARGE FILE: $logfile (${size_mb}MB)"
                fi
            else
                log_message "  ✅ OK: $logfile (${size_mb}MB)"
            fi
        fi
    done < <(find "$pm2_logs_dir" -name "*.log" -type f -print0)
    
    # Show summary
    if [ ${#files_to_clean[@]} -gt 0 ]; then
        if [ "$ANALYZE_ONLY" = true ]; then
            log_message "  ⚠️  Found ${#files_to_clean[@]} files that need cleaning (>${MAX_SIZE_MB}MB)"
            log_message "  🛠️  Run with --execute to clean these files"
        else
            log_message "  🔧 Found ${#files_to_clean[@]} files to clean (>${MAX_SIZE_MB}MB)"
        fi
        
        if [ "$EXECUTE_MODE" = true ]; then
            # Execute cleanup
            for logfile in "${files_to_clean[@]}"; do
                size_mb_before=$(du -m "$logfile" | cut -f1)
                
                log_message "  🔄 Truncating: $logfile (${size_mb_before}MB)"
                
                # Keep last 1000 lines and truncate the rest
                if tail -n 1000 "$logfile" > "${logfile}.tmp" 2>/dev/null; then
                    mv "${logfile}.tmp" "$logfile"
                    size_mb_after=$(du -m "$logfile" | cut -f1)
                    
                    log_message "  ✅ Successfully truncated: $logfile (${size_mb_before}MB → ${size_mb_after}MB)"
                    ((cleaned_count++))
                else
                    log_message "  ❌ ERROR: Failed to truncate $logfile"
                    rm -f "${logfile}.tmp" 2>/dev/null
                fi
            done
            
            if [ "$cleaned_count" -gt 0 ]; then
                log_message "  🎉 Successfully cleaned $cleaned_count files for user '$username'"
            fi
        fi
    else
        log_message "  🎯 All log files are within size limit (${MAX_SIZE_MB}MB) - no action needed"
    fi
    
    # Calculate total size after (if executed)
    if [ "$EXECUTE_MODE" = true ]; then
        total_size_after=0
        while IFS= read -r -d '' logfile; do
            if [ -f "$logfile" ]; then
                size_bytes=$(stat -c%s "$logfile" 2>/dev/null || echo 0)
                total_size_after=$((total_size_after + size_bytes))
            fi
        done < <(find "$pm2_logs_dir" -name "*.log" -type f -print0)
        
        # Convert bytes to human readable
        total_mb_before=$((total_size_before / 1024 / 1024))
        total_mb_after=$((total_size_after / 1024 / 1024))
        
        if [ "$total_mb_before" -gt "$total_mb_after" ]; then
            local saved_mb=$((total_mb_before - total_mb_after))
            log_message "  💾 Total size change: ${total_mb_before}MB → ${total_mb_after}MB (saved ${saved_mb}MB)"
        fi
    fi
}

# Function to use PM2's built-in log management for all users
pm2_flush_logs() {
    log_message "🔄 Flushing PM2 logs using pm2 flush command for all users"
    
    # Get all users and try to flush their PM2 logs
    get_all_users | while read -r user_home; do
        local username=$(basename "$user_home")
        
        # Skip if no PM2 directory exists
        if [ ! -d "$user_home/.pm2" ]; then
            continue
        fi
        
        log_message "🧹 Attempting to flush PM2 logs for user: $username"
        
        # Try to run pm2 flush as the user
        if [ "$username" = "root" ]; then
            if pm2 flush 2>/dev/null; then
                log_message "✅ Successfully flushed PM2 logs for root"
            else
                log_message "❌ Failed to flush PM2 logs for root"
            fi
        else
            if sudo -u "$username" pm2 flush 2>/dev/null; then
                log_message "✅ Successfully flushed PM2 logs for $username"
            else
                log_message "❌ Failed to flush PM2 logs for $username"
            fi
        fi
    done
    
    log_message "🏁 PM2 logs flush completed"
}

# Main execution
main() {
    if [ "$ANALYZE_ONLY" = true ]; then
        log_message "🔍 Starting PM2 log analysis (no changes will be made)"
        log_message "📏 Maximum log file size threshold: ${MAX_SIZE_MB}MB"
    else
        log_message "🚀 Starting PM2 log cleanup execution"
        log_message "📏 Maximum log file size threshold: ${MAX_SIZE_MB}MB"
    fi
    
    # Get all users with home directories
    local users=($(get_all_users))
    log_message "👥 Found ${#users[@]} users to check: ${users[*]}"
    
    # Process logs for each user
    for user_home in "${users[@]}"; do
        clean_user_logs "$user_home"
    done
    
    # Show summary
    if [ "$ANALYZE_ONLY" = true ]; then
        log_message "📊 Analysis completed - no changes were made"
        log_message "💡 To execute cleanup, run: $0 --execute"
    else
        log_message "🎉 PM2 log cleanup execution completed"
    fi
    
    log_message "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Run the main function
main