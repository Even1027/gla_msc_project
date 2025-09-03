#!/usr/bin/env bash
# cpu-contention-fault-experiment.sh - Enhanced CPU Contention Fault Experiment (fixed container detection)
set -euo pipefail
START_EPOCH=$(date +%s)

# Script dependencies
CONFIG_SCRIPT="./docker-redis-config-manager.sh"
CPU_FAULT_SCRIPT="./cpu-contention-fault-manager.sh"
BASELINE_SCRIPT="./baseline-test.sh"

# Ensure dependencies are executable...
for script in "$CONFIG_SCRIPT" "$CPU_FAULT_SCRIPT" "$BASELINE_SCRIPT"; do
  [ -x "$script" ] || { echo "ERROR: required script not found: $script"; exit 1; }
done

# **Fixed: auto-detect Redis container if not specified**
REDIS_CONTAINER=${REDIS_CONTAINER:-$(docker ps --format "{{.Names}}" | grep -i redis | head -1 || true)}
if [ -z "$REDIS_CONTAINER" ]; then
  echo "ERROR: No Redis container found for CPU contention experiment."; exit 1
fi
export REDIS_CONTAINER
echo "Using Redis container: $REDIS_CONTAINER"

# Experiment configuration
INJECT_AT=${INJECT_AT:-10}
STRESS_DURATION=${STRESS_DURATION:-15}
STRESS_PROCESSES=${STRESS_PROCESSES:-0}
BASE_URL=${BASE_URL:-"http://localhost:8080/api/orders"}
SYNC_TIMEOUT=${SYNC_TIMEOUT:-30}

# Load profile defaults (can be overridden by env)
LOW_DURATION=${LOW_DURATION:-45};   LOW_RPM=${LOW_RPM:-180};   LOW_CONCURRENCY=${LOW_CONCURRENCY:-3}
MEDIUM_DURATION=${MEDIUM_DURATION:-60}; MEDIUM_RPM=${MEDIUM_RPM:-600}; MEDIUM_CONCURRENCY=${MEDIUM_CONCURRENCY:-5}
HIGH_DURATION=${HIGH_DURATION:-75};  HIGH_RPM=${HIGH_RPM:-1200};  HIGH_CONCURRENCY=${HIGH_CONCURRENCY:-8}

# Results directory
RESULTS_DIR="../results"
mkdir -p "$RESULTS_DIR"
EXP_ID="cpu_contention_enhanced_$(date +%Y%m%d_%H%M%S)"
EXP_ROOT="$RESULTS_DIR/$EXP_ID"
mkdir -p "$EXP_ROOT"

log() { 
    echo "[$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')] $*" 
}

# Enhanced health check with retry logic
health_check() {
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -sf -m 5 -X POST "$BASE_URL" \
           -H "Content-Type: application/json" \
           -H "Idempotency-Key: health-$(date +%s%3N)" \
           -d '{"productId":1,"quantity":1}' >/dev/null 2>&1; then
            log "Health check passed (attempt $attempt)"
            return 0
        fi
        
        log "Health check failed (attempt $attempt/$max_attempts)"
        attempt=$((attempt + 1))
        [ $attempt -le $max_attempts ] && sleep 2
    done
    
    log "Health check failed after $max_attempts attempts"
    return 1
}

# Enhanced system warmup with validation
warmup() {
    local label="$1"
    local warmup_requests=8
    local success_count=0
    
    log "Warmup for $label ($warmup_requests requests + validation)"
    
    for i in $(seq 1 $warmup_requests); do
        if curl -sS -m 3 --connect-timeout 1 \
          -X POST "$BASE_URL" \
          -H "Content-Type: application/json" \
          -H "Idempotency-Key: warm-$label-$(date +%s%3N)" \
          -d '{"productId":1,"quantity":1}' >/dev/null 2>&1; then
            success_count=$((success_count + 1))
        fi
        sleep 0.5
    done
    
    log "Warmup completed: $success_count/$warmup_requests successful"
    
    if [ $success_count -lt $((warmup_requests / 2)) ]; then
        log "WARNING: Low warmup success rate, system may be unstable"
        return 1
    fi
    
    sleep 3
    return 0
}

