#!/bin/bash
# Docker Redis Configuration Manager (Academic Research Configurations)
# Usage: ./docker-redis-config-manager.sh [strong|balanced|performance]
# Based on academic research configurations for Redis consistency study

set -euo pipefail

CONFIG_TYPE=${1:-}
if [ -z "$CONFIG_TYPE" ]; then
  echo "Usage: $0 [strong|balanced|performance]"
  echo ""
  echo "Available configurations:"
  echo "  strong      - High consistency (appendfsync=always)"
  echo "  balanced    - Balanced consistency-performance (appendfsync=everysec)"
  echo "  performance - Performance optimized (appendfsync=no)"
  exit 1
fi

echo "=== REDIS CONSISTENCY CONFIGURATION MANAGER ==="
echo "Applying academic research profile: $CONFIG_TYPE"
echo ""

# Find Redis container
REDIS_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i redis | head -1 || true)
if [ -z "$REDIS_CONTAINER" ]; then
  echo "ERROR: No Redis container found."
  echo "Available containers:"
  docker ps --format "table {{.Names}}\t{{.Status}}"
  exit 1
fi
echo "SUCCESS: Found Redis container: $REDIS_CONTAINER"

# Redis CLI wrapper
redis_cmd() {
  docker exec "$REDIS_CONTAINER" redis-cli "$@"
}

# Test connectivity
if ! redis_cmd ping >/dev/null 2>&1; then
  echo "ERROR: Cannot connect to Redis in Docker."
  echo "Please check if Redis is running and accessible."
  exit 1
fi
echo "SUCCESS: Redis connectivity verified"

# Create results directory structure
RESULTS_DIR="../results"
mkdir -p "$RESULTS_DIR"
TS=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$RESULTS_DIR/config_backup/$TS"
mkdir -p "$BACKUP_DIR"

# FIXED: Enhanced backup with error handling
echo "Creating configuration backup..."
cat > "$BACKUP_DIR/redis_config_backup.txt" << EOF
# Redis Configuration Backup - $(date)
# Container: $REDIS_CONTAINER
# Backup ID: $TS

appendonly=$(redis_cmd config get appendonly 2>/dev/null | tail -1 || echo "unknown")
appendfsync=$(redis_cmd config get appendfsync 2>/dev/null | tail -1 || echo "unknown")
save=$(redis_cmd config get save 2>/dev/null | tail -1 || echo "unknown")
rdbcompression=$(redis_cmd config get rdbcompression 2>/dev/null | tail -1 || echo "unknown")
maxmemory=$(redis_cmd config get maxmemory 2>/dev/null | tail -1 || echo "unknown")
maxmemory-policy=$(redis_cmd config get maxmemory-policy 2>/dev/null | tail -1 || echo "unknown")
no-appendfsync-on-rewrite=$(redis_cmd config get no-appendfsync-on-rewrite 2>/dev/null | tail -1 || echo "unknown")
auto-aof-rewrite-percentage=$(redis_cmd config get auto-aof-rewrite-percentage 2>/dev/null | tail -1 || echo "unknown")
auto-aof-rewrite-min-size=$(redis_cmd config get auto-aof-rewrite-min-size 2>/dev/null | tail -1 || echo "unknown")
EOF
echo "SUCCESS: Configuration backup saved to: $BACKUP_DIR"

# Apply academic research configurations
echo ""
echo "Applying $CONFIG_TYPE configuration..."

