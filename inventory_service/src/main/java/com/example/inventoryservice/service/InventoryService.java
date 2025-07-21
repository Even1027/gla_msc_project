package com.example.inventoryservice.service;

import java.util.HashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.Acknowledgment;
import org.springframework.kafka.support.KafkaHeaders;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.example.inventoryservice.dto.OrderEvent;
import com.example.inventoryservice.entity.Inventory;
import com.example.inventoryservice.repository.InventoryRepository;

@Service
@Transactional
public class InventoryService {
    
    private static final Logger logger = LoggerFactory.getLogger(InventoryService.class);
    
    @Autowired
    private InventoryRepository inventoryRepository;
    
    // 已处理的订单ID集合，防重复处理（简单的内存幂等性控制）
    private final Set<String> processedOrderIds = new HashSet<>();
    
    /**
     * Kafka消息监听器 - 处理订单事件
     * 这是库存服务与外部系统交互的主要入口
     * 
     * @param orderEvent 订单事件对象
     * @param partition Kafka分区信息
     * @param offset 消息偏移量
     * @param acknowledgment 手动确认对象
     */
    @KafkaListener(
        topics = "order-events",
        groupId = "inventory-service-group",
        containerFactory = "kafkaListenerContainerFactory"
    )
    public void handleOrderEvent(
            @Payload OrderEvent orderEvent,
            @Header(KafkaHeaders.RECEIVED_PARTITION) int partition,
            @Header(KafkaHeaders.OFFSET) long offset,
            Acknowledgment acknowledgment) {
        
        logger.info("接收到订单事件: partition={}, offset={}, orderEvent={}", 
                   partition, offset, orderEvent);
        
        try {
            // 处理订单事件
            processOrderEvent(orderEvent);
            
            // 手动确认消息处理成功
            acknowledgment.acknowledge();
            logger.info("订单事件处理完成: orderId={}", orderEvent.getOrderId());
            
        } catch (Exception e) {
            logger.error("订单事件处理失败: orderId={}, error={}", 
                        orderEvent.getOrderId(), e.getMessage(), e);
            
            // 这里可以实现重试机制或将消息发送到死信队列
            // 暂时不确认消息，让Kafka重新投递
        }
    }
    
    /**
     * 处理订单事件的核心业务逻辑
     * 
     * @param orderEvent 订单事件
     */
    private void processOrderEvent(OrderEvent orderEvent) {
        // 1. 幂等性检查 - 避免重复处理同一订单
        if (isOrderAlreadyProcessed(orderEvent.getOrderId())) {
            logger.info("订单已处理，跳过: orderId={}", orderEvent.getOrderId());
            return;
        }
        
        // 2. 参数验证
        validateOrderEvent(orderEvent);
        
        // 3. 根据订单状态执行不同的库存操作
        switch (orderEvent.getStatus()) {
            case "PENDING":
                // 新订单 - 预留库存
                handleNewOrder(orderEvent);
                break;
                
            case "CONFIRMED":
                // 订单确认 - 确认扣减库存
                handleOrderConfirmation(orderEvent);
                break;
                
            case "CANCELLED":
                // 订单取消 - 释放预留库存
                handleOrderCancellation(orderEvent);
                break;
                
            default:
                logger.warn("未知的订单状态: orderId={}, status={}", 
                           orderEvent.getOrderId(), orderEvent.getStatus());
        }
        
        // 4. 记录已处理的订单
        markOrderAsProcessed(orderEvent.getOrderId());
    }
    
    /**
     * 处理新订单 - 预留库存
     */
    private void handleNewOrder(OrderEvent orderEvent) {
        logger.info("处理新订单: orderId={}, productId={}, quantity={}", 
                   orderEvent.getOrderId(), orderEvent.getProductId(), orderEvent.getQuantity());
        
        // 1. 查找库存记录
        Optional<Inventory> optInventory = inventoryRepository.findByProductId(orderEvent.getProductId());
        
        if (optInventory.isEmpty()) {
            logger.error("商品不存在: productId={}, orderId={}", 
                        orderEvent.getProductId(), orderEvent.getOrderId());
            // 这里可以发送商品不存在的消息给订单服务
            return;
        }
        
        Inventory inventory = optInventory.get();
        
        // 2. 检查库存是否充足
        if (!inventory.hasEnoughStock(orderEvent.getQuantity())) {
            logger.error("库存不足: productId={}, 请求数量={}, 可用库存={}, orderId={}", 
                        orderEvent.getProductId(), orderEvent.getQuantity(), 
                        inventory.getAvailableQuantity(), orderEvent.getOrderId());
            // 这里可以发送库存不足的消息给订单服务
            return;
        }
        
        // 3. 预留库存
        try {
            inventory.reserveStock(orderEvent.getQuantity());
            inventoryRepository.save(inventory);
            
            logger.info("库存预留成功: productId={}, 预留数量={}, 剩余可用={}, orderId={}", 
                       orderEvent.getProductId(), orderEvent.getQuantity(), 
                       inventory.getAvailableQuantity(), orderEvent.getOrderId());
                       
        } catch (Exception e) {
            logger.error("库存预留失败: orderId={}, error={}", orderEvent.getOrderId(), e.getMessage());
            throw e; // 重新抛出异常，触发事务回滚
        }
    }
    
