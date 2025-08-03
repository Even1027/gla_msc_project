#!/bin/bash

echo "==============================================="
echo "REDIS CONFIGURATION COMPARISON RESULTS"
echo "==============================================="

RESULTS_DIR="../results/baseline"

# 查看最近的3个测试结果
echo "Recent test results:"
ls -lt "$RESULTS_DIR" | head -4

echo ""
echo "Comparing metrics from recent tests:"

# 找到最近的3个目录
RECENT_DIRS=($(ls -t "$RESULTS_DIR" | head -3))

echo ""
echo "Configuration | Throughput | P95 Latency | Error Rate | Cache Effectiveness"
echo "-------------|------------|-------------|------------|-------------------"

for i in "${!RECENT_DIRS[@]}"; do
    CONFIG_NAME=""
    case $i in
        0) CONFIG_NAME="LATEST    " ;;
        1) CONFIG_NAME="MIDDLE    " ;;
        2) CONFIG_NAME="EARLIEST  " ;;
    esac
    
    METRICS_FILE="$RESULTS_DIR/${RECENT_DIRS[$i]}/core_metrics_report.txt"
    
    if [ -f "$METRICS_FILE" ]; then
        THROUGHPUT=$(grep "Successful Requests/Second:" "$METRICS_FILE" | grep -o '[0-9]*\.[0-9]*' || echo "N/A")
        P95=$(grep "P95.*:" "$METRICS_FILE" | grep -o '[0-9]*' | head -1 || echo "N/A")
        ERROR=$(grep "Error Rate:" "$METRICS_FILE" | grep -o '[0-9]*\.[0-9]*' || echo "N/A")
        CACHE=$(grep "Cache Effectiveness:" "$METRICS_FILE" | grep -o '[0-9]*\.[0-9]*' || echo "N/A")
        
        printf "%-12s | %-10s | %-11s | %-10s | %-18s\n" \
            "$CONFIG_NAME" "${THROUGHPUT} req/s" "${P95} ms" "${ERROR}%" "${CACHE}%"
    fi
done

echo ""
echo " Comparison complete!"
echo " Detailed reports available in: $RESULTS_DIR"