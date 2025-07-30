#!/bin/bash

# 基线性能测试脚本
# 用于建立系统性能基准

# ===================配置参数===================
BASE_URL="http://localhost:8080/api/orders"
INVENTORY_URL="http://localhost:8081/api/inventory"
TEST_DURATION=${1:-300}      # 测试持续时间（秒），默认5分钟
RATE_PER_MINUTE=${2:-100}    # 每分钟请求数，默认100
CONCURRENT_USERS=${3:-10}    # 并发用户数，默认10

# 计算参数
REQUESTS_PER_SECOND=$((RATE_PER_MINUTE / 60))
DELAY_BETWEEN_REQUESTS=$((60 / RATE_PER_MINUTE))

# 结果目录
RESULT_DIR="../results/baseline/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULT_DIR"

echo "======================================"
echo "基线性能测试开始"
echo "======================================"
echo "测试参数:"
echo "  持续时间: ${TEST_DURATION}秒"
echo "  请求频率: ${RATE_PER_MINUTE}/分钟"
echo "  并发用户: ${CONCURRENT_USERS}"
echo "  结果目录: $RESULT_DIR"
echo "======================================"

# ===================前置检查===================
echo "执行前置检查..."

# 检查服务健康状态
echo "检查订单服务..."
ORDER_HEALTH=$(curl -s "$BASE_URL/health" | jq -r '.data // "unhealthy"')
if [[ "$ORDER_HEALTH" != *"running"* ]]; then
    echo "❌ 订单服务不健康: $ORDER_HEALTH"
    exit 1
fi

echo "检查库存服务..."
INVENTORY_HEALTH=$(curl -s "$INVENTORY_URL/health" | jq -r '.message // "unhealthy"')
if [[ "$INVENTORY_HEALTH" != *"正常"* ]] && [[ "$INVENTORY_HEALTH" != *"running"* ]]; then
    echo "❌ 库存服务不健康: $INVENTORY_HEALTH"
    exit 1
fi

echo "检查Redis连接..."
REDIS_STATUS=$(curl -s "$BASE_URL/debug/redis-status" | jq -r '.data // "连接失败"')
if [[ "$REDIS_STATUS" != *"正常"* ]]; then
    echo "❌ Redis连接异常: $REDIS_STATUS"
    exit 1
fi

echo "✅ 所有服务健康检查通过"

# ===================清理环境===================
echo "清理测试环境..."
curl -s -X DELETE "$BASE_URL/debug/clear-idempotency" > /dev/null

# 记录初始库存状态
echo "记录初始状态..."
curl -s "$INVENTORY_URL" > "$RESULT_DIR/initial_inventory.json"

# ===================性能测试===================
echo "开始性能测试..."

# 测试数据文件
TEST_DATA_FILE="$RESULT_DIR/test_data.csv"
RESULTS_FILE="$RESULT_DIR/results.csv"
SUMMARY_FILE="$RESULT_DIR/summary.txt"

# 生成测试数据
echo "生成测试数据..."
echo "timestamp,idempotency_key,product_id,quantity,response_time,http_code,order_id,success" > "$RESULTS_FILE"

# 开始时间
START_TIME=$(date +%s)
END_TIME=$((START_TIME + TEST_DURATION))
REQUEST_COUNT=0
SUCCESS_COUNT=0
ERROR_COUNT=0
TOTAL_RESPONSE_TIME=0

