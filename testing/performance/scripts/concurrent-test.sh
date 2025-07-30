#!/bin/bash

# 增强并发测试脚本
# 测试系统在高并发情况下的表现

# ===================配置参数===================
BASE_URL="http://localhost:8080/api/orders"
CONCURRENT_USERS=${1:-20}      # 并发用户数，默认20
REQUESTS_PER_USER=${2:-10}     # 每用户请求数，默认10
TEST_TYPE=${3:-"mixed"}        # 测试类型: same_key, different_keys, mixed

# 结果目录
RESULT_DIR="../results/concurrent/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULT_DIR"

echo "======================================"
echo "并发性能测试"
echo "======================================"
echo "测试参数:"
echo "  并发用户数: $CONCURRENT_USERS"
echo "  每用户请求: $REQUESTS_PER_USER"
echo "  测试类型: $TEST_TYPE"
echo "  总请求数: $((CONCURRENT_USERS * REQUESTS_PER_USER))"
echo "  结果目录: $RESULT_DIR"
echo "======================================"

# 清理环境
echo "清理测试环境..."
curl -s -X DELETE "$BASE_URL/debug/clear-idempotency" > /dev/null

# 结果文件
RESULTS_FILE="$RESULT_DIR/concurrent_results.csv"
SUMMARY_FILE="$RESULT_DIR/concurrent_summary.txt"

# CSV头
echo "user_id,request_id,idempotency_key,start_time,end_time,response_time_ms,http_code,order_id,success,thread_pid" > "$RESULTS_FILE"

# ===================并发测试函数===================
run_user_requests() {
    local user_id=$1
    local user_results_file="$RESULT_DIR/user_${user_id}_results.csv"
    
    for ((req=1; req<=REQUESTS_PER_USER; req++)); do
        # 根据测试类型生成幂等性键
        case $TEST_TYPE in
            "same_key")
                IDEMPOTENCY_KEY="shared-key-for-all"
                ;;
            "different_keys")
                IDEMPOTENCY_KEY="user-${user_id}-req-${req}-$(date +%s%3N)"
                ;;
            "mixed")
                if [ $((req % 3)) -eq 0 ]; then
                    IDEMPOTENCY_KEY="shared-key-${user_id}"  # 每3个请求有一个重复
                else
                    IDEMPOTENCY_KEY="unique-${user_id}-${req}-$(date +%s%3N)"
                fi
                ;;
        esac
        
        PRODUCT_ID=$((1 + RANDOM % 3))
        QUANTITY=$((1 + RANDOM % 5))
        
        # 记录开始时间
        START_TIME=$(date +%s%3N)
        
        # 发送请求
        RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}\nTIME_TOTAL:%{time_total}" \
            -X POST "$BASE_URL" \
            -H "Content-Type: application/json" \
            -H "Idempotency-Key: $IDEMPOTENCY_KEY" \
            -d "{\"productId\": $PRODUCT_ID, \"quantity\": $QUANTITY}")
        
        # 记录结束时间
        END_TIME=$(date +%s%3N)
        
        # 解析响应
        HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d':' -f2)
        TIME_TOTAL=$(echo "$RESPONSE" | grep "TIME_TOTAL:" | cut -d':' -f2)
        ORDER_ID=$(echo "$RESPONSE" | grep -o '"orderId":"[^"]*"' | cut -d'"' -f4)
        
        # 计算响应时间
        RESPONSE_TIME_MS=$(echo "$TIME_TOTAL * 1000" | bc -l 2>/dev/null || echo "0")
        
        # 判断成功
        if [[ "$HTTP_CODE" == "201" ]] && [[ -n "$ORDER_ID" ]]; then
            SUCCESS="true"
        else
            SUCCESS="false"
        fi
        
        # 记录结果
        echo "$user_id,$req,$IDEMPOTENCY_KEY,$START_TIME,$END_TIME,$RESPONSE_TIME_MS,$HTTP_CODE,$ORDER_ID,$SUCCESS,$$" >> "$user_results_file"
        
        # 随机延迟，模拟真实用户行为
        sleep 0.$((RANDOM % 5))
    done
    
    echo "用户 $user_id 完成所有请求"
}

# ===================启动并发测试===================
echo "启动 $CONCURRENT_USERS 个并发用户..."

START_TIME=$(date +%s)

# 启动所有并发用户
for ((user=1; user<=CONCURRENT_USERS; user++)); do
    run_user_requests $user &
    echo "用户 $user 已启动 (PID: $!)"
done

