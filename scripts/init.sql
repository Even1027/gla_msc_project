-- Kafka微服务一致性研究项目 - 数据库初始化脚本
-- 创建时间: 2025-07-28
-- 说明: 订单服务和库存服务的完整数据库表结构

-- 创建数据库（如果不存在）
CREATE DATABASE IF NOT EXISTS microservices_db;
USE microservices_db;

-- ==================== 订单表 ====================
CREATE TABLE orders (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id VARCHAR(50) UNIQUE NOT NULL COMMENT '订单唯一标识',
    product_id BIGINT NOT NULL COMMENT '商品ID',
    quantity INT NOT NULL COMMENT '订单数量',
    status VARCHAR(20) DEFAULT 'PENDING' COMMENT '订单状态: PENDING, CONFIRMED, CANCELLED',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    updated_at TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    
    INDEX idx_order_id (order_id),
    INDEX idx_product_id (product_id),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单表';

-- ==================== 库存表 ====================
CREATE TABLE inventory (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNIQUE NOT NULL COMMENT '商品ID，必须唯一',
    quantity INT NOT NULL COMMENT '总库存数量',
    reserved_quantity INT NOT NULL DEFAULT 0 COMMENT '预留数量（已下单但未确认）',
    version BIGINT NOT NULL DEFAULT 0 COMMENT '乐观锁版本号，防止并发修改',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    updated_at TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    
    INDEX idx_product_id (product_id),
    INDEX idx_version (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='库存表';

-- ==================== 一致性日志表 ====================
CREATE TABLE consistency_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL COMMENT '事件类型: ORDER_CREATED, INVENTORY_RESERVED, INVENTORY_CONFIRMED等',
    order_id VARCHAR(50) COMMENT '关联的订单ID',
    product_id BIGINT COMMENT '关联的商品ID',
    quantity INT COMMENT '数量变化',
    old_value INT COMMENT '变更前的值',
    new_value INT COMMENT '变更后的值',
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '事件时间戳',
    details TEXT COMMENT '详细信息（JSON格式）',
    
    INDEX idx_event_type (event_type),
    INDEX idx_order_id (order_id),
    INDEX idx_product_id (product_id),
    INDEX idx_timestamp (timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='一致性事件日志表';

-- ==================== 初始数据插入 ====================

-- 插入测试商品库存数据
INSERT INTO inventory (product_id, quantity, reserved_quantity, version) VALUES 
(1, 100, 0, 0),  -- 商品1: 100个库存
(2, 50, 0, 0),   -- 商品2: 50个库存  
(3, 200, 0, 0);  -- 商品3: 200个库存

-- 插入一条初始化日志
INSERT INTO consistency_log (event_type, details) VALUES 
('SYSTEM_INIT', '{"message": "数据库初始化完成", "timestamp": "2025-07-28", "inventory_count": 3}');

-- ==================== 查看创建结果 ====================

-- 显示表结构
SHOW TABLES;

-- 显示库存表结构
DESCRIBE inventory;

-- 显示初始数据
SELECT 
    product_id,
    quantity,
    reserved_quantity,
    quantity - reserved_quantity AS available_quantity,
    version,
    created_at
FROM inventory;

-- 显示表统计信息
SELECT 
    'orders' as table_name, 
    COUNT(*) as record_count 
FROM orders
UNION ALL
SELECT 
    'inventory' as table_name, 
    COUNT(*) as record_count 
FROM inventory
UNION ALL
SELECT 
    'consistency_log' as table_name, 
    COUNT(*) as record_count 
FROM consistency_log;