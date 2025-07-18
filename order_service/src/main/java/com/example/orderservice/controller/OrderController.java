package com.example.orderservice.controller;

import java.util.List;
import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.example.orderservice.entity.Order;
import com.example.orderservice.entity.OrderStatus;
import com.example.orderservice.service.OrderService;

@RestController
@RequestMapping("/api/orders")
@CrossOrigin(origins = "*") // 允许跨域访问（开发环境）
public class OrderController {

    private static final Logger logger = LoggerFactory.getLogger(OrderController.class);

    @Autowired
    private OrderService orderService;

    // ==================== 核心API接口 ====================

    /**
     * 创建订单接口
     * POST /api/orders
     * 
     * @param request 订单创建请求
     * @return 创建的订单信息
     */
    @PostMapping
    public ResponseEntity<ApiResponse<Order>> createOrder(@RequestBody CreateOrderRequest request) {
        logger.info("收到创建订单请求: productId={}, quantity={}, idempotencyKey={}",
                request.getProductId(), request.getQuantity(), request.getIdempotencyKey());

        try {
            // 调用Service层创建订单
            Order order = orderService.createOrder(
                    request.getProductId(),
                    request.getQuantity(),
                    request.getIdempotencyKey());

            logger.info("订单创建成功: orderId={}", order.getOrderId());

            return ResponseEntity.status(HttpStatus.CREATED)
                    .body(ApiResponse.success("订单创建成功", order));

        } catch (IllegalArgumentException e) {
            logger.warn("订单创建失败 - 参数错误: {}", e.getMessage());
            return ResponseEntity.badRequest()
                    .body(ApiResponse.error("参数错误: " + e.getMessage()));

        } catch (Exception e) {
            logger.error("订单创建失败 - 系统错误", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(ApiResponse.error("系统错误，请稍后重试"));
        }
    }

    /**
     * 简化版创建订单接口（用于快速测试）
     * POST /api/orders/simple
     * 
     * @param productId 商品ID
     * @param quantity  数量
     * @return 创建的订单信息
     */
    @RequestMapping(value = "/simple", method = { RequestMethod.GET, RequestMethod.POST })
    public ResponseEntity<ApiResponse<Order>> createSimpleOrder(
            @RequestParam Long productId,
            @RequestParam Integer quantity) {

        logger.info("收到简化创建订单请求: productId={}, quantity={}", productId, quantity);

        try {
            Order order = orderService.createOrder(productId, quantity);

            return ResponseEntity.status(HttpStatus.CREATED)
                    .body(ApiResponse.success("订单创建成功", order));

        } catch (Exception e) {
            logger.error("简化订单创建失败", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(ApiResponse.error("创建失败: " + e.getMessage()));
        }
    }

    // ==================== 查询接口 ====================

    /**
     * 根据订单ID查询订单
     * GET /api/orders/{orderId}
     * 
     * @param orderId 订单ID
     * @return 订单信息
     */
    @GetMapping("/{orderId}")
    public ResponseEntity<ApiResponse<Order>> getOrderById(@PathVariable String orderId) {
        logger.info("查询订单: orderId={}", orderId);

        Optional<Order> orderOpt = orderService.findByOrderId(orderId);

        if (orderOpt.isPresent()) {
            return ResponseEntity.ok(ApiResponse.success("查询成功", orderOpt.get()));
        } else {
            return ResponseEntity.notFound().build();
        }
    }

    /**
     * 查询所有订单
     * GET /api/orders
     * 
     * @return 所有订单列表
     */
    @GetMapping
    public ResponseEntity<ApiResponse<List<Order>>> getAllOrders() {
        logger.info("查询所有订单");

        try {
            List<Order> orders = orderService.findAllOrders();
            return ResponseEntity.ok(ApiResponse.success("查询成功", orders));

        } catch (Exception e) {
            logger.error("查询所有订单失败", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(ApiResponse.error("查询失败"));
        }
    }

    /**
     * 根据状态查询订单
     * GET /api/orders/status/{status}
     * 
     * @param status 订单状态
     * @return 指定状态的订单列表
     */
    @GetMapping("/status/{status}")
    public ResponseEntity<ApiResponse<List<Order>>> getOrdersByStatus(@PathVariable OrderStatus status) {
        logger.info("根据状态查询订单: status={}", status);

        try {
            List<Order> orders = orderService.findByStatus(status);
            return ResponseEntity.ok(ApiResponse.success("查询成功", orders));

        } catch (Exception e) {
            logger.error("根据状态查询订单失败: status={}", status, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(ApiResponse.error("查询失败"));
        }
    }

    // ==================== 管理接口 ====================

    /**
     * 更新订单状态
     * PUT /api/orders/{orderId}/status
     * 
     * @param orderId 订单ID
     * @param request 状态更新请求
     * @return 更新后的订单信息
     */
    @PutMapping("/{orderId}/status")
    public ResponseEntity<ApiResponse<Order>> updateOrderStatus(
            @PathVariable String orderId,
            @RequestBody UpdateStatusRequest request) {

        logger.info("更新订单状态: orderId={}, newStatus={}", orderId, request.getStatus());

        try {
            Order updatedOrder = orderService.updateOrderStatus(orderId, request.getStatus());
            return ResponseEntity.ok(ApiResponse.success("状态更新成功", updatedOrder));

        } catch (RuntimeException e) {
            logger.warn("订单状态更新失败: orderId={}, error={}", orderId, e.getMessage());
            return ResponseEntity.badRequest()
                    .body(ApiResponse.error(e.getMessage()));

        } catch (Exception e) {
            logger.error("订单状态更新失败: orderId={}", orderId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(ApiResponse.error("更新失败"));
        }
    }

    // ==================== 一致性评估接口 ====================

    /**
     * 获取订单统计信息（用于一致性评估）
     * GET /api/orders/statistics
     * 
     * @return 订单统计信息
     */
    @GetMapping("/statistics")
    public ResponseEntity<ApiResponse<List<Object[]>>> getOrderStatistics() {
        logger.info("获取订单统计信息");

        try {
            List<Object[]> statistics = orderService.getOrderStatistics();
            return ResponseEntity.ok(ApiResponse.success("统计信息获取成功", statistics));

        } catch (Exception e) {
            logger.error("获取订单统计信息失败", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(ApiResponse.error("获取统计信息失败"));
        }
    }

    /**
     * 查找延迟处理的订单（用于一致性评估）
     * GET /api/orders/delayed?minutes=5
     * 
     * @param minutes 延迟分钟数（默认5分钟）
     * @return 延迟处理的订单列表
     */
    @GetMapping("/delayed")
    public ResponseEntity<ApiResponse<List<Order>>> getDelayedOrders(
            @RequestParam(defaultValue = "5") int minutes) {

        logger.info("查找延迟订单: delayMinutes={}", minutes);

        try {
            List<Order> delayedOrders = orderService.findDelayedOrders(minutes);
            return ResponseEntity.ok(ApiResponse.success("延迟订单查询成功", delayedOrders));

        } catch (Exception e) {
            logger.error("查找延迟订单失败: minutes={}", minutes, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(ApiResponse.error("查询失败"));
        }
    }

    // ==================== 健康检查接口 ====================

    /**
     * 服务健康检查
     * GET /api/orders/health
     * 
     * @return 服务状态
     */
    @GetMapping("/health")
    public ResponseEntity<ApiResponse<String>> healthCheck() {
        return ResponseEntity.ok(ApiResponse.success("服务正常", "Order Service is running"));
    }

    // ==================== 请求和响应类 ====================

    /**
     * 创建订单请求类
     */
    public static class CreateOrderRequest {
        private Long productId;
        private Integer quantity;
        private String idempotencyKey; // 可选的幂等性键

        // 构造函数
        public CreateOrderRequest() {
        }

        public CreateOrderRequest(Long productId, Integer quantity, String idempotencyKey) {
            this.productId = productId;
            this.quantity = quantity;
            this.idempotencyKey = idempotencyKey;
        }

        // Getter和Setter
        public Long getProductId() {
            return productId;
        }

        public void setProductId(Long productId) {
            this.productId = productId;
        }

        public Integer getQuantity() {
            return quantity;
        }

        public void setQuantity(Integer quantity) {
            this.quantity = quantity;
        }

        public String getIdempotencyKey() {
            return idempotencyKey;
        }

        public void setIdempotencyKey(String idempotencyKey) {
            this.idempotencyKey = idempotencyKey;
        }
    }

    /**
     * 状态更新请求类
     */
    public static class UpdateStatusRequest {
        private OrderStatus status;

        public UpdateStatusRequest() {
        }

        public UpdateStatusRequest(OrderStatus status) {
            this.status = status;
        }

        public OrderStatus getStatus() {
            return status;
        }

        public void setStatus(OrderStatus status) {
            this.status = status;
        }
    }

    /**
     * 统一API响应格式
     */
    public static class ApiResponse<T> {
        private boolean success;
        private String message;
        private T data;
        private long timestamp;

        private ApiResponse(boolean success, String message, T data) {
            this.success = success;
            this.message = message;
            this.data = data;
            this.timestamp = System.currentTimeMillis();
        }

        public static <T> ApiResponse<T> success(String message, T data) {
            return new ApiResponse<>(true, message, data);
        }

        public static <T> ApiResponse<T> error(String message) {
            return new ApiResponse<>(false, message, null);
        }

        // Getter方法
        public boolean isSuccess() {
            return success;
        }

        public String getMessage() {
            return message;
        }

        public T getData() {
            return data;
        }

        public long getTimestamp() {
            return timestamp;
        }
    }
}