# 等待所有用户完成
echo "等待所有用户完成..."
wait

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

# ===================合并结果===================
echo "合并测试结果..."

# 合并所有用户的结果
for user_file in "$RESULT_DIR"/user_*_results.csv; do
    if [ -f "$user_file" ]; then
        cat "$user_file" >> "$RESULTS_FILE"
        rm "$user_file"  # 清理临时文件
    fi
done

# ===================分析结果===================
echo "分析测试结果..."

# 计算统计数据
TOTAL_REQUESTS=$(tail -n +2 "$RESULTS_FILE" | wc -l)
SUCCESS_REQUESTS=$(tail -n +2 "$RESULTS_FILE" | grep ",true," | wc -l)
FAILED_REQUESTS=$(tail -n +2 "$RESULTS_FILE" | grep ",false," | wc -l)

SUCCESS_RATE=$(echo "scale=2; $SUCCESS_REQUESTS * 100 / $TOTAL_REQUESTS" | bc -l)
ERROR_RATE=$(echo "scale=2; $FAILED_REQUESTS * 100 / $TOTAL_REQUESTS" | bc -l)
THROUGHPUT=$(echo "scale=2; $SUCCESS_REQUESTS / $TOTAL_DURATION" | bc -l)

# 响应时间统计
AVG_RESPONSE_TIME=$(tail -n +2 "$RESULTS_FILE" | cut -d',' -f6 | awk '{sum+=$1; count++} END {print sum/count}')
MIN_RESPONSE_TIME=$(tail -n +2 "$RESULTS_FILE" | cut -d',' -f6 | sort -n | head -1)
MAX_RESPONSE_TIME=$(tail -n +2 "$RESULTS_FILE" | cut -d',' -f6 | sort -n | tail -1)

# 幂等性分析
if [[ "$TEST_TYPE" == "same_key" ]] || [[ "$TEST_TYPE" == "mixed" ]]; then
    echo "分析幂等性表现..."
    
    # 统计每个幂等性键对应的唯一订单数
    IDEMPOTENCY_ANALYSIS="$RESULT_DIR/idempotency_analysis.txt"
    echo "幂等性键分析:" > "$IDEMPOTENCY_ANALYSIS"
    echo "格式: 幂等性键 -> 唯一订单数 (总请求数)" >> "$IDEMPOTENCY_ANALYSIS"
    echo "=================================" >> "$IDEMPOTENCY_ANALYSIS"
    
    tail -n +2 "$RESULTS_FILE" | cut -d',' -f3,8 | sort | uniq -c | \
    awk '{
        key=$2; 
        order=$3; 
        count=$1; 
        keys[key]++; 
        if(orders[key]=="") orders[key]=order; 
        else if(orders[key]!=order) orders[key]=orders[key]","order
    } 
    END {
        for(k in keys) {
            split(orders[k], unique_orders, ",");
            unique_count=0;
            for(i in unique_orders) if(unique_orders[i]!="") unique_count++;
            print k " -> " unique_count " (" keys[k] ")"
        }
    }' >> "$IDEMPOTENCY_ANALYSIS"
fi

# ===================生成报告===================
cat > "$SUMMARY_FILE" << EOF
====================================
并发性能测试报告
====================================
测试配置:
  测试时间: $(date)
  并发用户数: $CONCURRENT_USERS
  每用户请求数: $REQUESTS_PER_USER
  测试类型: $TEST_TYPE
  总持续时间: ${TOTAL_DURATION}秒

测试结果:
  总请求数: $TOTAL_REQUESTS
  成功请求: $SUCCESS_REQUESTS
  失败请求: $FAILED_REQUESTS
  成功率: $SUCCESS_RATE%
  错误率: $ERROR_RATE%

性能指标:
  吞吐量: $THROUGHPUT 请求/秒
  平均响应时间: $AVG_RESPONSE_TIME ms
  最小响应时间: $MIN_RESPONSE_TIME ms
  最大响应时间: $MAX_RESPONSE_TIME ms

文件位置:
  详细结果: $RESULTS_FILE
  幂等性分析: $IDEMPOTENCY_ANALYSIS
====================================
EOF

# ===================输出结果===================
echo "======================================"
echo "并发性能测试完成"
echo "======================================"
cat "$SUMMARY_FILE"

if [ -f "$IDEMPOTENCY_ANALYSIS" ]; then
    echo
    echo "幂等性分析结果:"
    cat "$IDEMPOTENCY_ANALYSIS"
fi

echo
echo "所有结果已保存到: $RESULT_DIR"