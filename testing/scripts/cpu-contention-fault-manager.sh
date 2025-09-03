#!/usr/bin/env bash
# cpu-contention-fault-manager.sh - Fixed CPU Contention Fault Injection
# Fixed Unicode, process handling, and MinGW compatibility

set -euo pipefail

# ---------- Configuration ----------
REDIS_CONTAINER=${REDIS_CONTAINER:-redis}
REDIS_PORT=${REDIS_PORT:-6379}
RESULTS_DIR=${RESULTS_DIR:-../results}
LOG_TS_FORMAT=${LOG_TS_FORMAT:-"+%Y-%m-%dT%H:%M:%S%z"}

# CPU stress configuration
CPU_STRESS_PROCESSES=${CPU_STRESS_PROCESSES:-0}  # 0 = auto-detect cores
CPU_STRESS_METHODS=${CPU_STRESS_METHODS:-"yes,dd,gzip"}  # Multiple stress methods

mkdir -p "$RESULTS_DIR/fault_logs"

ts() { date "$LOG_TS_FORMAT" 2>/dev/null || date "+%Y-%m-%dT%H:%M:%S%z"; }

# Enhanced Redis connectivity check with timing
redis_ok() {
    local start_ms=$(date +%s%3N 2>/dev/null || echo "$(date +%s)000")
    if docker exec -i "$REDIS_CONTAINER" redis-cli -p "$REDIS_PORT" ping >/dev/null 2>&1; then
        local end_ms=$(date +%s%3N 2>/dev/null || echo "$(date +%s)000")
        local latency=$((end_ms - start_ms))
        echo "$latency"  # Return latency in milliseconds
        return 0
    else
        echo "timeout"
        return 1
    fi
}

# Get container CPU information
get_container_cpu_info() {
    local cpu_count
    cpu_count=$(docker exec -i "$REDIS_CONTAINER" nproc 2>/dev/null || echo "2")
    
    local cpu_limit
    cpu_limit=$(docker exec -i "$REDIS_CONTAINER" cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us 2>/dev/null || echo "-1")
    
    local cpu_period
    cpu_period=$(docker exec -i "$REDIS_CONTAINER" cat /sys/fs/cgroup/cpu/cpu.cfs_period_us 2>/dev/null || echo "100000")
    
    echo "CPUCores=$cpu_count"
    echo "CPUQuota=$cpu_limit"
    echo "CPUPeriod=$cpu_period"
    
    # Calculate effective CPU limit
    if [ "$cpu_limit" != "-1" ] && [ "$cpu_period" != "0" ]; then
        local effective_cores=$((cpu_limit / cpu_period))
        echo "EffectiveCores=$effective_cores"
        echo "$effective_cores"
    else
        echo "EffectiveCores=$cpu_count"
        echo "$cpu_count"
    fi
}

