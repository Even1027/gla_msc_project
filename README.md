# Kafka Microservices Consistency Evaluation

> A research project evaluating consistency mechanisms in Kafka-based microservices systems  
> **Academic Project** | **MSc Computer Science** | **2024-2025**

## Project Objective

This project evaluates and compares two consistency mechanisms in a microservices architecture:
1. **Redis-based Idempotency Control** - Preventing duplicate message processing
2. **Kafka Eventual Consistency** - Asynchronous message-driven consistency

## System Architecture

```
┌─────────────────┐    Kafka     ┌─────────────────┐
│   Order Service │ ──────────► │ Inventory Service│
│   (Port 8080)   │              │   (Port 8081)   │
└─────────────────┘              └─────────────────┘
         │                                │
         ▼                                ▼
    ┌─────────┐                     ┌─────────┐
    │  Redis  │                     │  MySQL  │
    │ (6379)  │                     │ (3307)  │
    └─────────┘                     └─────────┘
```

## Technology Stack

- **Backend**: Spring Boot 3.1.5, Java 21
- **Message Queue**: Apache Kafka 7.4.0
- **Database**: MySQL 8.0
- **Cache/Idempotency**: Redis 7.0
- **Containerization**: Docker & Docker Compose
- **Build Tool**: Maven 3.9+

## Quick Start

### Prerequisites
- Docker and Docker Compose
- Java 17+ (Java 21 recommended)
- VSCode with Java Extension Pack

### 1. Clone Repository
```bash
git clone https://github.com/YourUsername/kafka-microservices-consistency.git
cd kafka-microservices-consistency
```

### 2. Start Infrastructure Services
```bash
docker-compose up -d
```

### 3. Verify Services
```bash
docker-compose ps
```

### 4. Start Order Service
```bash
cd order-service
mvn spring-boot:run
```

### 5. Access Services
- **Order Service**: http://localhost:8080
- **Kafka UI**: http://localhost:8090
- **MySQL**: localhost:3307

## Consistency Mechanisms

### 1. Redis Idempotency Control
- Prevents duplicate order processing
- Uses Redis keys with TTL
- Handles network retries and failures

### 2. Kafka Eventual Consistency
- Asynchronous order-inventory synchronization
- At-least-once delivery guarantees
- Message ordering and deduplication

## Experimental Design

### Test Scenarios
1. **Baseline**: Normal operation without failures
2. **Redis Failure**: Container restart impact on idempotency
3. **Service Interruption**: Inventory service restart recovery
4. **Message Delays**: Kafka consumer lag effects
5. **Combined Failures**: Multiple failure scenarios

### Metrics Collected
- **Consistency Error Frequency**
- **Eventual Consistency Latency**
- **Idempotency Effectiveness**
- **Message Delivery Reliability**
- **System Recovery Time**

## Project Structure

```
├── README.md                    # Project documentation
├── docker-compose.yml           # Infrastructure services
├── scripts/
│   └── init.sql                # Database initialization
├── order-service/              # Order microservice
│   ├── pom.xml
│   └── src/main/java/com/example/orderservice/
└── inventory-service/          # Inventory microservice (TBD)
    ├── pom.xml
    └── src/main/java/com/example/inventoryservice/
```

## Development

### Adding New Features
1. Create feature branch: `git checkout -b feature/feature-name`
2. Implement changes
3. Test thoroughly
4. Commit: `git commit -m "Add feature description"`
5. Push: `git push origin feature/feature-name`
6. Create Pull Request

### Running Tests
```bash
mvn test
```

## Research Results

> Results will be updated as experiments are conducted

## Contributing

This is an academic research project. For questions or suggestions:
- Email: [your.email@university.edu]
- Supervisor: [supervisor.email@university.edu]

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Academic Context

**Institution**: [Your University Name]  
**Program**: MSc Computer Science  
**Course**: [Course Name]  
**Supervisor**: [Supervisor Name]  
**Academic Year**: 2024-2025

---

*This project demonstrates practical implementation of consistency mechanisms in distributed systems, contributing to the understanding of microservices reliability patterns.*