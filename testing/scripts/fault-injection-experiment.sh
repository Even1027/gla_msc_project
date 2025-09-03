#!/usr/bin/env bash
# fault-injection-experiment.sh – container-restart fault experiment (fixed baseline log handling)
set -euo pipefail

# Scripts
CONFIG_SCRIPT="./docker-redis-config-manager.sh"
FAULT_SCRIPT="./fault-injection-manager.sh"
BASELINE_SCRIPT="./baseline-test.sh"
for f in "$CONFIG_SCRIPT" "$FAULT_SCRIPT" "$BASELINE_SCRIPT"; do
  [ -x "$f" ] || { echo "ERROR: required script not found or not executable: $f"; exit 1; }
done

# Fixed: auto-detect Redis container (optional, config script also handles this)
REDIS_CONTAINER=${REDIS_CONTAINER:-$(docker ps --format "{{.Names}}" | grep -i redis | head -1 || true)}
if [ -z "$REDIS_CONTAINER" ]; then
  echo "ERROR: No Redis container found for container-restart experiment."; exit 1
fi
export REDIS_CONTAINER
echo "Using Redis container: $REDIS_CONTAINER"

INJECT_AT=${INJECT_AT:-10}
BASE_URL=${BASE_URL:-"http://localhost:8080/api/orders"}

# Adjusted durations for restart (extend profiles to include recovery buffer)
LOW_DURATION=${LOW_DURATION:-50};    LOW_RPM=${LOW_RPM:-180};    LOW_CONCURRENCY=${LOW_CONCURRENCY:-3}
MEDIUM_DURATION=${MEDIUM_DURATION:-70}; MEDIUM_RPM=${MEDIUM_RPM:-600}; MEDIUM_CONCURRENCY=${MEDIUM_CONCURRENCY:-5}
HIGH_DURATION=${HIGH_DURATION:-100};  HIGH_RPM=${HIGH_RPM:-1200};  HIGH_CONCURRENCY=${HIGH_CONCURRENCY:-8}

RESULTS_DIR="../results"
mkdir -p "$RESULTS_DIR"
EXP_ID="fault_container-restart_$(date +%Y%m%d_%H%M%S)"
EXP_ROOT="$RESULTS_DIR/$EXP_ID"
mkdir -p "$EXP_ROOT"
START_EPOCH=$(date +%s)

log() { echo "[$(date -Iseconds)] $*"; }

# Enhanced health check with detailed logging
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

# Enhanced warmup with validation
warmup() {
  local label="$1"
  local warmup_count=12
  local success_count=0
  
  log "Warmup(${warmup_count} req + 5s) [$label]"
  for i in $(seq 1 $warmup_count); do
    if curl -sS -m 2 --connect-timeout 1 \
      -X POST "$BASE_URL" \
      -H "Content-Type: application/json" \
      -H "Idempotency-Key: warm-$label-$(date +%s%3N)" \
      -d '{"productId":1,"quantity":1}' >/dev/null 2>&1; then
      success_count=$((success_count + 1))
    fi
    sleep 0.3
  done
  
  log "Warmup completed: $success_count/$warmup_count requests successful"
  
  if [ $success_count -lt $((warmup_count / 2)) ]; then
    log "WARNING: Low warmup success rate"
    return 1
  fi
  
  sleep 5
  return 0
}

profile_vars() {
  case "$1" in
    low)    echo "$LOW_DURATION $LOW_RPM $LOW_CONCURRENCY" ;;
    medium) echo "$MEDIUM_DURATION $MEDIUM_RPM $MEDIUM_CONCURRENCY" ;;
    high)   echo "$HIGH_DURATION $HIGH_RPM $HIGH_CONCURRENCY" ;;
    *) echo "0 0 0" ;;
  esac
}

