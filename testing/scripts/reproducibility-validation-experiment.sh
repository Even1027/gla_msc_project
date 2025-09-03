#!/bin/bash
# Academic Reproducibility Validation Experiment
# Redis Consistency Configuration Performance Study
# Fixed warmup version for MinGW compatibility

set -euo pipefail
START_EPOCH=$(date +%s)

# Script dependencies
CONFIG_SCRIPT="./docker-redis-config-manager.sh"
BASELINE_SCRIPT="./baseline-test.sh"

# Validate script dependencies
if [ ! -x "$CONFIG_SCRIPT" ]; then
  echo "ERROR: $CONFIG_SCRIPT not found or not executable"
  echo "Make sure the script exists and run: chmod +x $CONFIG_SCRIPT"
  exit 1
fi

if [ ! -x "$BASELINE_SCRIPT" ]; then
  echo "ERROR: $BASELINE_SCRIPT not found or not executable"
  echo "Make sure the script exists and run: chmod +x $BASELINE_SCRIPT"
  exit 1
fi

# Results directory setup
RESULTS_DIR="../results"
mkdir -p "$RESULTS_DIR"
EXPERIMENT_ID="validation_$(date +%Y%m%d_%H%M%S)"
EXPERIMENT_ROOT="$RESULTS_DIR/$EXPERIMENT_ID"
mkdir -p "$EXPERIMENT_ROOT"

# Environment configuration
BASE_URL=${BASE_URL:-"http://localhost:8080/api/orders"}
PAUSE_BETWEEN_CONFIGS=${PAUSE_BETWEEN_CONFIGS:-10}
PAUSE_BETWEEN_PROFILES=${PAUSE_BETWEEN_PROFILES:-5}
WARMUP_SECONDS=${WARMUP_SECONDS:-15}
WARMUP_RPS=${WARMUP_RPS:-5}

# Academic load profiles
LOW_DURATION=60;    LOW_RPM=180;    LOW_CONCURRENCY=3     # ~3 RPS
MEDIUM_DURATION=90; MEDIUM_RPM=600; MEDIUM_CONCURRENCY=5  # ~10 RPS
HIGH_DURATION=120;  HIGH_RPM=1200;  HIGH_CONCURRENCY=8    # ~20 RPS

echo "=== REDIS CONSISTENCY RESEARCH EXPERIMENT ==="
echo "Experiment ID: $EXPERIMENT_ID"
echo "Timestamp: $(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
echo ""
echo "Load Profiles:"
echo "  Low:    ${LOW_DURATION}s,  ${LOW_RPM} req/min,  ${LOW_CONCURRENCY} users  (~3 RPS)"
echo "  Medium: ${MEDIUM_DURATION}s, ${MEDIUM_RPM} req/min, ${MEDIUM_CONCURRENCY} users (~10 RPS)"
echo "  High:   ${HIGH_DURATION}s, ${HIGH_RPM} req/min, ${HIGH_CONCURRENCY} users (~20 RPS)"
echo ""

# Verify Redis container availability
REDIS_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i redis | head -1 || true)
if [ -z "$REDIS_CONTAINER" ]; then
  echo "ERROR: No Redis container found"
  echo "Available containers:"
  docker ps --format "table {{.Names}}\t{{.Status}}"
  exit 1
fi
echo "Using Redis container: $REDIS_CONTAINER"