# FIXED: More robust CPU stress process detection
check_cpu_stress() {
    local stress_info
    stress_info=$(docker exec -i "$REDIS_CONTAINER" sh -c '
        # Check if pgrep is available, fallback to ps
        if command -v pgrep >/dev/null 2>&1; then
            yes_count=$(pgrep -c yes 2>/dev/null || echo "0")
            dd_count=$(pgrep -c -f "dd if=/dev/zero" 2>/dev/null || echo "0") 
            gzip_count=$(pgrep -c -f "gzip.*dev/zero" 2>/dev/null || echo "0")
        else
            # Fallback to ps
            yes_count=$(ps aux | grep -c "[y]es" 2>/dev/null || echo "0")
            dd_count=$(ps aux | grep -c "[d]d if=/dev/zero" 2>/dev/null || echo "0")
            gzip_count=$(ps aux | grep -c "[g]zip.*dev/zero" 2>/dev/null || echo "0")
        fi
        total=$((yes_count + dd_count + gzip_count))
        echo "yes:$yes_count,dd:$dd_count,gzip:$gzip_count,total:$total"
    ' 2>/dev/null || echo "yes:0,dd:0,gzip:0,total:0")
    
    echo "$stress_info"
}

# FIXED: Enhanced CPU stress with proper process handling
start_cpu_stress() {
    local target_processes="${1:-$CPU_STRESS_PROCESSES}"
    
    # Auto-detect CPU cores if not specified
    if [ "$target_processes" -eq 0 ]; then
        target_processes=$(get_container_cpu_info | tail -1)
    fi
    
    echo "Starting enhanced CPU stress with $target_processes processes..."
    
    # Calculate processes per method
    local methods=3  # yes, dd, gzip
    local per_method=$((target_processes / methods))
    local remainder=$((target_processes % methods))
    
    local yes_procs=$per_method
    local dd_procs=$per_method
    local gzip_procs=$((per_method + remainder))
    
    echo "  CPU stress distribution: yes=$yes_procs, dd=$dd_procs, gzip=$gzip_procs"
    
    # FIXED: Method 1: yes command (CPU-bound) - removed redundant &
    for i in $(seq 1 $yes_procs); do
        docker exec -d "$REDIS_CONTAINER" sh -c 'yes > /dev/null'
    done
    
    # FIXED: Method 2: dd command (I/O and CPU) - removed redundant &
    for i in $(seq 1 $dd_procs); do
        docker exec -d "$REDIS_CONTAINER" sh -c 'dd if=/dev/zero of=/dev/null bs=1M count=999999 2>/dev/null'
    done
    
    # FIXED: Method 3: gzip compression (CPU-intensive) - removed redundant &
    for i in $(seq 1 $gzip_procs); do
        docker exec -d "$REDIS_CONTAINER" sh -c 'dd if=/dev/zero bs=1M count=999999 2>/dev/null | gzip > /dev/null'
    done
    
    # Wait for processes to start
    sleep 3
    
    local actual_info
    actual_info=$(check_cpu_stress)
    echo "CPU stress processes started: $actual_info"
    
    return 0
}

# FIXED: Enhanced process termination
stop_cpu_stress() {
    echo "Stopping all CPU stress processes..."
    
    # Kill each type of process with better error handling
    docker exec -i "$REDIS_CONTAINER" sh -c 'pkill yes 2>/dev/null; pkill -f "dd if=/dev/zero" 2>/dev/null; pkill -f "gzip.*dev/zero" 2>/dev/null; exit 0'
    
    sleep 2
    
    # Force kill any remaining processes
    docker exec -i "$REDIS_CONTAINER" sh -c 'pkill -9 yes 2>/dev/null; pkill -9 -f "dd if=/dev/zero" 2>/dev/null; pkill -9 -f "gzip.*dev/zero" 2>/dev/null; exit 0'
    
    sleep 1
    local remaining_info
    remaining_info=$(check_cpu_stress)
    local remaining
    remaining=$(echo "$remaining_info" | grep -o 'total:[0-9]*' | cut -d: -f2)
    
    if [ "$remaining" -eq 0 ]; then
        echo "All CPU stress processes stopped successfully"
    else
        echo "WARNING: $remaining processes still running ($remaining_info)"
    fi
    
    return 0
}

# FIXED: More robust performance monitoring with signal handling
monitor_redis_performance() {
    local duration="$1"
    local log_file="$2"
    local interval=2  # Monitor every 2 seconds
    
    echo "Starting Redis performance monitoring for ${duration}s..."
    
    local end_time=$(($(date +%s) + duration))
    local sample_count=0
    
    # Performance monitoring header
    {
        echo "# Redis Performance Monitoring During CPU Stress"
        echo "# Format: timestamp,latency_ms,info_memory_used_human,info_cpu_used_sys,stress_processes"
        echo "timestamp,latency_ms,memory_used,cpu_sys,stress_processes"
    } >> "$log_file"
    
    # FIXED: Add signal handling for clean termination
    local monitoring_active=true
    trap 'monitoring_active=false' TERM INT
    
    while [ "$(date +%s)" -lt "$end_time" ] && [ "$monitoring_active" = true ]; do
        local timestamp
        timestamp=$(ts)
        
        # Measure Redis command latency
        local latency
        latency=$(redis_ok || echo "timeout")
        
        # Get memory usage
        local memory_used
        memory_used=$(docker exec -i "$REDIS_CONTAINER" redis-cli -p "$REDIS_PORT" info memory 2>/dev/null | grep "used_memory_human:" | cut -d: -f2 | tr -d '\r\n' || echo "unknown")
        
        # Get system CPU usage (simplified)
        local cpu_sys
        cpu_sys=$(docker exec -i "$REDIS_CONTAINER" redis-cli -p "$REDIS_PORT" info cpu 2>/dev/null | grep "used_cpu_sys:" | cut -d: -f2 | tr -d '\r\n' || echo "0")
        
        # Get stress process count
        local stress_info
        stress_info=$(check_cpu_stress)
        local stress_count
        stress_count=$(echo "$stress_info" | grep -o 'total:[0-9]*' | cut -d: -f2 || echo "0")
        
        # Log sample
        echo "$timestamp,$latency,$memory_used,$cpu_sys,$stress_count" >> "$log_file"
        
        sample_count=$((sample_count + 1))
        sleep "$interval"
    done
    
    echo "Performance monitoring completed: $sample_count samples collected"
}

# Validate that CPU stress actually impacted Redis
validate_stress_impact() {
    local monitoring_log="$1"
    
    if [ ! -f "$monitoring_log" ]; then
        echo "NoValidation=missing_log"
        return 1
    fi
    
    # Extract latency values (skip header)
    local latencies
    latencies=$(tail -n +4 "$monitoring_log" | cut -d, -f2 | grep -E '^[0-9]+ || true)
    
    if [ -z "$latencies" ]; then
        echo "NoValidation=no_valid_latencies"
        return 1
    fi
    
    # Calculate basic statistics
    local count=0
    local sum=0
    local max_latency=0
    
    for lat in $latencies; do
        count=$((count + 1))
        sum=$((sum + lat))
        if [ "$lat" -gt "$max_latency" ]; then
            max_latency="$lat"
        fi
    done
    
    if [ "$count" -eq 0 ]; then
        echo "NoValidation=zero_samples"
        return 1
    fi
    
    local avg_latency=$((sum / count))
    
    echo "ValidationSamples=$count"
    echo "AverageLatencyMs=$avg_latency"  
    echo "MaxLatencyMs=$max_latency"
    
    # Determine if stress had significant impact
    # Consider impact significant if average latency > 50ms or max > 200ms
    if [ "$avg_latency" -gt 50 ] || [ "$max_latency" -gt 200 ]; then
        echo "StressImpact=significant"
        return 0
    elif [ "$avg_latency" -gt 10 ] || [ "$max_latency" -gt 50 ]; then
        echo "StressImpact=moderate"
        return 0
    else
        echo "StressImpact=minimal"
        echo "WARNING: CPU stress may not have significantly impacted Redis performance"
        return 1
    fi
}

# Main CPU contention fault injection function
fault_cpu_contention() {
    local duration="${1:-20}"
    local process_count="${2:-$CPU_STRESS_PROCESSES}"
    local log_file="$RESULTS_DIR/fault_logs/injection_cpu-contention_$(date +%Y%m%d_%H%M%S).log"
    local monitoring_file="${log_file%.log}_monitoring.csv"
    local start_epoch
    start_epoch=$(date +%s)

    # Initialize log file
    {
        echo "# Enhanced CPU Contention Fault Injection"
        echo "Fault=cpu-contention"
        echo "Start=$(ts)"
        echo "Container=$REDIS_CONTAINER"
        echo "Port=$REDIS_PORT"
        echo "ProcessCount=$process_count"
        echo "DurationSeconds=$duration"
        echo ""
    } > "$log_file"

    # Get container CPU information
    echo "=== Container CPU Information ===" | tee -a "$log_file"
    get_container_cpu_info | tee -a "$log_file"
    echo "" | tee -a "$log_file"

    # Check initial Redis state
    echo "=== Initial State Check ===" | tee -a "$log_file"
    local initial_latency
    initial_latency=$(redis_ok || echo "timeout")
    
    if [ "$initial_latency" = "timeout" ]; then
        echo "ERROR: Redis not accessible before CPU stress test" | tee -a "$log_file"
        return 1
    fi
    
    echo "InitialRedisLatencyMs=$initial_latency" | tee -a "$log_file"
    echo "Redis accessible before CPU stress (${initial_latency}ms)" | tee -a "$log_file"
    echo "" | tee -a "$log_file"

    # Start CPU stress
    echo "=== Starting CPU Stress ===" | tee -a "$log_file"
    local stress_start
    stress_start=$(date +%s)
    
    start_cpu_stress "$process_count" | tee -a "$log_file"
    
    # Verify stress processes started
    local stress_info
    stress_info=$(check_cpu_stress)
    echo "ActiveStressProcesses=$stress_info" | tee -a "$log_file"
    
    local total_processes
    total_processes=$(echo "$stress_info" | grep -o 'total:[0-9]*' | cut -d: -f2)
    
    if [ "$total_processes" -eq 0 ]; then
        echo "ERROR: No CPU stress processes started" | tee -a "$log_file"
        return 1
    fi
    echo "" | tee -a "$log_file"

    # Test initial Redis response under stress
    echo "=== Redis Response Under Initial Stress ===" | tee -a "$log_file"
    local stressed_latency
    stressed_latency=$(redis_ok || echo "timeout")
    
    local redis_responsive=true
    if [ "$stressed_latency" = "timeout" ]; then
        redis_responsive=false
        echo "Redis became unresponsive under CPU stress" | tee -a "$log_file"
    else
        echo "Redis responsive under stress (${stressed_latency}ms vs ${initial_latency}ms initial)" | tee -a "$log_file"
        
        # Calculate latency increase
        if [ "$stressed_latency" -gt "$initial_latency" ]; then
            local latency_increase=$((stressed_latency - initial_latency))
            echo "LatencyIncreaseMs=$latency_increase" | tee -a "$log_file"
        fi
    fi
    echo "" | tee -a "$log_file"

    # Test write operation performance
    echo "=== Write Operation Performance Test ===" | tee -a "$log_file"
    local write_test_start write_test_end write_latency_ms
    write_test_start=$(date +%s%3N 2>/dev/null || echo "$(date +%s)000")
    
    local write_success=false
    local test_key="cpu_stress_test_$(date +%s)"
    if docker exec -i "$REDIS_CONTAINER" redis-cli -p "$REDIS_PORT" set "$test_key" "performance_test_$(date +%s%3N)" >/dev/null 2>&1; then
        write_success=true
    fi
    
    write_test_end=$(date +%s%3N 2>/dev/null || echo "$(date +%s)000")
    write_latency_ms=$((write_test_end - write_test_start))
    
    echo "WriteTestSuccess=$write_success" | tee -a "$log_file"
    echo "WriteLatencyMs=$write_latency_ms" | tee -a "$log_file"
    echo "Write test: success=$write_success, latency=${write_latency_ms}ms" | tee -a "$log_file"
    echo "" | tee -a "$log_file"

    # FIXED: Start performance monitoring in background with better process handling
    echo "=== Starting Performance Monitoring ===" | tee -a "$log_file"
    monitor_redis_performance "$duration" "$monitoring_file" &
    local monitor_pid=$!

    # Maintain CPU stress for specified duration
    echo "Maintaining CPU stress for ${duration} seconds..." | tee -a "$log_file"
    sleep "$duration"

    # FIXED: Stop performance monitoring more gracefully
    if kill -0 "$monitor_pid" 2>/dev/null; then
        kill -TERM "$monitor_pid" 2>/dev/null || true
        sleep 2
        kill -KILL "$monitor_pid" 2>/dev/null || true
    fi
    wait "$monitor_pid" 2>/dev/null || true

    # Stop CPU stress
    echo "" | tee -a "$log_file"
    echo "=== Stopping CPU Stress ===" | tee -a "$log_file"
    local recovery_start
    recovery_start=$(date +%s)
    
    stop_cpu_stress | tee -a "$log_file"
    
    # Wait for Redis recovery and measure recovery time
    echo "" | tee -a "$log_file"
    echo "=== Redis Recovery Measurement ===" | tee -a "$log_file"
    local recovered=0
    local max_wait=15
    local wait_count=0
    
    echo "Waiting for Redis recovery (max ${max_wait}s)..." | tee -a "$log_file"
    while [ $wait_count -lt $max_wait ]; do
        local recovery_latency
        recovery_latency=$(redis_ok || echo "timeout")
        
        if [ "$recovery_latency" != "timeout" ] && [ "$recovery_latency" -le $((initial_latency + 10)) ]; then
            recovered=$(date +%s)
            echo "Redis recovery confirmed (${recovery_latency}ms latency)" | tee -a "$log_file"
            break
        fi
        sleep 1
        wait_count=$((wait_count + 1))
    done

    if [ $recovered -eq 0 ]; then
        echo "WARNING: Redis may not have fully recovered within ${max_wait}s" | tee -a "$log_file"
        recovered=$(date +%s)
    fi

    # Validate stress impact
    echo "" | tee -a "$log_file"
    echo "=== Stress Impact Validation ===" | tee -a "$log_file"
    validate_stress_impact "$monitoring_file" | tee -a "$log_file"

    # Final timing metrics
    echo "" | tee -a "$log_file"
    echo "=== Final Metrics ===" | tee -a "$log_file"
    {
        echo "StressStartSeconds=$((stress_start - start_epoch))"
        echo "StressDurationSeconds=$((recovery_start - stress_start))"
        echo "RecoverySeconds=$((recovered - recovery_start))"
        echo "TotalImpactSeconds=$((recovered - stress_start))"
        echo "RedisResponsiveDuringStress=$redis_responsive"
        echo "InitialLatencyMs=$initial_latency"
        echo "StressedLatencyMs=$stressed_latency"
        echo "WriteTestSuccess=$write_success"
        echo "WriteLatencyMs=$write_latency_ms"
        echo "MonitoringLog=$monitoring_file"
        echo "End=$(ts)"
    } >> "$log_file"

    echo ""
    echo "LOG_PATH=$log_file"
    echo "MONITORING_PATH=$monitoring_file"
}

# FIXED: Enhanced status display without Unicode
show_status() {
    echo "=== Enhanced CPU Contention Fault Status ==="
    echo "Redis Container: $REDIS_CONTAINER"
    echo "Default Stress Processes: $CPU_STRESS_PROCESSES (0=auto-detect)"
    echo "Stress Methods: $CPU_STRESS_METHODS"
    echo ""
    
    echo "=== Container CPU Information ==="
    get_container_cpu_info
    echo ""
    
    echo "=== Redis Status ==="
    local latency
    latency=$(redis_ok || echo "timeout")
    if [ "$latency" != "timeout" ]; then
        echo "Redis: ACCESSIBLE (${latency}ms latency)"
    else
        echo "Redis: NOT ACCESSIBLE"
    fi
    
    echo ""
    echo "=== CPU Stress Status ==="
    local stress_info
    stress_info=$(check_cpu_stress)
    local total_processes
    total_processes=$(echo "$stress_info" | grep -o 'total:[0-9]*' | cut -d: -f2)
    
    if [ "$total_processes" -gt 0 ]; then
        echo "Active stress processes: $stress_info"
        echo "WARNING: CPU contention is currently active"
    else
        echo "No CPU stress processes running"
        echo "SUCCESS: System is clean"
    fi
    
    echo ""
    echo "=== Container Resource Usage ==="
    docker stats "$REDIS_CONTAINER" --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" 2>/dev/null || echo "Unable to get container stats"
}

# Enhanced usage information
usage() {
    cat << EOF
Enhanced CPU Contention Fault Injection Manager

Usage: $0 <command> [options]

Commands:
    start [processes]       - Start CPU stress with N processes (0=auto-detect cores)
    stop                    - Stop all CPU stress processes  
    inject [duration] [processes] - Enhanced fault injection with monitoring
    status                  - Show detailed system status
    test                    - Test Redis connectivity with latency
    monitor [duration]      - Monitor Redis performance for specified time

Parameters:
    duration               - Duration in seconds (default: 20s)
    processes              - Number of CPU stress processes (0=auto-detect, default: $CPU_STRESS_PROCESSES)

Enhanced Features:
    - Multi-method CPU stress (yes, dd, gzip)
    - Auto-detection of container CPU cores
    - Real-time Redis performance monitoring
    - Stress impact validation
    - Detailed latency measurement
    - Recovery time tracking

Examples:
    $0 start 0             # Auto-detect cores and start stress
    $0 inject 30 4         # 30-second stress with 4 processes + monitoring
    $0 monitor 60          # Monitor Redis performance for 60 seconds
    $0 stop                # Clean shutdown of all stress processes
    $0 status              # Detailed system information

Environment Variables:
    REDIS_CONTAINER         - Redis container name (default: redis)
    REDIS_PORT             - Redis port (default: 6379) 
    CPU_STRESS_PROCESSES   - Default process count (0=auto, default: $CPU_STRESS_PROCESSES)
    RESULTS_DIR            - Results directory (default: ../results)

Academic Research Context:
    - Tests Redis single-threaded architecture under CPU contention
    - Validates appendfsync performance degradation under load
    - Measures recovery characteristics for consistency configurations
    - Provides quantitative data for fault tolerance analysis
EOF
}

# Main function dispatcher
main() {
    case "${1:-}" in
        start)
            local processes="${2:-$CPU_STRESS_PROCESSES}"
            start_cpu_stress "$processes"
            ;;
        stop)
            stop_cpu_stress
            ;;
        inject)
            local duration="${2:-20}"
            local processes="${3:-$CPU_STRESS_PROCESSES}"
            fault_cpu_contention "$duration" "$processes"
            ;;
        status)
            show_status
            ;;
        test)
            local latency
            latency=$(redis_ok || echo "timeout")
            if [ "$latency" != "timeout" ]; then
                echo "Redis is accessible (${latency}ms latency)"
                show_status
                exit 0
            else
                echo "Redis is NOT accessible"
                exit 1
            fi
            ;;
        monitor)
            local duration="${2:-60}"
            local monitor_file="$RESULTS_DIR/fault_logs/manual_monitoring_$(date +%Y%m%d_%H%M%S).csv"
            echo "Starting $duration second monitoring session..."
            monitor_redis_performance "$duration" "$monitor_file"
            echo "Monitoring complete. Results: $monitor_file"
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