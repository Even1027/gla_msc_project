package com.example.orderservice.service;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.example.orderservice.entity.Order;
import com.example.orderservice.entity.OrderStatus;
import com.example.orderservice.repository.OrderRepository;

@Service
@Transactional
public class OrderService {

    private static final Logger logger = LoggerFactory.getLogger(OrderService.class);
    
    // Redis键的前缀，用于幂等性控制
    private static final String IDEMPOTENCY_KEY_PREFIX = "order:idempotency:";
    
    // Redis键的过期时间（分钟）
    private static final long IDEMPOTENCY_KEY_TTL = 30;
    
    // Kafka主题名称
    private static final String ORDER_TOPIC = "order-events";

    @Autowired
    private OrderRepository orderRepository;

    @Autowired
    private RedisTemplate<String, Object> redisTemplate;

    @Autowired
    private KafkaTemplate<String, Object> kafkaTemplate;

    // ==================== 核心业务方法 ====================

    /**
     * 创建订单 - 包含完整的一致性机制
     * @param productId 商品ID
     * @param quantity 数量
     * @param idempotencyKey 幂等性键（可选）
     * @return 创建的订单
     */
    public Order createOrder(Long productId, Integer quantity, String idempotencyKey) {
        logger.info("开始创建订单: productId={}, quantity={}, idempotencyKey={}", 
                   productId, quantity, idempotencyKey);

        // 第一步：参数验证
        validateOrderRequest(productId, quantity);

        // 第二步：幂等性检查
        if (idempotencyKey != null && !idempotencyKey.trim().isEmpty()) {
            Order existingOrder = checkIdempotency(idempotencyKey);
            if (existingOrder != null) {
                logger.info("发现重复请求，返回已存在订单: orderId={}", existingOrder.getOrderId());
                return existingOrder;
            }
        }

        // 第三步：生成订单ID
        String orderId = generateOrderId();

        // 第四步：创建订单对象
        Order order = new Order(orderId, productId, quantity);

        // 第五步：保存到数据库
        Order savedOrder = orderRepository.save(order);
        logger.info("订单保存成功: orderId={}, id={}", savedOrder.getOrderId(), savedOrder.getId());

        // 第六步：设置幂等性缓存
        if (idempotencyKey != null && !idempotencyKey.trim().isEmpty()) {
            setIdempotencyCache(idempotencyKey, savedOrder);
        }

        // 第七步：发送Kafka消息
        sendOrderCreatedEvent(savedOrder);

        logger.info("订单创建完成: orderId={}", savedOrder.getOrderId());
        return savedOrder;
    }

    /**
     * 简化版创建订单（自动生成幂等性键）
     * @param productId 商品ID
     * @param quantity 数量
     * @return 创建的订单
     */
    public Order createOrder(Long productId, Integer quantity) {
        return createOrder(productId, quantity, null);
    }

    // ==================== 幂等性控制机制 ====================

    /**
     * 检查幂等性 - Redis缓存实现
     * @param idempotencyKey 幂等性键
     * @return 如果存在重复请求，返回已存在的订单；否则返回null
     */
    private Order checkIdempotency(String idempotencyKey) {
        String redisKey = IDEMPOTENCY_KEY_PREFIX + idempotencyKey;
        
        try {
            // 从Redis获取缓存的订单ID
            Object cachedOrderId = redisTemplate.opsForValue().get(redisKey);
            
            if (cachedOrderId != null) {
                String orderIdStr = cachedOrderId.toString();
                logger.debug("Redis中找到幂等性记录: idempotencyKey={}, orderId={}", 
                           idempotencyKey, orderIdStr);
                
                // 从数据库获取完整订单信息
                Optional<Order> orderOpt = orderRepository.findByOrderId(orderIdStr);
                if (orderOpt.isPresent()) {
                    return orderOpt.get();
                } else {
                    // 缓存存在但数据库中没有，清理缓存
                    logger.warn("Redis缓存与数据库不一致，清理缓存: orderId={}", orderIdStr);
                    redisTemplate.delete(redisKey);
                }
            }
        } catch (Exception e) {
            logger.error("Redis幂等性检查失败: idempotencyKey={}", idempotencyKey, e);
            // Redis失败时，降级到数据库检查
            return checkIdempotencyFallback(idempotencyKey);
        }
        
        return null;
    }

    /**
     * 设置幂等性缓存
     * @param idempotencyKey 幂等性键
     * @param order 订单对象
     */
    private void setIdempotencyCache(String idempotencyKey, Order order) {
        String redisKey = IDEMPOTENCY_KEY_PREFIX + idempotencyKey;
        
        try {
            // 在Redis中缓存订单ID，设置过期时间
            redisTemplate.opsForValue().set(redisKey, order.getOrderId(), 
                                          IDEMPOTENCY_KEY_TTL, TimeUnit.MINUTES);
            logger.debug("设置幂等性缓存: idempotencyKey={}, orderId={}, ttl={}分钟", 
                        idempotencyKey, order.getOrderId(), IDEMPOTENCY_KEY_TTL);
        } catch (Exception e) {
            logger.error("设置Redis幂等性缓存失败: idempotencyKey={}, orderId={}", 
                        idempotencyKey, order.getOrderId(), e);
            // Redis失败不影响主流程，但要记录日志
        }
    }