# Enhanced run_case with better result tracking
run_case() {
  local cfg="$1" profile="$2"
  log "----- CASE: cfg=$cfg, profile=$profile -----"

  # Apply configuration
  "$CONFIG_SCRIPT" "$cfg" || { log "Apply config failed: $cfg"; return 1; }
  sleep 5
  health_check || { log "Health check failed"; return 1; }
  warmup "$cfg-$profile" || log "Warmup had issues, continuing..."

  # Get profile parameters
  read -r DURATION RPM CONCURRENCY <<<"$(profile_vars "$profile")"
  [ "$DURATION" -gt 0 ] || { log "Bad profile $profile"; return 1; }

  # Calculate injection timing (leave at least 15s for recovery)
  local inject_at="$INJECT_AT"
  local min_recovery_time=15
  if [ "$inject_at" -ge "$DURATION" ] || [ $((DURATION - inject_at)) -lt $min_recovery_time ]; then
    inject_at=$(( DURATION - min_recovery_time ))
    if [ "$inject_at" -lt 5 ]; then
      inject_at=5
    fi
    log "Adjusted inject-at to $inject_at for duration=$DURATION (recovery buffer: ${min_recovery_time}s)"
  fi

  local case_dir="$EXP_ROOT/${cfg}/${profile}/container-restart"
  mkdir -p "$case_dir"

  # Create synchronization files
  local sync_dir="$case_dir/.sync"
  mkdir -p "$sync_dir"
  echo "0" > "$sync_dir/baseline_ready"
  echo "0" > "$sync_dir/baseline_started"
  echo "0" > "$sync_dir/injection_ready"

  # Start baseline test
  local base_log="$case_dir/baseline_stdout.log"
  log "Start baseline: ${DURATION}s rpm=${RPM} conc=${CONCURRENCY}"
  
  (
    # Signal baseline ready
    echo "1" > "$sync_dir/baseline_ready"
    
    # Wait for injection to be ready
    while [ "$(cat "$sync_dir/injection_ready" 2>/dev/null || echo "0")" = "0" ]; do
      sleep 1
    done
    
    # Signal baseline started and execute test
    echo "1" > "$sync_dir/baseline_started"
    BASE_URL="$BASE_URL" "$BASELINE_SCRIPT" "$DURATION" "$RPM" "$CONCURRENCY"
  ) > "$base_log" 2>&1 &
  local baseline_pid=$!

  # Start fault injection
  (
    # Signal injection ready
    echo "1" > "$sync_dir/injection_ready"
    
    # Wait for baseline to be ready
    while [ "$(cat "$sync_dir/baseline_ready" 2>/dev/null || echo "0")" = "0" ]; do
      sleep 1
    done
    
    sleep "$inject_at"
    log ">>> Inject container-restart at t=+$inject_at s"
    
    # Execute restart and capture output
    local restart_output
    restart_output=$("$FAULT_SCRIPT" container-restart 2>&1)
    echo "$restart_output" > "$case_dir/fault_stdout.log"
    
    # Extract log path
    local fault_log_path
    fault_log_path=$(echo "$restart_output" | grep -E '^LOG_PATH=' | cut -d= -f2 || true)
    
    if [ -n "$fault_log_path" ] && [ -f "$fault_log_path" ]; then
      cp "$fault_log_path" "$case_dir/injection_container-restart_$(date +%Y%m%d_%H%M%S).log"
    fi
    
    # Re-apply configuration after restart
    log "Re-applying config $cfg after container restart"
    "$CONFIG_SCRIPT" "$cfg" > "$case_dir/reapply_stdout.log" 2>&1 || true
    
  ) &
  local injector_pid=$!

  # FIXED: Wait for baseline & injector to finish and capture exit codes
  local baseline_result=0
  local injection_result=0
  
  wait "$baseline_pid" || baseline_result=$?
  wait "$injector_pid" || injection_result=$?

  # **Fixed: Simplified baseline result directory extraction**
  baseline_dir=$(grep -m1 -E 'Output Directory:' "$base_log" | awk '{print $NF}')
  if [ -z "$baseline_dir" ]; then
    baseline_dir=$(ls -dt "$RESULTS_DIR"/baseline_* 2>/dev/null | head -1 || true)
  fi
  if [ -n "$baseline_dir" ] && [ -d "$baseline_dir" ]; then
    mv "$baseline_dir"/* "$case_dir/" 2>/dev/null || cp -r "$baseline_dir"/* "$case_dir/"
    rmdir "$baseline_dir" 2>/dev/null || true
  else
    log "WARNING: Could not locate baseline results for $cfg/$profile"
  fi

  # Create case metadata
  cat > "$case_dir/run_metadata.txt" <<EOF
Config=${cfg}
Profile=${profile}
Fault=container-restart
InjectAtSeconds=${inject_at}
DurationSeconds=${DURATION}
TargetRPM=${RPM}
Concurrency=${CONCURRENCY}
BaselineResult=${baseline_result}
InjectionResult=${injection_result}
RecoveryBufferSeconds=$((DURATION - inject_at))
ExecutedAt=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')
EOF

  # Cleanup sync directory
  rm -rf "$sync_dir" 2>/dev/null || true
  
  log "Case $cfg/$profile completed (baseline=$baseline_result, injection=$injection_result)"
  sleep 3

  # Return success if baseline completed successfully
  [ $baseline_result -eq 0 ]
}

run_suite_for_fault() {
  local total_cases=9
  local completed_cases=0
  local failed_cases=0
  
  for c in strong balanced performance; do
    log "===== CONFIG: $c ====="
    for p in low medium high; do
      completed_cases=$((completed_cases + 1))
      log "Progress: $completed_cases/$total_cases cases"
      
      if run_case "$c" "$p"; then
        log "SUCCESS: $c/$p completed"
      else
        log "FAILED: $c/$p encountered errors"  
        failed_cases=$((failed_cases + 1))
      fi
      sleep 5  # Inter-case cooldown
    done
    sleep 10  # Config transition time
  done
  
  log "Suite completed: $completed_cases cases, $failed_cases failures"
}

consolidate_csv() {
  local csv="$EXP_ROOT/consolidated_results.csv"
  echo "config,profile,fault,total_requests,success,failed,error_rate_percent,throughput_rps,p50_ms,p95_ms,p99_ms,idempotency_hit_rate_percent,timeout_count,http_4xx_count,http_5xx_count,restart_seconds,recover_seconds,downtime_seconds,pre_restart_requests,post_restart_requests" > "$csv"
  
  for c in strong balanced performance; do
    for p in low medium high; do
      local dir="$EXP_ROOT/$c/$p/container-restart"
      
      # Initialize all variables with defaults
      local total=0 success=0 failed=0 err=0 thr=0 p50=0 p95=0 p99=0 hit=0 timeout=0 h4=0 h5=0
      local r_sec="" rec_sec="" down_sec=""
      local pre_restart=0 post_restart=0
      
      # Find summary file
      local sum=$(find "$dir" -name "summary.txt" 2>/dev/null | head -1 || true)
      if [ -f "$sum" ]; then
        total=$(grep -E '^TOTAL_REQUESTS=' "$sum" | cut -d= -f2 2>/dev/null || echo "0")
        success=$(grep -E '^SUCCESS=' "$sum" | cut -d= -f2 2>/dev/null || echo "0")
        failed=$(grep -E '^FAILED=' "$sum" | cut -d= -f2 2>/dev/null || echo "0")
        err=$(grep -E '^ERROR_RATE_PERCENT=' "$sum" | cut -d= -f2 2>/dev/null || echo "0")
        thr=$(grep -E '^THROUGHPUT_RPS=' "$sum" | cut -d= -f2 2>/dev/null || echo "0")
        p50=$(grep -E '^P50_MS=' "$sum" | cut -d= -f2 2>/dev/null || echo "0")
        p95=$(grep -E '^P95_MS=' "$sum" | cut -d= -f2 2>/dev/null || echo "0")
        p99=$(grep -E '^P99_MS=' "$sum" | cut -d= -f2 2>/dev/null || echo "0")
        hit=$(grep -E '^IDEMPOTENCY_HIT_RATE_PERCENT=' "$sum" | cut -d= -f2 2>/dev/null || echo "0")
        timeout=$(grep -E '^TIMEOUT_COUNT=' "$sum" | cut -d= -f2 2>/dev/null || echo "0")
        h4=$(grep -E '^HTTP_4XX_COUNT=' "$sum" | cut -d= -f2 2>/dev/null || echo "0")
        h5=$(grep -E '^HTTP_5XX_COUNT=' "$sum" | cut -d= -f2 2>/dev/null || echo "0")
      fi

      # Find injection log
      local inj=$(find "$dir" -name "injection_*" 2>/dev/null | head -1 || true)
      if [ -n "$inj" ] && [ -f "$inj" ]; then
        r_sec=$(grep -E '^RestartSeconds=' "$inj" | cut -d= -f2 2>/dev/null || echo "")
        rec_sec=$(grep -E '^RecoverSeconds=' "$inj" | cut -d= -f2 2>/dev/null || echo "")
        down_sec=$(grep -E '^DowntimeSeconds=' "$inj" | cut -d= -f2 2>/dev/null || echo "")
      fi
      
      # Calculate pre/post restart request estimates (simplified)
      if [ "$total" -gt 0 ] && [ -n "$down_sec" ] && [ "$down_sec" != "" ]; then
        # Rough estimate based on downtime vs total duration
        local meta="$dir/run_metadata.txt"
        if [ -f "$meta" ]; then
          local duration=$(grep -E '^DurationSeconds=' "$meta" | cut -d= -f2 2>/dev/null || echo "60")
          local inject_at=$(grep -E '^InjectAtSeconds=' "$meta" | cut -d= -f2 2>/dev/null || echo "10")
          if [ "$duration" -gt 0 ]; then
            pre_restart=$(( total * inject_at / duration ))
            post_restart=$(( total - pre_restart ))
          fi
        fi
      fi

      echo "$c,$p,container-restart,$total,$success,$failed,$err,$thr,$p50,$p95,$p99,$hit,$timeout,$h4,$h5,$r_sec,$rec_sec,$down_sec,$pre_restart,$post_restart" >> "$csv"
    done
  done
  echo "CSV saved: $csv"
}

# Create comprehensive experiment metadata
create_experiment_metadata() {
  cat > "$EXP_ROOT/experiment_metadata.txt" <<EOF
# Container Restart Fault Injection Experiment

ExperimentID=$EXP_ID
ExperimentType=container-restart-fault
StartTime=$(date -u -d @$START_EPOCH -Iseconds 2>/dev/null || date -u -r $START_EPOCH '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%S%z')
EndTime=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')
TotalDurationSeconds=$(($(date +%s) - START_EPOCH))

# Fault Configuration
FaultType=container-restart
InjectionTimeSeconds=$INJECT_AT
BaseURL=$BASE_URL
RecoveryBufferSeconds=15

# Load Profiles (Extended for restart recovery)
LowLoad=${LOW_DURATION}s,${LOW_RPM}rpm,${LOW_CONCURRENCY}users
MediumLoad=${MEDIUM_DURATION}s,${MEDIUM_RPM}rpm,${MEDIUM_CONCURRENCY}users
HighLoad=${HIGH_DURATION}s,${HIGH_RPM}rpm,${HIGH_CONCURRENCY}users

# Test Matrix
ConfigsTested=strong,balanced,performance
ProfilesTested=low,medium,high
TotalCases=9

# Expected Behavior
RestartImpact=complete_service_interruption
RecoveryPattern=configuration_dependent
StrongConfigRecovery=slowest_due_to_appendfsync_always
PerformanceConfigRecovery=fastest_due_to_appendfsync_no
BalancedConfigRecovery=moderate_due_to_appendfsync_everysec

# Technical Details
SynchronizationMethod=file-based
ResultTracking=enhanced
ConfigReapplication=automatic
HealthCheckValidation=multi-attempt
MinGWCompatibility=enabled

# Results
ConsolidatedResults=consolidated_results.csv
Status=COMPLETED
EOF
}

# Enhanced final cleanup
final_cleanup() {
  log "Performing final cleanup..."
  
  # Clean up any synchronization directories
  find "$EXP_ROOT" -name ".sync" -type d -exec rm -rf {} + 2>/dev/null || true
  
  # Validate essential files exist
  local missing_count=0
  for c in strong balanced performance; do
    for p in low medium high; do
      local case_dir="$EXP_ROOT/$c/$p/container-restart"
      if [ ! -f "$case_dir/run_metadata.txt" ]; then
        log "WARNING: Missing metadata for $c/$p"
        missing_count=$((missing_count + 1))
      fi
    done
  done
  
  if [ $missing_count -eq 0 ]; then
    log "All case metadata files validated"
  else
    log "WARNING: $missing_count cases have missing metadata"
  fi
}

# Main execution function
main() {
  log "=== CONTAINER RESTART FAULT EXPERIMENT ==="
  log "Root: $EXP_ROOT"
  log "InjectAt=${INJECT_AT}s"
  log "Extended durations for restart recovery: Low=${LOW_DURATION}s, Medium=${MEDIUM_DURATION}s, High=${HIGH_DURATION}s"
  
  # Setup cleanup trap
  trap final_cleanup EXIT

  # Execute test suite
  run_suite_for_fault
  
  # Generate results
  consolidate_csv
  create_experiment_metadata

  log "=== CONTAINER RESTART EXPERIMENT COMPLETED ==="
  log "Results: $EXP_ROOT"
  log "CSV Data: $EXP_ROOT/consolidated_results.csv"
  log "Duration: $(($(date +%s) - START_EPOCH))s"
  log ""
  log "Expected Findings:"
  log "- All configurations experience complete service interruption"
  log "- Strong config: Slowest recovery (appendfsync=always)"
  log "- Performance config: Fastest recovery (appendfsync=no)"
  log "- Balanced config: Moderate recovery (appendfsync=everysec)"
  log "- Recovery time should correlate with appendfsync setting"
  log ""
  log "Next: Analyze consolidated_results.csv for recovery patterns"
}

main "$@"