package com.example.inventoryservice.controller;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.example.inventoryservice.entity.Inventory;
import com.example.inventoryservice.service.InventoryService;

@RestController
@RequestMapping("/api/inventory")
@CrossOrigin(origins = "*")
public class InventoryController {

    private static final Logger logger = LoggerFactory.getLogger(InventoryController.class);

    @Autowired
    private InventoryService inventoryService;

    /**
     * 健康检查接口
     * GET /api/inventory/health
     */
    @GetMapping("/health")
    public ResponseEntity<Map<String, Object>> healthCheck() {
        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        response.put("message", "库存服务正常");
        response.put("service", "Inventory Service");
        response.put("timestamp", System.currentTimeMillis());
        response.put("time", LocalDateTime.now());

        return ResponseEntity.ok(response);
    }

    /**
     * 查询所有库存信息
     * GET /api/inventory
     */
    @GetMapping
    public ResponseEntity<Map<String, Object>> getAllInventories() {
        try {
            List<Inventory> inventories = inventoryService.getAllInventories();

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "查询成功");
            response.put("data", inventories);
            response.put("count", inventories.size());
            response.put("timestamp", System.currentTimeMillis());

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            logger.error("查询所有库存失败", e);
            return buildErrorResponse("查询失败: " + e.getMessage(), HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }

    /**
     * 根据商品ID查询库存
     * GET /api/inventory/product/{productId}
     */
    @GetMapping("/product/{productId}")
    public ResponseEntity<Map<String, Object>> getInventoryByProductId(@PathVariable Long productId) {
        try {
            Optional<Inventory> inventory = inventoryService.getInventoryByProductId(productId);

            Map<String, Object> response = new HashMap<>();
            
            if (inventory.isPresent()) {
                response.put("success", true);
                response.put("message", "查询成功");
                response.put("data", inventory.get());
            } else {
                response.put("success", false);
                response.put("message", "商品不存在");
                response.put("data", null);
            }
            
            response.put("timestamp", System.currentTimeMillis());
            return ResponseEntity.ok(response);

        } catch (Exception e) {
            logger.error("查询商品库存失败: productId={}", productId, e);
            return buildErrorResponse("查询失败: " + e.getMessage(), HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }

    /**
     * 查询库存不足的商品
     * GET /api/inventory/low-stock?threshold=10
     */
    @GetMapping("/low-stock")
    public ResponseEntity<Map<String, Object>> getLowStockInventories(
            @RequestParam(defaultValue = "10") Integer threshold) {
        try {
            List<Inventory> lowStockItems = inventoryService.getLowStockInventories(threshold);

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "查询成功");
            response.put("data", lowStockItems);
            response.put("threshold", threshold);
            response.put("count", lowStockItems.size());
            response.put("timestamp", System.currentTimeMillis());

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            logger.error("查询库存不足商品失败: threshold={}", threshold, e);
            return buildErrorResponse("查询失败: " + e.getMessage(), HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }

    /**
     * 手动调整库存（管理功能）
     * PUT /api/inventory/adjust/{productId}
     */
    @PutMapping("/adjust/{productId}")
    public ResponseEntity<Map<String, Object>> adjustInventory(
            @PathVariable Long productId,
            @RequestBody Map<String, Integer> request) {
        try {
            Integer newQuantity = request.get("quantity");
            if (newQuantity == null || newQuantity < 0) {
                return buildErrorResponse("库存数量无效", HttpStatus.BAD_REQUEST);
            }

            inventoryService.adjustInventory(productId, newQuantity);

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "库存调整成功");
            response.put("productId", productId);
            response.put("newQuantity", newQuantity);
            response.put("timestamp", System.currentTimeMillis());

            return ResponseEntity.ok(response);

        } catch (IllegalArgumentException e) {
            logger.warn("库存调整参数错误: productId={}, error={}", productId, e.getMessage());
            return buildErrorResponse(e.getMessage(), HttpStatus.BAD_REQUEST);
            
        } catch (Exception e) {
            logger.error("库存调整失败: productId={}", productId, e);
            return buildErrorResponse("调整失败: " + e.getMessage(), HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }

    /**
     * 构建错误响应
     */
    private ResponseEntity<Map<String, Object>> buildErrorResponse(String message, HttpStatus status) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        response.put("message", message);
        response.put("timestamp", System.currentTimeMillis());
        return ResponseEntity.status(status).body(response);
    }
}