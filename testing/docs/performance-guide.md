# 性能测试执行指南

## 📋 测试脚本位置

```
testing/
├── performance/
│   ├── scripts/
│   │   ├── baseline-test.sh      # 基线性能测试
│   │   ├── concurrent-test.sh    # 并发性能测试
│   │   ├── load-test.sh          # 负载测试
│   │   └── stress-test.sh        # 压力测试
│   └── results/                  # 测试结果存储
```

## 🚀 执行步骤

### 1. 进入测试目录
```bash
cd testing/performance/scripts
```

### 2. 给脚本执行权限
```bash
chmod +x *.sh
```

### 3. 执行基线测试
```bash
# 基本执行（默认参数：5分钟，100请求/分钟）
./baseline-test.sh

# 自定义参数（持续时间300秒，500请求/分钟，20并发用户）
./baseline-test.sh 300 500 20
```

### 4. 执行并发测试
```bash
# 测试相同幂等性键的并发处理
./concurrent-test.sh 10 5 same_key

# 测试不同幂等性键的并发处理
./concurrent-test.sh 20 10 different_keys

# 混合测试
./concurrent-test.sh 15 8 mixed
```

## 📊 结果分析

### 关键指标
- **吞吐量**：每秒成功处理的请求数
- **响应时间**：平均、最小、最大响应时间
- **成功率**：成功请求占总请求的百分比
- **幂等性有效性**：相同键的重复处理率

### 结果文件
- `results.csv`：详细的请求-响应数据
- `summary.txt`：汇总报告
- `idempotency_analysis.txt`：幂等性分析

## 🎯 性能基准目标

基于你的研究文档，预期目标：

| 配置类型 | 吞吐量 | P99延迟 | 错误率 |
|---------|--------|---------|--------|
| 强一致性 | 100-300/秒 | <500ms | <0.1% |
| 平衡配置 | 500-1000/秒 | <200ms | <1% |
| 性能优化 | 1000+/秒 | <50ms | <5% |

## 🔧 故障排除

### 常见问题
1. **权限错误**：执行 `chmod +x *.sh`
2. **依赖缺失**：安装 `bc`、`jq`、`curl`
3. **服务不可用**：检查服务健康状态
4. **Redis连接失败**：验证Redis服务状态

### 依赖安装
```bash
# Ubuntu/Debian
sudo apt-get install bc jq curl

# CentOS/RHEL
sudo yum install bc jq curl

# macOS
brew install bc jq curl
```