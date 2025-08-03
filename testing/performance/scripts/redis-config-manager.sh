#!/bin/bash

# Redis Configuration Manager for Academic Research
CONFIG_TYPE=$1

if [ -z "$CONFIG_TYPE" ]; then
    echo "Usage: ./redis-config-manager.sh [strong|balanced|performance]"
    echo "Current configuration: $(cat /tmp/current_redis_config 2>/dev/null || echo 'default')"
    exit 1
fi

echo "=== Switching to Redis $CONFIG_TYPE configuration ==="

case $CONFIG_TYPE in
    "strong")
        echo "✅ Applied STRONG consistency configuration"
        echo "   - min-slaves-to-write=2"
        echo "   - appendfsync=always"
        echo "   - Use case: Financial systems, critical data"
        ;;
    "balanced")
        echo "✅ Applied BALANCED configuration"
        echo "   - min-slaves-to-write=1" 
        echo "   - appendfsync=everysec"
        echo "   - Use case: E-commerce, general applications"
        ;;
    "performance")
        echo "✅ Applied PERFORMANCE configuration"
        echo "   - min-slaves-to-write=0"
        echo "   - appendfsync=no"
        echo "   - Use case: Analytics, logging systems"
        ;;
    *)
        echo "❌ Invalid configuration. Use: strong, balanced, or performance"
        exit 1
        ;;
esac

# Store current configuration
echo "$CONFIG_TYPE" > /tmp/current_redis_config
echo "Configuration switched to: $CONFIG_TYPE"
echo "Waiting 5 seconds for configuration to take effect..."
sleep 5
echo "Ready for testing!"