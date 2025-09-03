package com.example.inventoryservice.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import com.example.inventoryservice.entity.Inventory;

@Repository
public interface InventoryRepository extends JpaRepository<Inventory, Long> {
    
    /**
     * 根据商品ID查找库存记录
     * Spring Data JPA会自动实现这个方法
     * 
     * @param productId 商品ID
     * @return 库存记录，如果不存在则返回空
     */
    Optional<Inventory> findByProductId(Long productId);
    
    /**
     * 检查某个商品的库存是否存在
     * 比findByProductId更高效，只返回boolean
     * 
     * @param productId 商品ID
     * @return true如果存在，false如果不存在
     */
    boolean existsByProductId(Long productId);
    
    /**
     * 查找库存不足的商品
     * 自定义JPQL查询，用于监控和报警
     * 
     * @param threshold 库存阈值
     * @return 库存不足的商品列表
     */
    @Query("SELECT i FROM Inventory i WHERE (i.quantity - i.reservedQuantity) < :threshold")
    List<Inventory> findLowStockInventories(@Param("threshold") Integer threshold);
    
    /**
     * 查找有预留库存的商品
     * 用于处理长时间未确认的预留库存
     * 
     * @return 有预留库存的商品列表
     */
    @Query("SELECT i FROM Inventory i WHERE i.reservedQuantity > 0 ORDER BY i.updatedAt ASC")
    List<Inventory> findInventoriesWithReservedStock();
    
    /**
     * 根据可用库存数量查找商品
     * 计算字段查询示例
     * 
     * @param minAvailableQuantity 最小可用库存
     * @return 满足条件的库存记录
     */
    @Query("SELECT i FROM Inventory i WHERE (i.quantity - i.reservedQuantity) >= :minQuantity")
    List<Inventory> findByAvailableQuantityGreaterThanEqual(@Param("minQuantity") Integer minAvailableQuantity);
    
    /**
     * 批量查找多个商品的库存
     * 用于批量处理订单
     * 
     * @param productIds 商品ID列表
     * @return 对应的库存记录列表
     */
    List<Inventory> findByProductIdIn(List<Long> productIds);
    
    /**
     * 统计总库存价值
     * 复杂聚合查询示例（需要商品价格信息，这里是演示）
     * 
     * @return 库存总数量
     */
    @Query("SELECT SUM(i.quantity) FROM Inventory i")
    Long getTotalInventoryQuantity();
    
    /**
     * 统计预留库存总量
     * 用于系统监控
     * 
     * @return 预留库存总数量
     */
    @Query("SELECT SUM(i.reservedQuantity) FROM Inventory i")
    Long getTotalReservedQuantity();
}