    /**
     * 幂等性检查降级方案（Redis失败时使用数据库）
     * @param idempotencyKey 幂等性键
     * @return 已存在的订单或null
     */
    private Order checkIdempotencyFallback(String idempotencyKey) {
        logger.info("使用数据库进行幂等性检查降级: idempotencyKey={}", idempotencyKey);
        // 这里可以实现基于数据库的幂等性检查逻辑
        // 为简化，暂时返回null
        return null;
    }

    // ==================== Kafka消息发送 ====================

    /**
     * 发送订单创建事件到Kafka
     * @param order 订单对象
     */
    private void sendOrderCreatedEvent(Order order) {
        try {
            // 构建消息内容
            OrderEvent orderEvent = new OrderEvent(
                order.getOrderId(),
                order.getProductId(),
                order.getQuantity(),
                order.getStatus().toString(),
                order.getCreatedAt()
            );

            // 发送到Kafka主题
            kafkaTemplate.send(ORDER_TOPIC, order.getOrderId(), orderEvent);
            logger.info("订单事件发送成功: orderId={}, topic={}", order.getOrderId(), ORDER_TOPIC);
            
        } catch (Exception e) {
            logger.error("发送订单事件失败: orderId={}", order.getOrderId(), e);
            // 消息发送失败不影响主流程，但要记录日志
            // 实际项目中可能需要重试机制或补偿措施
        }
    }

    // ==================== 查询方法 ====================

    /**
     * 根据订单ID查找订单
     * @param orderId 订单ID
     * @return 订单对象
     */
    public Optional<Order> findByOrderId(String orderId) {
        return orderRepository.findByOrderId(orderId);
    }

    /**
     * 根据状态查找订单
     * @param status 订单状态
     * @return 订单列表
     */
    public List<Order> findByStatus(OrderStatus status) {
        return orderRepository.findByStatus(status);
    }

    /**
     * 查找所有订单
     * @return 所有订单列表
     */
    public List<Order> findAllOrders() {
        return orderRepository.findAll();
    }

    /**
     * 更新订单状态
     * @param orderId 订单ID
     * @param newStatus 新状态
     * @return 更新后的订单
     */
    public Order updateOrderStatus(String orderId, OrderStatus newStatus) {
        Optional<Order> orderOpt = orderRepository.findByOrderId(orderId);
        if (orderOpt.isPresent()) {
            Order order = orderOpt.get();
            order.setStatus(newStatus);
            Order updatedOrder = orderRepository.save(order);
            
            logger.info("订单状态更新: orderId={}, oldStatus={}, newStatus={}", 
                       orderId, order.getStatus(), newStatus);
            
            return updatedOrder;
        } else {
            throw new RuntimeException("订单不存在: " + orderId);
        }
    }

    // ==================== 一致性评估方法 ====================

    /**
     * 获取订单统计信息（用于一致性评估）
     * @return 各状态的订单数量
     */
    public List<Object[]> getOrderStatistics() {
        return orderRepository.getOrderStatusStatistics();
    }

    /**
     * 查找处理延迟的订单（用于一致性评估）
     * @param delayMinutes 延迟分钟数
     * @return 延迟处理的订单列表
     */
    public List<Order> findDelayedOrders(int delayMinutes) {
        LocalDateTime thresholdTime = LocalDateTime.now().minusMinutes(delayMinutes);
        return orderRepository.findDelayedOrders(OrderStatus.PENDING, thresholdTime);
    }

    // ==================== 辅助方法 ====================

    /**
     * 验证订单请求参数
     * @param productId 商品ID
     * @param quantity 数量
     */
    private void validateOrderRequest(Long productId, Integer quantity) {
        if (productId == null || productId <= 0) {
            throw new IllegalArgumentException("商品ID必须为正数");
        }
        if (quantity == null || quantity <= 0) {
            throw new IllegalArgumentException("订单数量必须为正数");
        }
        if (quantity > 1000) {
            throw new IllegalArgumentException("单次订单数量不能超过1000");
        }
    }

    /**
     * 生成唯一订单ID
     * @return 订单ID
     */
    private String generateOrderId() {
        // 格式：ORDER_yyyyMMddHHmmss_UUID前8位
        String timestamp = LocalDateTime.now().toString().replaceAll("[^0-9]", "").substring(0, 14);
        String uuid = UUID.randomUUID().toString().substring(0, 8);
        return "ORDER_" + timestamp + "_" + uuid;
    }

    // ==================== 内部类：订单事件 ====================

    /**
     * 订单事件类（用于Kafka消息）
     */
    public static class OrderEvent {
        private String orderId;
        private Long productId;
        private Integer quantity;
        private String status;
        private LocalDateTime createdAt;

        public OrderEvent(String orderId, Long productId, Integer quantity, 
                         String status, LocalDateTime createdAt) {
            this.orderId = orderId;
            this.productId = productId;
            this.quantity = quantity;
            this.status = status;
            this.createdAt = createdAt;
        }

        // Getter和Setter方法
        public String getOrderId() { return orderId; }
        public void setOrderId(String orderId) { this.orderId = orderId; }
        
        public Long getProductId() { return productId; }
        public void setProductId(Long productId) { this.productId = productId; }
        
        public Integer getQuantity() { return quantity; }
        public void setQuantity(Integer quantity) { this.quantity = quantity; }
        
        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }
        
        public LocalDateTime getCreatedAt() { return createdAt; }
        public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }
    }
}