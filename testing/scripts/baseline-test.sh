#!/bin/bash
# Academic Baseline Load Test for Redis Consistency Research
# Fixed version with correct rate calculation and resolved issues
# Usage: ./baseline-test.sh <DURATION_SECONDS> <REQUEST_RATE_PER_MIN> <CONCURRENT_USERS>

set -euo pipefail

# Test parameters
TEST_DURATION=${1:-60}
RATE_PER_MINUTE=${2:-300}
CONCURRENT_USERS=${3:-3}
BASE_URL=${BASE_URL:-"http://localhost:8080/api/orders"}

# Enhanced timeout settings
TIMEOUT_CONNECT=${TIMEOUT_CONNECT:-2}
TIMEOUT_TOTAL=${TIMEOUT_TOTAL:-5}
REQUEST_DELAY=${REQUEST_DELAY:-0}

# Quality thresholds for assessment
ERROR_THRESHOLD=${ERROR_THRESHOLD:-5}      # 5% max acceptable error rate
HIGH_LATENCY_THRESHOLD=${HIGH_LATENCY_THRESHOLD:-2000}  # 2000ms

# Results directory setup
RESULTS_DIR="../results"
mkdir -p "$RESULTS_DIR"
TS=$(date +%Y%m%d_%H%M%S)
OUT_DIR="$RESULTS_DIR/baseline_${TS}"
mkdir -p "$OUT_DIR"

# Output the directory for external scripts to track
echo "OUT_DIR=$OUT_DIR"

# Output files
RESULTS_FILE="$OUT_DIR/results.csv"
TIMES_FILE="$OUT_DIR/response_times_ms.txt"
METRICS_FILE="$OUT_DIR/metrics.csv"
ERRORS_FILE="$OUT_DIR/errors.log"
TIMING_FILE="$OUT_DIR/request_timing.csv"

# Initialize output files
echo "timestamp,idempotency_key,product_id,quantity,response_time_ms,http_code,order_id,success" > "$RESULTS_FILE"
echo "worker_id,request_num,start_time,end_time,response_time_ms,success" > "$TIMING_FILE"
: > "$TIMES_FILE"
: > "$ERRORS_FILE"

# Calculate test parameters with improved precision
END_TIME=$(( $(date +%s) + TEST_DURATION ))

# FIXED: Correct rate calculation
if [ $CONCURRENT_USERS -gt 0 ]; then
  # Calculate target RPS and distribute among workers
  TARGET_RPS=$(( RATE_PER_MINUTE / 60 ))
  [ $TARGET_RPS -lt 1 ] && TARGET_RPS=1

  PER_WORKER_RPS=$(( TARGET_RPS / CONCURRENT_USERS ))
  [ $PER_WORKER_RPS -lt 1 ] && PER_WORKER_RPS=1

  # Convert back to RPM for display and delay calculation
  PER_WORKER_RPM=$(( PER_WORKER_RPS * 60 ))
else
  PER_WORKER_RPM=$RATE_PER_MINUTE
  PER_WORKER_RPS=$(( PER_WORKER_RPM / 60 ))
fi

# Improved delay calculation using lookup table and fallback
calculate_delay() {
  local rps="$1"
  case $rps in
    1) echo "1.000" ;;
    2) echo "0.500" ;;
    3) echo "0.333" ;;
    4) echo "0.250" ;;
    5) echo "0.200" ;;
    6) echo "0.167" ;;
    10) echo "0.100" ;;
    12) echo "0.083" ;;
    15) echo "0.067" ;;
    20) echo "0.050" ;;
    *) 
      # For other values, use integer math with better precision
      if [ "$rps" -gt 0 ]; then
        local delay_ms=$(( 1000 / rps ))
        printf "%d.%03d" $((delay_ms / 1000)) $((delay_ms % 1000))
      else
        echo "1.000"
      fi
      ;;
  esac
}