    /**
     * 处理订单确认 - 确认扣减库存
     */
    private void handleOrderConfirmation(OrderEvent orderEvent) {
        logger.info("处理订单确认: orderId={}, productId={}, quantity={}", 
                   orderEvent.getOrderId(), orderEvent.getProductId(), orderEvent.getQuantity());
        
        Optional<Inventory> optInventory = inventoryRepository.findByProductId(orderEvent.getProductId());
        
        if (optInventory.isEmpty()) {
            logger.error("商品不存在: productId={}, orderId={}", 
                        orderEvent.getProductId(), orderEvent.getOrderId());
            return;
        }
        
        Inventory inventory = optInventory.get();
        
        try {
            // 确认扣减库存（从预留转为实际扣减）
            inventory.confirmReduction(orderEvent.getQuantity());
            inventoryRepository.save(inventory);
            
            logger.info("库存扣减确认成功: productId={}, 扣减数量={}, 剩余库存={}, orderId={}", 
                       orderEvent.getProductId(), orderEvent.getQuantity(), 
                       inventory.getQuantity(), orderEvent.getOrderId());
                       
        } catch (Exception e) {
            logger.error("库存扣减确认失败: orderId={}, error={}", orderEvent.getOrderId(), e.getMessage());
            throw e;
        }
    }
    
    /**
     * 处理订单取消 - 释放预留库存
     */
    private void handleOrderCancellation(OrderEvent orderEvent) {
        logger.info("处理订单取消: orderId={}, productId={}, quantity={}", 
                   orderEvent.getOrderId(), orderEvent.getProductId(), orderEvent.getQuantity());
        
        Optional<Inventory> optInventory = inventoryRepository.findByProductId(orderEvent.getProductId());
        
        if (optInventory.isEmpty()) {
            logger.warn("商品不存在，但订单取消操作继续: productId={}, orderId={}", 
                       orderEvent.getProductId(), orderEvent.getOrderId());
            return;
        }
        
        Inventory inventory = optInventory.get();
        
        try {
            // 释放预留库存
            inventory.cancelReservation(orderEvent.getQuantity());
            inventoryRepository.save(inventory);
            
            logger.info("预留库存释放成功: productId={}, 释放数量={}, 可用库存={}, orderId={}", 
                       orderEvent.getProductId(), orderEvent.getQuantity(), 
                       inventory.getAvailableQuantity(), orderEvent.getOrderId());
                       
        } catch (Exception e) {
            logger.error("预留库存释放失败: orderId={}, error={}", orderEvent.getOrderId(), e.getMessage());
            throw e;
        }
    }
    
    /**
     * 验证订单事件参数
     */
    private void validateOrderEvent(OrderEvent orderEvent) {
        if (orderEvent.getOrderId() == null || orderEvent.getOrderId().trim().isEmpty()) {
            throw new IllegalArgumentException("订单ID不能为空");
        }
        
        if (orderEvent.getProductId() == null || orderEvent.getProductId() <= 0) {
            throw new IllegalArgumentException("商品ID无效: " + orderEvent.getProductId());
        }
        
        if (orderEvent.getQuantity() == null || orderEvent.getQuantity() <= 0) {
            throw new IllegalArgumentException("订单数量无效: " + orderEvent.getQuantity());
        }
        
        if (orderEvent.getStatus() == null || orderEvent.getStatus().trim().isEmpty()) {
            throw new IllegalArgumentException("订单状态不能为空");
        }
    }
    
    /**
     * 检查订单是否已经处理过（简单的内存幂等性控制）
     */
    private boolean isOrderAlreadyProcessed(String orderId) {
        return processedOrderIds.contains(orderId);
    }
    
    /**
     * 标记订单为已处理
     */
    private void markOrderAsProcessed(String orderId) {
        processedOrderIds.add(orderId);
        
        // 简单的内存清理策略：当集合过大时清理（生产环境应使用Redis等外部存储）
        if (processedOrderIds.size() > 10000) {
            processedOrderIds.clear();
            logger.info("清理已处理订单ID集合");
        }
    }
    
    // ========== 对外提供的查询接口 ==========
    
    /**
     * 查询商品库存信息
     */
    public Optional<Inventory> getInventoryByProductId(Long productId) {
        logger.debug("查询商品库存: productId={}", productId);
        return inventoryRepository.findByProductId(productId);
    }
    
    /**
     * 查询库存不足的商品列表
     */
    public List<Inventory> getLowStockInventories(Integer threshold) {
        logger.debug("查询库存不足商品: threshold={}", threshold);
        return inventoryRepository.findLowStockInventories(threshold);
    }
    
    /**
     * 获取所有库存信息
     */
    public List<Inventory> getAllInventories() {
        logger.debug("查询所有库存信息");
        return inventoryRepository.findAll();
    }
    
    /**
     * 手动调整库存（管理功能）
     * 用于库存盘点、补货等场景
     */
    public void adjustInventory(Long productId, Integer newQuantity) {
        logger.info("手动调整库存: productId={}, newQuantity={}", productId, newQuantity);
        
        Optional<Inventory> optInventory = inventoryRepository.findByProductId(productId);
        
        if (optInventory.isEmpty()) {
            logger.error("商品不存在，无法调整库存: productId={}", productId);
            throw new IllegalArgumentException("商品不存在: " + productId);
        }
        
        Inventory inventory = optInventory.get();
        Integer oldQuantity = inventory.getQuantity();
        
        inventory.setQuantity(newQuantity);
        inventoryRepository.save(inventory);
        
        logger.info("库存调整成功: productId={}, 原库存={}, 新库存={}", 
                   productId, oldQuantity, newQuantity);
    }
}