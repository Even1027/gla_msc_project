-- Kafka Microservices Consistency Research Project - Database Initialisation Scripts
-- Created: 2025-07-28
-- Description: Complete database table structure for Order Service and Inventory Service

-- Create database (if it doesn't exist)）
CREATE DATABASE IF NOT EXISTS microservices_db;
USE microservices_db;

-- ==================== order form ====================
CREATE TABLE orders (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id VARCHAR(50) UNIQUE NOT NULL COMMENT 'Order Unique Identifier',
    product_id BIGINT NOT NULL COMMENT 'Product ID',
    quantity INT NOT NULL COMMENT 'Number of orders',
    status VARCHAR(20) DEFAULT 'PENDING' COMMENT 'Order Status: PENDING, CONFIRMED, CANCELLED',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Create time',
    updated_at TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP COMMENT 'update time',
    
    INDEX idx_order_id (order_id),
    INDEX idx_product_id (product_id),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='order form';

-- ==================== inventory list ====================
CREATE TABLE inventory (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNIQUE NOT NULL COMMENT 'Product ID, must be unique',
    quantity INT NOT NULL COMMENT 'Total number of stocks',
    reserved_quantity INT NOT NULL DEFAULT 0 COMMENT 'Quantity reserved (ordered but not confirmed)',
    version BIGINT NOT NULL DEFAULT 0 COMMENT 'Optimistic locking of version numbers to prevent concurrent modifications',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Create time',
    updated_at TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP COMMENT 'update time',
    
    INDEX idx_product_id (product_id),
    INDEX idx_version (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='inventory list';

-- ==================== Consistency log table ====================
CREATE TABLE consistency_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL COMMENT 'Event Type: ORDER_CREATED, INVENTORY_RESERVED, INVENTORY_CONFIRMED等',
    order_id VARCHAR(50) COMMENT 'Related Orders ID',
    product_id BIGINT COMMENT 'Associated Commodities ID',
    quantity INT COMMENT 'Quantitative changes',
    old_value INT COMMENT 'Value before change',
    new_value INT COMMENT 'Changed value',
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'event timestamp',
    details TEXT COMMENT 'Details (JSON format)',
    
    INDEX idx_event_type (event_type),
    INDEX idx_order_id (order_id),
    INDEX idx_product_id (product_id),
    INDEX idx_timestamp (timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Consistency event log table';

-- ==================== Initial data insertion ====================

-- Insert test item inventory data
INSERT INTO inventory (product_id, quantity, reserved_quantity, version) VALUES 
(1, 100, 0, 0),  -- Product 1: 100 in stock
(2, 50, 0, 0),   -- Product 2: 50 in stock  
(3, 200, 0, 0);  -- Product 3.: 200 in stock

-- Insert an initialisation log
INSERT INTO consistency_log (event_type, details) VALUES 
('SYSTEM_INIT', '{"message": "Database initialisation complete", "timestamp": "2025-07-28", "inventory_count": 3}');

-- ==================== View creation results ====================

-- Show Table Structure
SHOW TABLES;

-- Show inventory table structure
DESCRIBE inventory;

-- Display initial data
SELECT 
    product_id,
    quantity,
    reserved_quantity,
    quantity - reserved_quantity AS available_quantity,
    version,
    created_at
FROM inventory;

-- Displaying Table Statistics
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