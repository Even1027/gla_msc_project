package com.example.inventoryservice.entity;

import java.time.LocalDateTime;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

@Entity
@Table(name = "inventory")
public class Inventory {
    
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    // 解释: 数据库主键，自动生成
    
    @Column(unique = true, nullable = false)
    private Long productId;
    // 解释: 商品ID，与订单中的productId对应，必须唯一
    
    @Column(nullable = false)
    private Integer quantity;
    // 解释: 当前可用库存数量，不能为空
    
    @Column(nullable = false)
    private Integer reservedQuantity = 0;
    // 解释: 预留数量，已下单但未确认的库存，默认为0
    
    @Version
    private Long version;
    // 解释: 乐观锁版本号，防止并发修改冲突
    // 当多个请求同时修改库存时，确保数据一致性
    
    @Column(updatable = false)
    private LocalDateTime createdAt = LocalDateTime.now();
    // 解释: 创建时间，不可修改，用于追踪和分析
    
    private LocalDateTime updatedAt = LocalDateTime.now();
    // 解释: 最后更新时间，每次修改都会更新
    
    // 默认构造函数（JPA需要）
    public Inventory() {}
    
    // 业务构造函数
    public Inventory(Long productId, Integer quantity) {
        this.productId = productId;
        this.quantity = quantity;
        this.reservedQuantity = 0;
        this.createdAt = LocalDateTime.now();
        this.updatedAt = LocalDateTime.now();
    }
    
    // 业务方法：检查是否有足够库存
    public boolean hasEnoughStock(Integer requestedQuantity) {
        return (quantity - reservedQuantity) >= requestedQuantity;
    }
    
    // 业务方法：预留库存
    public void reserveStock(Integer requestedQuantity) {
        if (!hasEnoughStock(requestedQuantity)) {
            throw new IllegalStateException(
                String.format("库存不足: 商品ID=%d, 请求数量=%d, 可用库存=%d", 
                             productId, requestedQuantity, getAvailableQuantity())
            );
        }
        this.reservedQuantity += requestedQuantity;
        this.updatedAt = LocalDateTime.now();
    }
    
    // 业务方法：确认库存扣减
    public void confirmReduction(Integer confirmedQuantity) {
        if (confirmedQuantity > reservedQuantity) {
            throw new IllegalStateException(
                String.format("确认数量超过预留数量: 商品ID=%d, 确认数量=%d, 预留数量=%d", 
                             productId, confirmedQuantity, reservedQuantity)
            );
        }
        this.quantity -= confirmedQuantity;
        this.reservedQuantity -= confirmedQuantity;
        this.updatedAt = LocalDateTime.now();
    }
    
    // 业务方法：取消预留
    public void cancelReservation(Integer cancelQuantity) {
        if (cancelQuantity > reservedQuantity) {
            throw new IllegalStateException(
                String.format("取消数量超过预留数量: 商品ID=%d, 取消数量=%d, 预留数量=%d", 
                             productId, cancelQuantity, reservedQuantity)
            );
        }
        this.reservedQuantity -= cancelQuantity;
        this.updatedAt = LocalDateTime.now();
    }
    
    // 计算可用库存
    public Integer getAvailableQuantity() {
        return quantity - reservedQuantity;
    }
    
    // Getter和Setter方法
    public Long getId() {
        return id;
    }
    
    public void setId(Long id) {
        this.id = id;
    }
    
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
        this.updatedAt = LocalDateTime.now();
    }
    
    public Integer getReservedQuantity() {
        return reservedQuantity;
    }
    
    public void setReservedQuantity(Integer reservedQuantity) {
        this.reservedQuantity = reservedQuantity;
        this.updatedAt = LocalDateTime.now();
    }
    
    public Long getVersion() {
        return version;
    }
    
    public void setVersion(Long version) {
        this.version = version;
    }
    
    public LocalDateTime getCreatedAt() {
        return createdAt;
    }
    
    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }
    
    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }
    
    public void setUpdatedAt(LocalDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }
    
    @Override
    public String toString() {
        return "Inventory{" +
                "id=" + id +
                ", productId=" + productId +
                ", quantity=" + quantity +
                ", reservedQuantity=" + reservedQuantity +
                ", version=" + version +
                ", availableQuantity=" + getAvailableQuantity() +
                ", createdAt=" + createdAt +
                ", updatedAt=" + updatedAt +
                '}';
    }
}