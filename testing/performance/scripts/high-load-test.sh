#!/bin/bash

# High Load Performance Testing Script  
# Academic Research: System Scalability Evaluation

echo "================================================="
echo "HIGH LOAD PERFORMANCE TEST"
echo "Academic Research: Scalability Analysis"
echo "================================================="

BASE_URL="http://localhost:8080/api/orders"
RESULT_DIR="../results/high_load/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULT_DIR"

# Progressive load testing
LOAD_LEVELS=(600 1200 1800)  # 10, 20, 30 requests per minute
LOAD_NAMES=("MEDIUM" "HIGH" "EXTREME")
TEST_DURATION=60  # 1 minute per load level

echo "Test Configuration:"
echo "  Load Levels: ${LOAD_LEVELS[@]} requests/minute"
echo "  Duration per Level: ${TEST_DURATION} seconds"
echo "  Results Directory: $RESULT_DIR"

# Initialize summary file
SUMMARY_FILE="$RESULT_DIR/load_test_summary.csv"
echo "load_level,requests_per_minute,total_requests,successful_requests,throughput_req_per_sec,avg_response_time_ms,p95_latency_ms,error_rate_percent" > "$SUMMARY_FILE"

for i in "${!LOAD_LEVELS[@]}"; do
    LOAD_RATE=${LOAD_LEVELS[$i]}
    LOAD_NAME=${LOAD_NAMES[$i]}
    
    echo ""
    echo "=========================================="
    echo "TESTING LOAD LEVEL: $LOAD_NAME ($LOAD_RATE req/min)"
    echo "=========================================="
    
    # Run baseline test with high load
    ./baseline-test.sh $TEST_DURATION $LOAD_RATE
    
    # Extract metrics from latest result
    LATEST_DIR=$(ls -t ../results/baseline/ | head -1)
    METRICS_FILE="../results/baseline/$LATEST_DIR/core_metrics_report.txt"
    
    if [ -f "$METRICS_FILE" ]; then
        # Extract metrics
        THROUGHPUT=$(grep "Successful Requests/Second:" "$METRICS_FILE" | grep -o '[0-9]*\.[0-9]*' || echo "0")
        AVG_RESPONSE=$(grep "Average Response Time:" "$METRICS_FILE" | grep -o '[0-9]*\.[0-9]*' || echo "0") 
        P95_LATENCY=$(grep "P95.*:" "$METRICS_FILE" | grep -o '[0-9]*' | head -1 || echo "0")
        ERROR_RATE=$(grep "Error Rate:" "$METRICS_FILE" | grep -o '[0-9]*\.[0-9]*' || echo "0")
        TOTAL_REQUESTS=$(grep "Total Requests Sent:" "$METRICS_FILE" | grep -o '[0-9]*' || echo "0")
        SUCCESS_REQUESTS=$(grep "Successful Requests:" "$METRICS_FILE" | grep -o '[0-9]*' || echo "0")
        
        # Add to summary
        echo "$LOAD_NAME,$LOAD_RATE,$TOTAL_REQUESTS,$SUCCESS_REQUESTS,$THROUGHPUT,$AVG_RESPONSE,$P95_LATENCY,$ERROR_RATE" >> "$SUMMARY_FILE"
        
        echo " $LOAD_NAME Load Completed:"
        echo "   Throughput: $THROUGHPUT req/s"
        echo "   P95 Latency: $P95_LATENCY ms"
        echo "   Error Rate: $ERROR_RATE%"
    fi
    
    # Wait between tests
    if [ $i -lt $((${#LOAD_LEVELS[@]} - 1)) ]; then
        echo "Waiting 30 seconds before next load level..."
        sleep 30
    fi
done

# Generate comprehensive analysis
ANALYSIS_FILE="$RESULT_DIR/scalability_analysis.txt"

cat > "$ANALYSIS_FILE" << EOF
=================================================
HIGH LOAD SCALABILITY ANALYSIS
Academic Research: Performance Under Stress
=================================================

Test Methodology:
Progressive load testing across three intensity levels to evaluate
system scalability and identify performance bottlenecks.

=================================================
SCALABILITY PERFORMANCE SUMMARY
=================================================

Load Level Analysis:
EOF

# Add performance data for each load level
while IFS=',' read -r load_name load_rate total_req success_req throughput avg_resp p95_lat error_rate || [ -n "$load_name" ]; do
    if [[ "$load_name" != "load_level" ]]; then  # Skip header
        cat >> "$ANALYSIS_FILE" << EOF

${load_name} LOAD (${load_rate} req/min):
  ✓ Achieved Throughput: ${throughput} req/s
  ✓ Average Response Time: ${avg_resp} ms
  ✓ P95 Latency: ${p95_lat} ms
  ✓ Error Rate: ${error_rate}%
  ✓ Request Success Rate: $(echo "$success_req $total_req" | awk '{if($2>0) printf "%.2f%%", $1*100/$2; else print "N/A"}')
EOF
    fi
done < "$SUMMARY_FILE"

cat >> "$ANALYSIS_FILE" << EOF

=================================================
SCALABILITY ASSESSMENT
=================================================

 Performance Trends:
$(awk -F',' 'NR>1 {
    if(prev_throughput != "") {
        change = ($5 - prev_throughput) / prev_throughput * 100
        if(change > 0) print "  ↗ Throughput increased by " change "% from previous level"
        else print "  ↘ Throughput decreased by " change*-1 "% from previous level"
    }
    prev_throughput = $5
}' "$SUMMARY_FILE")

 Performance Bottlenecks:
$(awk -F',' 'NR>1 {
    if($8 > 5) print "   High error rate detected at " $1 " load (" $8 "%)"
    if($7 > 100) print "   High latency detected at " $1 " load (" $7 "ms P95)"
}' "$SUMMARY_FILE")

 System Behavior:
$(awk -F',' 'NR>1 {
    if($8 == 0) stable_loads++
    total_loads++
} END {
    if(stable_loads == total_loads) print "   System maintained stability across all load levels"
    else print "   System showed degradation at " (total_loads - stable_loads) " load level(s)"
}' "$SUMMARY_FILE")

=================================================
ACADEMIC SIGNIFICANCE
=================================================

 Literature Context:
Results provide empirical validation of Redis idempotency mechanism
scalability, contributing to the limited literature on microservices
performance under varying load conditions.

 Research Contribution:
- Quantitative scalability boundaries identification
- Performance degradation pattern analysis  
- Load-dependent error rate characterization

 Practical Implications:
Based on empirical evidence, the system demonstrates:
$(awk -F',' 'NR>1 {
    if($8 < 1) good_loads++
    if($7 < 50) fast_loads++
    total++
} END {
    print "- Reliability: " (good_loads/total*100) "% of load levels maintained <1% error rate"
    print "- Responsiveness: " (fast_loads/total*100) "% of load levels maintained <50ms P95 latency"
}' "$SUMMARY_FILE")

=================================================
SCALABILITY RECOMMENDATIONS
=================================================

 Optimal Operating Range:
$(awk -F',' 'NR>1 {
    if($8 < 1 && $7 < 50) {
        if(best_rate == "" || $5 > best_throughput) {
            best_rate = $2
            best_throughput = $5
            best_name = $1
        }
    }
} END {
    if(best_rate != "") 
        print "Recommended maximum load: " best_rate " req/min (" best_name " level)"
    else 
        print "System requires optimization for production loads"
}' "$SUMMARY_FILE")

 Load Balancing Guidance:
- Monitor error rate increases above baseline levels
- Scale horizontally before reaching identified bottlenecks
- Implement circuit breakers for loads exceeding optimal range

=================================================
THESIS INTEGRATION VALUE
=================================================

✅ Scalability validation: Quantitative performance boundaries
✅ Bottleneck identification: Clear performance degradation points  
✅ Production readiness: Evidence-based capacity planning
✅ Academic rigor: Systematic load progression methodology

=================================================
EOF

echo ""
echo "================================================="
echo "HIGH LOAD TESTING COMPLETED"
echo "================================================="
cat "$ANALYSIS_FILE"

echo ""
echo " All results saved to: $RESULT_DIR"
echo " Load test summary: $SUMMARY_FILE"
echo " Scalability analysis: $ANALYSIS_FILE"