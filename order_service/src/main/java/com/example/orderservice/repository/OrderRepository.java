package com.example.orderservice.repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import com.example.orderservice.entity.Order;
import com.example.orderservice.entity.OrderStatus;

@Repository
public interface OrderRepository extends JpaRepository<Order, Long> {
    
    // ==================== 幂等性相关查询 ====================
    
    /**
     * 根据订单ID查找订单（幂等性检查）
     * @param orderId 业务订单ID
     * @return 订单对象（如果存在）
     */
    Optional<Order> findByOrderId(String orderId);
    
    /**
     * 检查订单ID是否已存在（幂等性检查）
     * @param orderId 业务订单ID
     * @return true如果订单已存在
     */
    boolean existsByOrderId(String orderId);
    
    // ==================== 业务查询 ====================
    
    /**
     * 根据状态查找订单
     * @param status 订单状态
     * @return 指定状态的订单列表
     */
    List<Order> findByStatus(OrderStatus status);
    
    /**
     * 根据商品ID查找订单
     * @param productId 商品ID
     * @return 该商品的所有订单
     */
    List<Order> findByProductId(Long productId);
    
    /**
     * 查找指定时间范围内的订单
     * @param startTime 开始时间
     * @param endTime 结束时间
     * @return 时间范围内的订单列表
     */
    List<Order> findByCreatedAtBetween(LocalDateTime startTime, LocalDateTime endTime);
    
    // ==================== 一致性评估相关查询 ====================
    
    /**
     * 查找待处理的订单（用于一致性测试）
     * @return 所有PENDING状态的订单
     */
    List<Order> findByStatusOrderByCreatedAtAsc(OrderStatus status);
    
    /**
     * 查找特定时间后创建的订单（用于性能测试）
     * @param createdAfter 时间点
     * @return 该时间点后创建的订单
     */
    List<Order> findByCreatedAtAfter(LocalDateTime createdAfter);
    
    /**
     * 统计各个状态的订单数量
     * @param status 订单状态
     * @return 该状态的订单数量
     */
    long countByStatus(OrderStatus status);
    
    // ==================== 自定义查询 ====================
    
    /**
     * 查找处理时间超过指定分钟数的订单
     * 用于检测一致性延迟问题
     */
    @Query("SELECT o FROM Order o WHERE o.status = :status " +
           "AND o.createdAt < :thresholdTime")
    List<Order> findDelayedOrders(@Param("status") OrderStatus status, 
                                  @Param("thresholdTime") LocalDateTime thresholdTime);
    
    /**
     * 获取订单处理的统计信息
     * 返回每个状态的订单数量
     */
    @Query("SELECT o.status, COUNT(o) FROM Order o GROUP BY o.status")
    List<Object[]> getOrderStatusStatistics();
    
    /**
     * 查找可能的重复订单（相同商品、数量、时间窗口内）
     * 用于检测幂等性问题
     */
    @Query("SELECT o FROM Order o WHERE o.productId = :productId " +
           "AND o.quantity = :quantity " +
           "AND o.createdAt BETWEEN :startTime AND :endTime " +
           "AND o.orderId != :excludeOrderId")
    List<Order> findPotentialDuplicates(@Param("productId") Long productId,
                                       @Param("quantity") Integer quantity,
                                       @Param("startTime") LocalDateTime startTime,
                                       @Param("endTime") LocalDateTime endTime,
                                       @Param("excludeOrderId") String excludeOrderId);
}