echo "测试进行中..."
while [ $(date +%s) -lt $END_TIME ]; do
    REQUEST_COUNT=$((REQUEST_COUNT + 1))
    IDEMPOTENCY_KEY="baseline-test-$(date +%s%3N)-$REQUEST_COUNT"
    PRODUCT_ID=$((1 + RANDOM % 3))  # 随机选择产品1-3
    QUANTITY=$((1 + RANDOM % 5))    # 随机数量1-5
    
    # 发送请求并测量响应时间
    REQUEST_START=$(date +%s%3N)
    
    RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}\nTIME_TOTAL:%{time_total}" \
        -X POST "$BASE_URL" \
        -H "Content-Type: application/json" \
        -H "Idempotency-Key: $IDEMPOTENCY_KEY" \
        -d "{\"productId\": $PRODUCT_ID, \"quantity\": $QUANTITY}")
    
    REQUEST_END=$(date +%s%3N)
    
    # 解析响应
    HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d':' -f2)
    TIME_TOTAL=$(echo "$RESPONSE" | grep "TIME_TOTAL:" | cut -d':' -f2)
    ORDER_ID=$(echo "$RESPONSE" | grep -o '"orderId":"[^"]*"' | cut -d'"' -f4)
    
    # 转换响应时间为毫秒
    RESPONSE_TIME_MS=$(echo "$TIME_TOTAL * 1000" | bc -l 2>/dev/null || echo "0")
    
    # 判断成功/失败
    if [[ "$HTTP_CODE" == "201" ]] && [[ -n "$ORDER_ID" ]]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        SUCCESS="true"
    else
        ERROR_COUNT=$((ERROR_COUNT + 1))
        SUCCESS="false"
    fi
    
    # 累计响应时间
    TOTAL_RESPONSE_TIME=$(echo "$TOTAL_RESPONSE_TIME + $RESPONSE_TIME_MS" | bc -l 2>/dev/null || echo "$TOTAL_RESPONSE_TIME")
    
    # 记录结果
    echo "$(date '+%Y-%m-%d %H:%M:%S'),$IDEMPOTENCY_KEY,$PRODUCT_ID,$QUANTITY,$RESPONSE_TIME_MS,$HTTP_CODE,$ORDER_ID,$SUCCESS" >> "$RESULTS_FILE"
    
    # 显示进度
    if [ $((REQUEST_COUNT % 10)) -eq 0 ]; then
        ELAPSED=$(($(date +%s) - START_TIME))
        REMAINING=$((TEST_DURATION - ELAPSED))
        echo "进度: ${REQUEST_COUNT}请求, ${SUCCESS_COUNT}成功, ${ERROR_COUNT}失败, 剩余${REMAINING}秒"
    fi
    
    # 控制请求频率
    sleep $DELAY_BETWEEN_REQUESTS
done

# ===================结果分析===================
echo "分析测试结果..."

# 计算统计数据
ACTUAL_DURATION=$(($(date +%s) - START_TIME))
THROUGHPUT=$(echo "scale=2; $SUCCESS_COUNT / $ACTUAL_DURATION" | bc -l)
AVG_RESPONSE_TIME=$(echo "scale=2; $TOTAL_RESPONSE_TIME / $REQUEST_COUNT" | bc -l 2>/dev/null || echo "0")
SUCCESS_RATE=$(echo "scale=2; $SUCCESS_COUNT * 100 / $REQUEST_COUNT" | bc -l)
ERROR_RATE=$(echo "scale=2; $ERROR_COUNT * 100 / $REQUEST_COUNT" | bc -l)

# 记录最终库存状态
curl -s "$INVENTORY_URL" > "$RESULT_DIR/final_inventory.json"

# 生成汇总报告
cat > "$SUMMARY_FILE" << EOF
====================================
基线性能测试报告
====================================
测试配置:
  测试时间: $(date)
  持续时间: ${ACTUAL_DURATION}秒
  目标频率: ${RATE_PER_MINUTE}请求/分钟
  并发用户: ${CONCURRENT_USERS}

测试结果:
  总请求数: ${REQUEST_COUNT}
  成功请求: ${SUCCESS_COUNT}
  失败请求: ${ERROR_COUNT}
  成功率: ${SUCCESS_RATE}%
  错误率: ${ERROR_RATE}%

性能指标:
  吞吐量: ${THROUGHPUT} 请求/秒
  平均响应时间: ${AVG_RESPONSE_TIME} ms

文件位置:
  详细结果: $RESULTS_FILE
  初始库存: $RESULT_DIR/initial_inventory.json
  最终库存: $RESULT_DIR/final_inventory.json
====================================
EOF

# ===================输出结果===================
echo "======================================"
echo "基线性能测试完成"
echo "======================================"
cat "$SUMMARY_FILE"

# 检查是否需要生成图表
if command -v python3 &> /dev/null; then
    echo "生成性能图表..."
    python3 ../analysis/generate-charts.py "$RESULT_DIR"
fi

echo "所有结果已保存到: $RESULT_DIR"