# Get load parameters with validation
get_load_params() {
    case "$1" in
        low)    echo "$LOW_DURATION $LOW_RPM $LOW_CONCURRENCY" ;;
        medium) echo "$MEDIUM_DURATION $MEDIUM_RPM $MEDIUM_CONCURRENCY" ;;
        high)   echo "$HIGH_DURATION $HIGH_RPM $HIGH_CONCURRENCY" ;;
        *) 
            log "ERROR: Invalid profile $1"
            echo "0 0 0" 
            ;;
    esac
}

# Create synchronization primitives
create_sync_files() {
    local case_dir="$1"
    
    # Create synchronization directory
    local sync_dir="$case_dir/.sync"
    mkdir -p "$sync_dir"
    
    # Initialize sync files
    echo "0" > "$sync_dir/baseline_ready"
    echo "0" > "$sync_dir/fault_ready"
    echo "0" > "$sync_dir/baseline_started"
    echo "0" > "$sync_dir/fault_injected"
    echo "0" > "$sync_dir/fault_completed"
    
    echo "$sync_dir"
}

# Wait for synchronization event
wait_for_sync() {
    local sync_file="$1"
    local timeout="${2:-$SYNC_TIMEOUT}"
    local check_interval=1
    local waited=0
    
    while [ "$(cat "$sync_file" 2>/dev/null || echo "0")" = "0" ] && [ $waited -lt $timeout ]; do
        sleep $check_interval
        waited=$((waited + check_interval))
    done
    
    if [ $waited -ge $timeout ]; then
        log "WARNING: Synchronization timeout waiting for $(basename "$sync_file")"
        return 1
    fi
    
    return 0
}

# Signal synchronization event
signal_sync() {
    local sync_file="$1"
    echo "1" > "$sync_file"
}

