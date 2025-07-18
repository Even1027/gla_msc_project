package com.example.orderservice.entity;

public enum OrderStatus {
    PENDING("待处理"),
    CONFIRMED("已确认"), 
    PROCESSING("处理中"),
    COMPLETED("已完成"),
    CANCELLED("已取消"),
    FAILED("失败");
    
    private final String description;
    
    OrderStatus(String description) {
        this.description = description;
    }
    
    public String getDescription() {
        return description;
    }
}