# Create experiment metadata
cat > "$EXPERIMENT_ROOT/experiment_metadata.txt" << EOF
# Redis Consistency Research Experiment Metadata
Experiment ID: $EXPERIMENT_ID
Start Time: $(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')
Base URL: $BASE_URL
Redis Container: $REDIS_CONTAINER

# System Information
Docker Version: $(docker --version)
Host OS: $(uname -a)
Git Commit: $(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Load Profile Configuration
Low Load: ${LOW_DURATION}s, ${LOW_RPM} req/min, ${LOW_CONCURRENCY} concurrent
Medium Load: ${MEDIUM_DURATION}s, ${MEDIUM_RPM} req/min, ${MEDIUM_CONCURRENCY} concurrent
High Load: ${HIGH_DURATION}s, ${HIGH_RPM} req/min, ${HIGH_CONCURRENCY} concurrent

# Timing Configuration
Pause Between Configs: ${PAUSE_BETWEEN_CONFIGS}s
Pause Between Profiles: ${PAUSE_BETWEEN_PROFILES}s
Warm-up: ${WARMUP_SECONDS}s @ ~${WARMUP_RPS} rps
EOF

# Application health check function
health_check() {
  local max_attempts=3
  local attempt=1
  
  while [ $attempt -le $max_attempts ]; do
    echo "Health check attempt $attempt/$max_attempts..."
    
    # Try a simple API call
    if curl -sf -m 5 -X POST "$BASE_URL" \
       -H "Content-Type: application/json" \
       -H "Idempotency-Key: health-check-$(date +%s)" \
       -d '{"productId":1,"quantity":1}' >/dev/null 2>&1; then
      echo "SUCCESS: Application is healthy"
      return 0
    fi
    
    attempt=$((attempt + 1))
    if [ $attempt -le $max_attempts ]; then
      echo "Health check failed, retrying in 2 seconds..."
      sleep 2
    fi
  done
  
  echo "ERROR: Application health check failed after $max_attempts attempts"
  return 1
}

# Fixed warmup function using only shell arithmetic
warmup_system() {
  local config_type=$1
  
  if [ "$WARMUP_SECONDS" -le 0 ] || [ "$WARMUP_RPS" -le 0 ]; then
    echo "Warm-up skipped (WARMUP_SECONDS=$WARMUP_SECONDS, WARMUP_RPS=$WARMUP_RPS)"
    return 0
  fi

  echo "Warming up system (${WARMUP_SECONDS}s @ ~${WARMUP_RPS} rps) for $config_type ..."
  
  # Calculate delay using shell arithmetic - avoid floating point
  # Convert to milliseconds for more precision
  local delay_ms
  if [ "$WARMUP_RPS" -gt 0 ]; then
    delay_ms=$(( 1000 / WARMUP_RPS ))
  else
    delay_ms=1000  # 1 second default
  fi
  
  # Convert back to seconds with decimal
  local delay_seconds
  if [ "$delay_ms" -ge 1000 ]; then
    delay_seconds=$(( delay_ms / 1000 ))
  else
    delay_seconds="0.${delay_ms}"
  fi
  
  echo "  Using ${delay_seconds}s delay between warmup requests"
  
  local end_ts=$(( $(date +%s) + WARMUP_SECONDS ))
  local warmup_count=0
  
  while [ "$(date +%s)" -lt "$end_ts" ]; do
    warmup_count=$((warmup_count + 1))
    
    # Generate unique timestamp for each warmup request
    local timestamp_ms=$(date +%s%3N 2>/dev/null || echo "$(date +%s)$(printf "%03d" $((RANDOM % 1000)))")
    
    # Execute warmup request with short timeout
    curl -sS -m 2 --connect-timeout 1 \
      -X POST "$BASE_URL" \
      -H "Content-Type: application/json" \
      -H "Idempotency-Key: warmup-${config_type}-${timestamp_ms}" \
      -d '{"productId":1,"quantity":1}' >/dev/null 2>&1 || true
    
    # Use shell-compatible sleep
    sleep "$delay_seconds"
  done
  
  echo "System warmup completed ($warmup_count requests)"
}

# Load profile execution function
run_load_profile() {
  local config_type=$1
  local profile_name=$2
  local duration=$3
  local rpm=$4
  local concurrency=$5

  echo ""
  echo ">>> Executing $profile_name profile for $config_type configuration"
  echo "    Duration: ${duration}s, Rate: ${rpm} req/min, Concurrency: ${concurrency}"

  # Health check before test
  if ! health_check; then
    echo "ERROR: Health check failed before $profile_name test"
    return 1
  fi

  # System warmup
  warmup_system "$config_type"

  # FIXED: Create profile directory first to avoid conflicts
  local profile_dir="$CONFIG_DIR/$profile_name"
  mkdir -p "$profile_dir"

  # Execute baseline test and capture output
  local baseline_stdout="$profile_dir/baseline_execution.log"
  BASE_URL="$BASE_URL" "$BASELINE_SCRIPT" "$duration" "$rpm" "$concurrency" > "$baseline_stdout" 2>&1

  # Find the most recent baseline result from the log
  local baseline_result_dir
  baseline_result_dir=$(grep -E '^OUT_DIR=' "$baseline_stdout" | tail -1 | cut -d= -f2 2>/dev/null || true)
  
  if [ -z "$baseline_result_dir" ]; then
    # Fallback: find most recent baseline directory
    baseline_result_dir=$(ls -dt "$RESULTS_DIR"/baseline_* 2>/dev/null | head -1 || true)
  fi
  
  if [ -z "$baseline_result_dir" ] || [ ! -d "$baseline_result_dir" ]; then
    echo "ERROR: No baseline result found for $config_type/$profile_name"
    return 1
  fi

  # Move results to organized directory structure
  if [ -d "$baseline_result_dir" ]; then
    # Copy/move all contents from baseline result to profile directory
    cp -r "$baseline_result_dir"/* "$profile_dir/" 2>/dev/null || {
      echo "WARNING: Failed to copy baseline results, trying move..."
      mv "$baseline_result_dir"/* "$profile_dir/" 2>/dev/null || {
        echo "ERROR: Failed to move baseline results from $baseline_result_dir"
        return 1
      }
    }
    # Clean up original directory
    rmdir "$baseline_result_dir" 2>/dev/null || true
  fi

  # Add profile metadata
  cat > "$profile_dir/profile_metadata.txt" << EOF
Configuration: $config_type
Profile: $profile_name
Duration: ${duration}s
Target Rate: ${rpm} req/min
Concurrency: ${concurrency}
Execution Time: $(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')
Warmup: ${WARMUP_SECONDS}s @ ${WARMUP_RPS} rps
BaselineResultDir: $baseline_result_dir
EOF

  echo "    Results saved to: $profile_dir"

  # Brief pause between profiles
  if [ "$PAUSE_BETWEEN_PROFILES" -gt 0 ]; then
    echo "    Pausing ${PAUSE_BETWEEN_PROFILES}s before next profile..."
    sleep "$PAUSE_BETWEEN_PROFILES"
  fi

  return 0
}

# Configuration test suite function
run_configuration_suite() {
  local config_type=$1

  echo ""
  echo "===== TESTING CONFIGURATION: $config_type ====="
  echo "Timestamp: $(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"

  # Apply Redis configuration
  if ! "$CONFIG_SCRIPT" "$config_type"; then
    echo "ERROR: Failed to apply $config_type configuration"
    return 1
  fi

  # Verify configuration was applied
  local appendonly appendfsync maxmemory policy
  appendonly=$(docker exec "$REDIS_CONTAINER" redis-cli config get appendonly 2>/dev/null | tail -1 || echo "unknown")
  appendfsync=$(docker exec "$REDIS_CONTAINER" redis-cli config get appendfsync 2>/dev/null | tail -1 || echo "unknown")
  maxmemory=$(docker exec "$REDIS_CONTAINER" redis-cli config get maxmemory 2>/dev/null | tail -1 || echo "unknown")
  policy=$(docker exec "$REDIS_CONTAINER" redis-cli config get maxmemory-policy 2>/dev/null | tail -1 || echo "unknown")

  echo "Configuration verified:"
  echo "  appendonly=$appendonly"
  echo "  appendfsync=$appendfsync"
  echo "  maxmemory=$maxmemory"
  echo "  maxmemory-policy=$policy"

  # Create configuration directory
  CONFIG_DIR="$EXPERIMENT_ROOT/$config_type"
  mkdir -p "$CONFIG_DIR"

  # Save configuration snapshot
  cat > "$CONFIG_DIR/redis_config_snapshot.txt" << EOF
# Redis Configuration Snapshot for $config_type
Timestamp: $(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')
Configuration Type: $config_type

appendonly: $appendonly
appendfsync: $appendfsync
maxmemory: $maxmemory
maxmemory-policy: $policy
save: $(docker exec "$REDIS_CONTAINER" redis-cli config get save 2>/dev/null | tail -1 || echo "unknown")
rdbcompression: $(docker exec "$REDIS_CONTAINER" redis-cli config get rdbcompression 2>/dev/null | tail -1 || echo "unknown")
no-appendfsync-on-rewrite: $(docker exec "$REDIS_CONTAINER" redis-cli config get no-appendfsync-on-rewrite 2>/dev/null | tail -1 || echo "unknown")
auto-aof-rewrite-percentage: $(docker exec "$REDIS_CONTAINER" redis-cli config get auto-aof-rewrite-percentage 2>/dev/null | tail -1 || echo "unknown")
auto-aof-rewrite-min-size: $(docker exec "$REDIS_CONTAINER" redis-cli config get auto-aof-rewrite-min-size 2>/dev/null | tail -1 || echo "unknown")
EOF

  # Pause to let system stabilize
  if [ "$PAUSE_BETWEEN_CONFIGS" -gt 0 ]; then
    echo "Allowing system to stabilize for ${PAUSE_BETWEEN_CONFIGS}s..."
    sleep "$PAUSE_BETWEEN_CONFIGS"
  fi

  # Execute all load profiles
  run_load_profile "$config_type" "low"    $LOW_DURATION    $LOW_RPM    $LOW_CONCURRENCY    || return 1
  run_load_profile "$config_type" "medium" $MEDIUM_DURATION $MEDIUM_RPM $MEDIUM_CONCURRENCY || return 1
  run_load_profile "$config_type" "high"   $HIGH_DURATION   $HIGH_RPM   $HIGH_CONCURRENCY   || return 1

  echo "Configuration $config_type testing completed successfully"
  return 0
}

# Results aggregation function
aggregate_results() {
  local consolidated_file="$EXPERIMENT_ROOT/consolidated_results.csv"

  echo ""
  echo "Aggregating experimental results..."

  # CSV header
  echo "config,profile,total_requests,success,failed,error_rate_percent,throughput_rps,p50_ms,p95_ms,p99_ms,idempotency_hit_rate_percent,timeout_count,http_4xx_count,http_5xx_count" > "$consolidated_file"

  # Process each configuration and profile combination
  for config in strong balanced performance; do
    for profile in low medium high; do
      local summary_file
      summary_file=$(find "$EXPERIMENT_ROOT/$config/$profile" -name "summary.txt" 2>/dev/null | head -1)

      if [ -f "$summary_file" ]; then
        # Extract metrics from summary file with safe fallbacks
        local total success failed error_rate throughput p50 p95 p99 hit_rate timeout http4xx http5xx
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

        # Add to consolidated results
        echo "$config,$profile,$total,$success,$failed,$error_rate,$throughput,$p50,$p95,$p99,$hit_rate,$timeout,$http4xx,$http5xx" >> "$consolidated_file"
      else
        echo "WARNING: Missing summary file for $config/$profile"
        # Add empty row to maintain data structure
        echo "$config,$profile,0,0,0,0,0,0,0,0,0,0,0,0" >> "$consolidated_file"
      fi
    done
  done

  echo "Consolidated results saved to: $consolidated_file"
}

# Performance summary generation
generate_performance_summary() {
  local summary_file="$EXPERIMENT_ROOT/performance_summary.md"

  cat > "$summary_file" << EOF
# Redis Consistency Configuration Performance Study Results

**Experiment ID:** $EXPERIMENT_ID  
**Execution Date:** $(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')  
**Redis Container:** $REDIS_CONTAINER

## Experimental Setup

### Load Profiles
- **Low Load:** ${LOW_DURATION}s duration, ${LOW_RPM} req/min, ${LOW_CONCURRENCY} concurrent users (~3 RPS)
- **Medium Load:** ${MEDIUM_DURATION}s duration, ${MEDIUM_RPM} req/min, ${MEDIUM_CONCURRENCY} concurrent users (~10 RPS)  
- **High Load:** ${HIGH_DURATION}s duration, ${HIGH_RPM} req/min, ${HIGH_CONCURRENCY} concurrent users (~20 RPS)

### Redis Configurations Tested
1. **Strong Consistency:** appendfsync=always, save="60 1", maxmemory-policy=noeviction
2. **Balanced Configuration:** appendfsync=everysec, save="900 1 300 10 60 10000", maxmemory-policy=allkeys-lru
3. **Performance Optimized:** appendfsync=no, save="", maxmemory-policy=volatile-lru

### Methodology Improvements
- Active warm-up: ${WARMUP_SECONDS}s @ ~${WARMUP_RPS} rps before each test
- System stabilization: ${PAUSE_BETWEEN_CONFIGS}s pause after configuration changes
- Inter-test pause: ${PAUSE_BETWEEN_PROFILES}s between load profiles
- Idempotency testing with ~30% repeated keys

## Key Findings

*To be filled with analysis of consolidated_results.csv*

## Data Files
- **Consolidated Results:** consolidated_results.csv
- **Raw Test Data:** Available in respective configuration/profile subdirectories
- **Configuration Snapshots:** redis_config_snapshot.txt in each configuration directory

EOF

  echo "Performance summary template created: $summary_file"
}

# Main execution flow
main() {
  echo "Starting Redis consistency configuration experiment..."

  # Execute test suite for each configuration
  run_configuration_suite "strong"      || { echo "FAILED: strong configuration test"; exit 1; }
  run_configuration_suite "balanced"    || { echo "FAILED: balanced configuration test"; exit 1; }
  run_configuration_suite "performance" || { echo "FAILED: performance configuration test"; exit 1; }

  # Aggregate and analyze results
  aggregate_results
  generate_performance_summary

  # Final experiment metadata
  cat >> "$EXPERIMENT_ROOT/experiment_metadata.txt" << EOF

# Experiment Completion
End Time: $(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')
Total Duration: $(($(date +%s) - START_EPOCH)) seconds
Status: COMPLETED SUCCESSFULLY
EOF

  echo ""
  echo "=== EXPERIMENT COMPLETED SUCCESSFULLY ==="
  echo "Results Location: $EXPERIMENT_ROOT"
  echo "Consolidated Data: $EXPERIMENT_ROOT/consolidated_results.csv"
  echo "Performance Summary: $EXPERIMENT_ROOT/performance_summary.md"
  echo ""
  echo "Next Steps:"
  echo "1. Analyze consolidated_results.csv for performance trends"
  echo "2. Generate visualizations from the aggregated data"
  echo "3. Document findings in the performance summary"
  echo ""
}

# Execute main function
main "$@"