# FIXED: Enhanced baseline test execution with result tracking
execute_baseline_test() {
    local case_dir="$1"
    local duration="$2"
    local rpm="$3"
    local concurrency="$4"
    local sync_dir="$5"
    
    # Signal baseline ready
    signal_sync "$sync_dir/baseline_ready"
    
    # Wait for fault injection to be ready
    wait_for_sync "$sync_dir/fault_ready" || return 1
    
    # Create unique output directory to avoid conflicts
    local baseline_output_dir="$case_dir/baseline_results"
    mkdir -p "$baseline_output_dir"
    
    # Execute baseline test with explicit output directory
    log "Starting synchronized baseline test..."
    signal_sync "$sync_dir/baseline_started"
    
    # Run baseline test and capture its output directory
    local baseline_stdout="$case_dir/baseline_execution.log"
    
    ( 
        export BASE_URL="$BASE_URL"
        "$BASELINE_SCRIPT" "$duration" "$rpm" "$concurrency" 2>&1
    ) > "$baseline_stdout"
    
    # Find and move the baseline results
    local created_baseline
    created_baseline=$(grep -E '^OUT_DIR=' "$baseline_stdout" | tail -1 | cut -d= -f2 || true)
    
    if [ -z "$created_baseline" ]; then
        # FIXED: MinGW compatible fallback (removed -printf)
        created_baseline=$(ls -dt "$RESULTS_DIR"/baseline_* 2>/dev/null | head -1 || true)
    fi
    
    if [ -n "$created_baseline" ] && [ -d "$created_baseline" ]; then
        # Move results to our case directory
        mv "$created_baseline"/* "$baseline_output_dir/" 2>/dev/null || \
        cp -r "$created_baseline"/* "$baseline_output_dir/" 2>/dev/null || \
        log "WARNING: Failed to move baseline results from $created_baseline"
        
        # Clean up original directory if it was moved
        rmdir "$created_baseline" 2>/dev/null || true
        
        log "Baseline results saved to: $baseline_output_dir"
        echo "$baseline_output_dir" > "$case_dir/.baseline_result_path"
    else
        log "ERROR: Could not locate baseline test results"
        return 1
    fi
    
    return 0
}

# FIXED: Enhanced fault injection with monitoring and proper variable passing
execute_fault_injection() {
    local case_dir="$1"
    local inject_at="$2"
    local stress_duration="$3"
    local stress_processes="$4"
    local sync_dir="$5"
    local config="$6"  # FIXED: Added config parameter
    
    # Signal fault injection ready
    signal_sync "$sync_dir/fault_ready"
    
    # Wait for baseline to start
    wait_for_sync "$sync_dir/baseline_started" || return 1
    
    # Wait for injection time
    log "Waiting ${inject_at}s before injecting CPU contention..."
    sleep "$inject_at"
    
    # Signal fault injection started
    signal_sync "$sync_dir/fault_injected"
    
    log ">>> INJECTING CPU CONTENTION at t=+${inject_at}s <<<"
    
    # Execute enhanced fault injection
    local fault_output
    fault_output=$("$CPU_FAULT_SCRIPT" inject "$stress_duration" "$stress_processes" 2>&1)
    
    echo "$fault_output" > "$case_dir/fault_injection_output.log"
    
    # Extract fault log path
    local fault_log_path
    fault_log_path=$(echo "$fault_output" | grep -E '^LOG_PATH=' | cut -d= -f2 || true)
    
    # Extract monitoring log path
    local monitoring_log_path
    monitoring_log_path=$(echo "$fault_output" | grep -E '^MONITORING_PATH=' | cut -d= -f2 || true)
    
    # Copy logs to case directory
    if [ -n "$fault_log_path" ] && [ -f "$fault_log_path" ]; then
        cp "$fault_log_path" "$case_dir/fault_injection.log"
    fi
    
    if [ -n "$monitoring_log_path" ] && [ -f "$monitoring_log_path" ]; then
        cp "$monitoring_log_path" "$case_dir/performance_monitoring.csv"
    fi
    
    log "CPU contention injection completed"
    
    # Ensure cleanup
    "$CPU_FAULT_SCRIPT" stop >/dev/null 2>&1 || true
    
    # FIXED: Re-apply configuration after stress with proper variable
    log "Re-applying configuration after CPU stress"
    "$CONFIG_SCRIPT" "$config" >/dev/null 2>&1 || true
    
    signal_sync "$sync_dir/fault_completed"
    return 0
}

# Enhanced test case execution
run_case() {
    local config="$1"
    local profile="$2"
    
    log "===== CASE: $config/$profile ====="

    # Clean any residual CPU stress processes
    "$CPU_FAULT_SCRIPT" stop >/dev/null 2>&1 || true

    # Apply Redis configuration
    log "Applying Redis configuration: $config"
    if ! "$CONFIG_SCRIPT" "$config"; then
        log "ERROR: Failed to apply $config configuration"
        return 1
    fi
    sleep 5  # Extended wait for configuration to take effect

    # Health check
    if ! health_check; then
        log "ERROR: Health check failed"
        return 1
    fi

    # System warmup
    if ! warmup "$config-$profile"; then
        log "WARNING: Warmup had issues but continuing..."
    fi

    # Get load parameters
    read -r duration rpm concurrency <<< "$(get_load_params "$profile")"
    if [ "$duration" -le 0 ]; then
        log "ERROR: Invalid profile $profile"
        return 1
    fi

    # Calculate optimal injection timing
    local inject_at="$INJECT_AT"
    local min_post_injection_time=10  # Minimum time after injection ends
    local required_tail_time=$((STRESS_DURATION + min_post_injection_time))
    
    if [ "$inject_at" -ge "$duration" ] || [ $((duration - inject_at)) -lt $required_tail_time ]; then
        inject_at=$(( duration - required_tail_time ))
        if [ "$inject_at" -lt 5 ]; then
            inject_at=5
        fi
        log "Adjusted inject time to ${inject_at}s (duration=${duration}s, stress=${STRESS_DURATION}s)"
    fi

    # Create case directory
    local case_dir="$EXP_ROOT/$config/$profile"
    mkdir -p "$case_dir"
    
    # Create synchronization framework
    local sync_dir
    sync_dir=$(create_sync_files "$case_dir")

    # Start baseline test in background
    log "Starting synchronized baseline test: ${duration}s, ${rpm} req/min, ${concurrency} concurrent"
    execute_baseline_test "$case_dir" "$duration" "$rpm" "$concurrency" "$sync_dir" &
    local baseline_pid=$!

    # FIXED: Start fault injection in background with config parameter
    execute_fault_injection "$case_dir" "$inject_at" "$STRESS_DURATION" "$STRESS_PROCESSES" "$sync_dir" "$config" &
    local fault_pid=$!

    # FIXED: Wait for both processes to complete and capture exit codes
    local baseline_result=0
    local fault_result=0
    
    wait "$baseline_pid" || baseline_result=$?
    wait "$fault_pid" || fault_result=$?

    # Check results
    if [ $baseline_result -ne 0 ]; then
        log "WARNING: Baseline test failed with exit code $baseline_result"
    fi
    
    if [ $fault_result -ne 0 ]; then
        log "WARNING: Fault injection failed with exit code $fault_result"
    fi

    # Final cleanup
    "$CPU_FAULT_SCRIPT" stop >/dev/null 2>&1 || true

    # Create comprehensive case metadata
    cat > "$case_dir/case_metadata.txt" << EOF
Config=$config
Profile=$profile
FaultType=cpu-contention-enhanced
InjectAtSeconds=$inject_at
DurationSeconds=$duration
TargetRPM=$rpm
ConcurrentUsers=$concurrency
StressDurationSeconds=$STRESS_DURATION
StressProcesses=$STRESS_PROCESSES
ExecutedAt=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')
BaselineResult=$baseline_result
FaultResult=$fault_result
SynchronizationUsed=true
EnhancedMonitoring=true
EOF

    # Cleanup synchronization files
    rm -rf "$sync_dir" 2>/dev/null || true
    
    log "Case $config/$profile completed (baseline=$baseline_result, fault=$fault_result)"
    sleep 3  # Inter-case cooldown
    
    # Return success if at least baseline worked
    [ $baseline_result -eq 0 ]
}

# Execute full test suite
run_test_suite() {
    log "========================================"
    log "ENHANCED CPU CONTENTION FAULT EXPERIMENT"
    log "========================================"
    log "Experiment ID: $EXP_ID"
    log "Injection: t=+${INJECT_AT}s, ${STRESS_DURATION}s duration, ${STRESS_PROCESSES} processes (0=auto)"
    log "Base URL: $BASE_URL"
    log "Enhanced Features: Synchronized execution, performance monitoring, impact validation"
    
    # Initial cleanup
    "$CPU_FAULT_SCRIPT" stop >/dev/null 2>&1 || true
    
    # Test suite execution with progress tracking
    local total_cases=9
    local completed_cases=0
    local failed_cases=0
    
    for config in strong balanced performance; do
        log "===== CONFIG: $config ====="
        for profile in low medium high; do
            completed_cases=$((completed_cases + 1))
            log "Progress: $completed_cases/$total_cases cases"
            
            if run_case "$config" "$profile"; then
                log "SUCCESS: $config/$profile completed"
            else
                log "FAILED: $config/$profile encountered errors"
                failed_cases=$((failed_cases + 1))
            fi
            sleep 5  # Config transition time
        done
        sleep 10  # Extended pause between configurations
    done
    
    log "========================================"
    log "TEST SUITE COMPLETED"
    log "Total: $completed_cases/$total_cases, Failed: $failed_cases"  
    log "========================================"
}

# Enhanced results consolidation with monitoring data
consolidate_csv() {
    log "Consolidating results with enhanced metrics..."
    
    local csv="$EXP_ROOT/consolidated_results.csv"
    
    # Enhanced CSV header with monitoring metrics
    echo "config,profile,fault_type,total_requests,success,failed,error_rate_percent,throughput_rps,p50_ms,p95_ms,p99_ms,idempotency_hit_rate_percent,timeout_count,http_4xx_count,http_5xx_count,stress_duration_s,recovery_time_s,redis_responsive_during_stress,write_test_success,write_latency_ms,stress_impact,avg_latency_during_stress_ms,max_latency_during_stress_ms,monitoring_samples" > "$csv"
    
    for config in strong balanced performance; do
        for profile in low medium high; do
            local case_dir="$EXP_ROOT/$config/$profile"
            
            # Initialize all variables with defaults
            local total=0 success=0 failed=0 error_rate=0 throughput=0
            local p50=0 p95=0 p99=0 hit_rate=0 timeout=0 http4xx=0 http5xx=0
            local stress_duration=0 recovery_time=0
            local redis_responsive="unknown" write_success="unknown" write_latency=0
            local stress_impact="unknown" avg_stress_latency=0 max_stress_latency=0 monitoring_samples=0
            
            # Extract baseline metrics
            local summary_file
            summary_file=$(find "$case_dir" -name "summary.txt" 2>/dev/null | head -1)
            if [ -f "$summary_file" ]; then
                total=$(grep -E '^TOTAL_REQUESTS=' "$summary_file" | cut -d= -f2 2>/dev/null || echo "0")
                success=$(grep -E '^SUCCESS=' "$summary_file" | cut -d= -f2 2>/dev/null || echo "0")
                failed=$(grep -E '^FAILED=' "$summary_file" | cut -d= -f2 2>/dev/null || echo "0")
                error_rate=$(grep -E '^ERROR_RATE_PERCENT=' "$summary_file" | cut -d= -f2 2>/dev/null || echo "0")
                throughput=$(grep -E '^THROUGHPUT_RPS=' "$summary_file" | cut -d= -f2 2>/dev/null || echo "0")
                p50=$(grep -E '^P50_MS=' "$summary_file" | cut -d= -f2 2>/dev/null || echo "0")
                p95=$(grep -E '^P95_MS=' "$summary_file" | cut -d= -f2 2>/dev/null || echo "0")
                p99=$(grep -E '^P99_MS=' "$summary_file" | cut -d= -f2 2>/dev/null || echo "0")
                hit_rate=$(grep -E '^IDEMPOTENCY_HIT_RATE_PERCENT=' "$summary_file" | cut -d= -f2 2>/dev/null || echo "0")
                timeout=$(grep -E '^TIMEOUT_COUNT=' "$summary_file" | cut -d= -f2 2>/dev/null || echo "0")
                http4xx=$(grep -E '^HTTP_4XX_COUNT=' "$summary_file" | cut -d= -f2 2>/dev/null || echo "0")
                http5xx=$(grep -E '^HTTP_5XX_COUNT=' "$summary_file" | cut -d= -f2 2>/dev/null || echo "0")
            fi
            
            # Extract fault injection metrics
            local fault_log="$case_dir/fault_injection.log"
            if [ -f "$fault_log" ]; then
                stress_duration=$(grep -E '^StressDurationSeconds=' "$fault_log" | cut -d= -f2 2>/dev/null || echo "0")
                recovery_time=$(grep -E '^RecoverySeconds=' "$fault_log" | cut -d= -f2 2>/dev/null || echo "0")
                redis_responsive=$(grep -E '^RedisResponsiveDuringStress=' "$fault_log" | cut -d= -f2 2>/dev/null || echo "unknown")
                write_success=$(grep -E '^WriteTestSuccess=' "$fault_log" | cut -d= -f2 2>/dev/null || echo "unknown")
                write_latency=$(grep -E '^WriteLatencyMs=' "$fault_log" | cut -d= -f2 2>/dev/null || echo "0")
                stress_impact=$(grep -E '^StressImpact=' "$fault_log" | cut -d= -f2 2>/dev/null || echo "unknown")
                avg_stress_latency=$(grep -E '^AverageLatencyMs=' "$fault_log" | cut -d= -f2 2>/dev/null || echo "0")
                max_stress_latency=$(grep -E '^MaxLatencyMs=' "$fault_log" | cut -d= -f2 2>/dev/null || echo "0")
                monitoring_samples=$(grep -E '^ValidationSamples=' "$fault_log" | cut -d= -f2 2>/dev/null || echo "0")
            fi
            
            # Add row to CSV
            echo "$config,$profile,cpu-contention-enhanced,$total,$success,$failed,$error_rate,$throughput,$p50,$p95,$p99,$hit_rate,$timeout,$http4xx,$http5xx,$stress_duration,$recovery_time,$redis_responsive,$write_success,$write_latency,$stress_impact,$avg_stress_latency,$max_stress_latency,$monitoring_samples" >> "$csv"
        done
    done
    
    log "Enhanced CSV saved: $csv"
}

# Create comprehensive experiment metadata
create_metadata() {
    cat > "$EXP_ROOT/experiment_metadata.txt" << EOF
# Enhanced CPU Contention Fault Injection Experiment

ExperimentID=$EXP_ID
ExperimentType=cpu-contention-enhanced
StartTime=$(date -u -d @$START_EPOCH -Iseconds 2>/dev/null || date -u -r $START_EPOCH '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%S%z')
EndTime=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')
TotalDurationSeconds=$(($(date +%s) - START_EPOCH))

# Enhanced Fault Configuration
FaultType=cpu-contention-multi-method
InjectionTimeSeconds=$INJECT_AT
StressDurationSeconds=$STRESS_DURATION
StressProcesses=$STRESS_PROCESSES (0=auto-detect)
BaseURL=$BASE_URL
SynchronizationTimeout=$SYNC_TIMEOUT

# Enhanced Load Profiles
LowLoad=${LOW_DURATION}s,${LOW_RPM}rpm,${LOW_CONCURRENCY}users
MediumLoad=${MEDIUM_DURATION}s,${MEDIUM_RPM}rpm,${MEDIUM_CONCURRENCY}users
HighLoad=${HIGH_DURATION}s,${HIGH_RPM}rpm,${HIGH_CONCURRENCY}users

# Test Matrix
ConfigsTested=strong,balanced,performance
ProfilesTested=low,medium,high
TotalCases=9
EnhancedFeatures=synchronization,monitoring,impact_validation

# Enhanced Capabilities
CPUStressMethods=yes,dd,gzip
AutoCoreDetection=enabled
PerformanceMonitoring=real-time
StressImpactValidation=enabled
ResultTracking=enhanced
TimingSynchronization=enabled

# Academic Context
ResearchFocus=redis_consistency_under_cpu_contention
FaultCategory=resource-contention-multi-vector
ArchitecturalTarget=single-threaded-redis
ExpectedFindings=appendfsync_performance_correlation

# Technical Implementation
WindowsCompatibility=maintained
GitBashCompatibility=maintained
SynchronizationPrimitives=file-based
MonitoringInterval=2s
ImpactValidationThresholds=avg>50ms_or_max>200ms

# Results
ConsolidatedResults=consolidated_results.csv
EnhancedMetrics=stress_impact,monitoring_samples,latency_during_stress
Status=COMPLETED
EOF
}

# Final cleanup with validation
final_cleanup() {
    log "Performing comprehensive cleanup..."
    
    # Stop any remaining CPU stress processes
    "$CPU_FAULT_SCRIPT" stop >/dev/null 2>&1 || true
    
    # Clean up any leftover sync directories
    find "$EXP_ROOT" -name ".sync" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # Validate critical result files exist
    local missing_files=0
    local total_expected=9
    
    for config in strong balanced performance; do
        for profile in low medium high; do
            local case_dir="$EXP_ROOT/$config/$profile"
            if [ ! -f "$case_dir/case_metadata.txt" ]; then
                log "WARNING: Missing metadata for $config/$profile"
                missing_files=$((missing_files + 1))
            fi
        done
    done
    
    if [ $missing_files -gt 0 ]; then
        log "WARNING: $missing_files/$total_expected cases have missing files"
    else
        log "All case files validated successfully"
    fi
}

# Main execution function
main() {
    log "Starting Enhanced CPU Contention Fault Injection Experiment..."
    
    # Setup cleanup trap
    trap final_cleanup EXIT
    
    # Execute test suite
    run_test_suite
    
    # Generate enhanced results
    consolidate_csv
    create_metadata
    
    log "========================================"
    log "ENHANCED EXPERIMENT COMPLETED"
    log "========================================"
    log "Results: $EXP_ROOT"
    log "Enhanced CSV: $EXP_ROOT/consolidated_results.csv"
    log "Duration: $(($(date +%s) - START_EPOCH))s"
    log ""
    log "Enhanced Features Applied:"
    log "- Multi-method CPU stress (yes, dd, gzip)"
    log "- Auto-detection of container CPU cores"
    log "- Synchronized fault injection timing" 
    log "- Real-time Redis performance monitoring"
    log "- Quantitative stress impact validation"
    log "- Enhanced result tracking and cleanup"
    log ""
    log "Expected Findings:"
    log "- Strong config: Highest impact (appendfsync=always blocks on CPU)"
    log "- Performance config: Lowest impact (appendfsync=no, minimal blocking)"
    log "- Balanced config: Moderate impact (appendfsync=everysec)"
    log "- Higher loads should amplify configuration differences"
    log ""
    log "Next Steps:"
    log "1. Analyze consolidated_results.csv for performance patterns"
    log "2. Review performance_monitoring.csv files for detailed traces"
    log "3. Validate stress_impact metrics show significant CPU effects"
    log "4. Compare results across configurations and load profiles"
}

main "$@"