BASE_DELAY=$(calculate_delay "$PER_WORKER_RPS")

# Add jitter to prevent thundering herd
add_jitter() {
  local base_delay="$1"
  local jitter_percent=10  # 10% jitter

  # Extract integer and decimal parts
  local int_part=${base_delay%.*}
  local dec_part=${base_delay#*.}

  # Convert to milliseconds for calculation
  local total_ms=$(( int_part * 1000 + 10#$dec_part ))

  # FIXED: Calculate jitter (±10%)
  local jitter_amount=$(( total_ms * jitter_percent / 100 ))
  local random_jitter=$(( (RANDOM % (jitter_amount * 2 + 1)) - jitter_amount ))

  # Apply jitter
  local jittered_ms=$(( total_ms + random_jitter ))
  [ $jittered_ms -lt 50 ] && jittered_ms=50  # Minimum 50ms

  printf "%d.%03d" $((jittered_ms / 1000)) $((jittered_ms % 1000))
}

TOTAL_DELAY=$(add_jitter "$BASE_DELAY")

# Worker directory
WORK_DIR="$OUT_DIR/workers"
mkdir -p "$WORK_DIR"

# Enhanced test configuration logging
cat > "$OUT_DIR/test_config.txt" << EOF
# Fixed Academic Baseline Test Configuration
Test Start: $(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')
Duration: ${TEST_DURATION} seconds
Target Rate: ${RATE_PER_MINUTE} requests/minute
Target RPS: ${TARGET_RPS} requests/second
Concurrent Users: ${CONCURRENT_USERS}
Per-Worker RPS: ${PER_WORKER_RPS} requests/second
Per-Worker Rate: ${PER_WORKER_RPM} requests/minute
Base Request Delay: ${BASE_DELAY} seconds
Actual Request Delay (with jitter): ${TOTAL_DELAY} seconds
Base URL: ${BASE_URL}
Timeout Settings: connect=${TIMEOUT_CONNECT}s, total=${TIMEOUT_TOTAL}s
Jitter: 10% for realistic timing variation
Enhanced Features: Fixed rate calculation, improved percentiles, timing validation
System: Enhanced MinGW/Windows Compatible Mode
EOF

echo "=== FIXED ACADEMIC BASELINE LOAD TEST ==="
echo "Configuration:"
echo "  Duration: ${TEST_DURATION}s"
echo "  Target Rate: ${RATE_PER_MINUTE} req/min (${TARGET_RPS} RPS total)"
echo "  Concurrent Users: ${CONCURRENT_USERS}"
echo "  Per-Worker: ${PER_WORKER_RPS} RPS (${PER_WORKER_RPM} req/min)"
echo "  Request Delay: ${TOTAL_DELAY}s (includes 10% jitter)"
echo "  Endpoint: ${BASE_URL}"
echo "  Features: Fixed rate calculation, enhanced percentiles"
echo ""

# Enhanced worker function with better timing tracking
worker() {
  local worker_id=$1
  local end_timestamp=$2
  local worker_csv="$WORK_DIR/results_${worker_id}.csv"
  local worker_times="$WORK_DIR/times_${worker_id}.txt"
  local worker_errors="$WORK_DIR/errors_${worker_id}.log"
  local worker_timing="$WORK_DIR/timing_${worker_id}.csv"

  # Initialize worker files
  echo "timestamp,idempotency_key,product_id,quantity,response_time_ms,http_code,order_id,success" > "$worker_csv"
  echo "worker_id,request_num,start_time,end_time,response_time_ms,success" > "$worker_timing"
  : > "$worker_times"
  : > "$worker_errors"

  local request_count=0
  local last_request_time=$(date +%s)

  while [ "$(date +%s)" -lt "$end_timestamp" ]; do
    request_count=$((request_count + 1))
    local request_start_time=$(date +%s%3N 2>/dev/null || echo "$(date +%s)000")