case "$CONFIG_TYPE" in
  strong)
    echo "Academic rationale: Maximum consistency for financial-critical workloads"
    echo "Configuration: appendfsync=always, frequent snapshots, no eviction"
    echo ""
    
    # Core persistence settings
    redis_cmd config set appendonly yes
    redis_cmd config set appendfsync always
    redis_cmd config set save "60 1"
    redis_cmd config set rdbcompression yes
    
    # Memory and eviction policy
    redis_cmd config set maxmemory 2gb
    redis_cmd config set maxmemory-policy noeviction
    
    # AOF rewrite settings (conservative)
    redis_cmd config set no-appendfsync-on-rewrite no
    redis_cmd config set auto-aof-rewrite-percentage 100
    redis_cmd config set auto-aof-rewrite-min-size 64mb
    ;;

  balanced)
    echo "Academic rationale: Balanced trade-off for e-commerce transactions"
    echo "Configuration: appendfsync=everysec, standard snapshots, smart eviction"
    echo ""
    
    # Core persistence settings
    redis_cmd config set appendonly yes
    redis_cmd config set appendfsync everysec
    redis_cmd config set save "900 1 300 10 60 10000"
    redis_cmd config set rdbcompression yes
    
    # Memory and eviction policy
    redis_cmd config set maxmemory 2gb
    redis_cmd config set maxmemory-policy allkeys-lru
    
    # AOF rewrite settings (balanced)
    redis_cmd config set no-appendfsync-on-rewrite yes
    redis_cmd config set auto-aof-rewrite-percentage 100
    redis_cmd config set auto-aof-rewrite-min-size 64mb
    ;;

  performance)
    echo "Academic rationale: Maximum throughput for analytics/read-heavy workloads"
    echo "Configuration: appendfsync=no, minimal snapshots, aggressive eviction"
    echo ""
    
    # Core persistence settings
    redis_cmd config set appendonly yes
    redis_cmd config set appendfsync no
    redis_cmd config set save ""
    redis_cmd config set rdbcompression no
    
    # Memory and eviction policy
    redis_cmd config set maxmemory 2gb
    redis_cmd config set maxmemory-policy volatile-lru
    
    # AOF rewrite settings (performance optimized)
    redis_cmd config set no-appendfsync-on-rewrite yes
    redis_cmd config set auto-aof-rewrite-percentage 200
    redis_cmd config set auto-aof-rewrite-min-size 128mb
    
    # Additional performance optimizations
    redis_cmd config set lazyfree-lazy-eviction yes 2>/dev/null || true
    ;;

  *)
    echo "ERROR: Invalid configuration type: $CONFIG_TYPE"
    echo "Valid options: strong, balanced, performance"
    exit 1
    ;;
esac

# Verification and audit trail
echo ""
echo "Verifying applied configuration..."
VER_FILE="$RESULTS_DIR/config_verification_${TS}.txt"
cat > "$VER_FILE" << EOF
# Redis Configuration Verification
Configuration Type: $CONFIG_TYPE
Applied Timestamp: $(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')
Container: $REDIS_CONTAINER
Verification ID: $TS

# Core Persistence Settings
appendonly: $(redis_cmd config get appendonly 2>/dev/null | tail -1 || echo "unknown")
appendfsync: $(redis_cmd config get appendfsync 2>/dev/null | tail -1 || echo "unknown")
save: $(redis_cmd config get save 2>/dev/null | tail -1 || echo "unknown")
rdbcompression: $(redis_cmd config get rdbcompression 2>/dev/null | tail -1 || echo "unknown")

# Memory Management
maxmemory: $(redis_cmd config get maxmemory 2>/dev/null | tail -1 || echo "unknown")
maxmemory-policy: $(redis_cmd config get maxmemory-policy 2>/dev/null | tail -1 || echo "unknown")

# AOF Rewrite Settings
no-appendfsync-on-rewrite: $(redis_cmd config get no-appendfsync-on-rewrite 2>/dev/null | tail -1 || echo "unknown")
auto-aof-rewrite-percentage: $(redis_cmd config get auto-aof-rewrite-percentage 2>/dev/null | tail -1 || echo "unknown")
auto-aof-rewrite-min-size: $(redis_cmd config get auto-aof-rewrite-min-size 2>/dev/null | tail -1 || echo "unknown")

# Additional Settings
lazyfree-lazy-eviction: $(redis_cmd config get lazyfree-lazy-eviction 2>/dev/null | tail -1 || echo "unknown")
EOF

echo "SUCCESS: Configuration verification saved to: $VER_FILE"

# Display current configuration summary
echo ""
echo "=== CONFIGURATION SUMMARY ==="
echo "Type: $CONFIG_TYPE"
echo "appendonly: $(redis_cmd config get appendonly 2>/dev/null | tail -1 || echo "unknown")"
echo "appendfsync: $(redis_cmd config get appendfsync 2>/dev/null | tail -1 || echo "unknown")"
echo "save: $(redis_cmd config get save 2>/dev/null | tail -1 || echo "unknown")"
echo "maxmemory: $(redis_cmd config get maxmemory 2>/dev/null | tail -1 || echo "unknown")"
echo "maxmemory-policy: $(redis_cmd config get maxmemory-policy 2>/dev/null | tail -1 || echo "unknown")"

echo ""
echo "NOTICE: These are runtime-only changes."
echo "If the Redis container restarts, configuration will revert to defaults."
echo "For persistent changes, modify redis.conf in your Docker setup."
echo ""
echo "=== CONFIGURATION APPLIED SUCCESSFULLY: $CONFIG_TYPE ==="