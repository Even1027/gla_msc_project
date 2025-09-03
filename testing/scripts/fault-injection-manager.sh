#!/usr/bin/env bash
# fault-injection-manager.sh - container-restart only (Fixed)
# Usage:
#   ./fault-injection-manager.sh container-restart
# Env:
#   REDIS_CONTAINER=redis  REDIS_PORT=6379  RESULTS_DIR=../results

set -euo pipefail

# ---------- Config ----------
REDIS_CONTAINER=${REDIS_CONTAINER:-redis}
REDIS_PORT=${REDIS_PORT:-6379}
RESULTS_DIR=${RESULTS_DIR:-../results}
LOG_TS_FORMAT=${LOG_TS_FORMAT:-"+%Y-%m-%dT%H:%M:%S%z"}

mkdir -p "$RESULTS_DIR/fault_logs"

ts() { date "$LOG_TS_FORMAT" 2>/dev/null || date "+%Y-%m-%dT%H:%M:%S%z"; }

# Enhanced Redis connectivity check
redis_ok() { 
    docker exec -i "$REDIS_CONTAINER" redis-cli -p "$REDIS_PORT" PING >/dev/null 2>&1
}

# FIXED: Enhanced container restart fault injection with better monitoring
fault_container_restart() {
    local log_file="$RESULTS_DIR/fault_logs/injection_container-restart_$(date +%Y%m%d_%H%M%S).log"
    local start_epoch
    start_epoch=$(date +%s)

    {
        echo "# Container Restart Fault Injection"
        echo "Fault=container-restart"
        echo "Start=$(ts)"
        echo "Container=${REDIS_CONTAINER}"
        echo "Port=${REDIS_PORT}"
        echo ""
    } > "$log_file"

    # Check initial state
    echo "=== Initial State Check ===" | tee -a "$log_file"
    if redis_ok; then
        echo "Redis accessible before restart" | tee -a "$log_file"
    else
        echo "WARNING: Redis not accessible before restart" | tee -a "$log_file"
    fi
    echo "" | tee -a "$log_file"

    # Execute container restart
    echo "=== Executing Container Restart ===" | tee -a "$log_file"
    echo "Restarting container $REDIS_CONTAINER..." | tee -a "$log_file"
    
    if ! docker restart "$REDIS_CONTAINER" >/dev/null 2>&1; then
        echo "ERROR: Failed to restart container" | tee -a "$log_file"
        echo "End=$(ts)" >> "$log_file"
        echo "LOG_PATH=$log_file"
        return 1
    fi

    local restart_done
    restart_done=$(date +%s)
    local restart_seconds=$((restart_done - start_epoch))
    echo "Container restart completed in ${restart_seconds}s" | tee -a "$log_file"
    echo "" | tee -a "$log_file"

    # Wait for Redis to become healthy with enhanced monitoring
    echo "=== Waiting for Redis Recovery ===" | tee -a "$log_file"
    local waited=0 
    local max_wait=60
    local check_interval=1
    
    echo "Monitoring Redis recovery (max ${max_wait}s)..." | tee -a "$log_file"
    
    while [ $waited -lt $max_wait ]; do
        if redis_ok; then
            break
        fi
        sleep $check_interval
        waited=$((waited + check_interval))
        
        # Log progress every 5 seconds
        if [ $((waited % 5)) -eq 0 ]; then
            echo "  Recovery check: ${waited}s elapsed, Redis still not ready" | tee -a "$log_file"
        fi
    done

    local recovered
    recovered=$(date +%s)
    local recovery_seconds=$((recovered - restart_done))
    local total_downtime=$((recovered - start_epoch))

    if redis_ok; then
        echo "Redis recovery confirmed after ${recovery_seconds}s" | tee -a "$log_file"
    else
        echo "WARNING: Redis may not have fully recovered within ${max_wait}s" | tee -a "$log_file"
        echo "Final connectivity test failed" | tee -a "$log_file"
    fi

    # Final metrics
    echo "" | tee -a "$log_file"
    echo "=== Final Metrics ===" | tee -a "$log_file"
    {
        echo "RestartSeconds=${restart_seconds}"
        echo "RecoverSeconds=${recovery_seconds}"
        echo "DowntimeSeconds=${total_downtime}"
        echo "MaxWaitSeconds=${max_wait}"
        echo "ActualWaitSeconds=${waited}"
        echo "RecoverySuccessful=$(redis_ok && echo "true" || echo "false")"
        echo "End=$(ts)"
    } | tee -a "$log_file"

    echo ""
    echo "LOG_PATH=$log_file"
}

usage() {
    cat << EOF
Container Restart Fault Injection Manager

Usage: $0 container-restart

Commands:
    container-restart      - Restart Redis container and measure recovery time

Environment Variables:
    REDIS_CONTAINER        - Redis container name (default: redis)
    REDIS_PORT            - Redis port (default: 6379)
    RESULTS_DIR           - Results directory (default: ../results)

Features:
    - Measures restart time and recovery time separately
    - Enhanced monitoring with progress logging
    - Validates Redis accessibility before and after restart
    - Comprehensive timing metrics for academic analysis

Example:
    $0 container-restart   # Restart container and measure recovery
EOF
}

main() {
    case "${1:-}" in
        container-restart) 
            fault_container_restart 
            ;;
        -h|--help|"") 
            usage 
            ;;
        *) 
            echo "Unknown command: $1"
            usage
            exit 1 
            ;;
    esac
}

main "$@"