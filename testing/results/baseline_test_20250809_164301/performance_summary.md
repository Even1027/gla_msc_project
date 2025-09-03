# Redis Consistency Configuration Performance Study Results

**Experiment ID:** validation_20250809_164301  
**Execution Date:** 2025-08-09T17:04:02+01:00  
**Redis Container:** redis

## Experimental Setup

### Load Profiles
- **Low Load:** 60s duration, 180 req/min, 3 concurrent users (~3 RPS)
- **Medium Load:** 90s duration, 600 req/min, 5 concurrent users (~10 RPS)  
- **High Load:** 120s duration, 1200 req/min, 8 concurrent users (~20 RPS)

### Redis Configurations Tested
1. **Strong Consistency:** appendfsync=always, save="60 1", maxmemory-policy=noeviction
2. **Balanced Configuration:** appendfsync=everysec, save="900 1 300 10 60 10000", maxmemory-policy=allkeys-lru
3. **Performance Optimized:** appendfsync=no, save="", maxmemory-policy=volatile-lru

## Key Findings

*To be filled with analysis of consolidated_results.csv*

## Data Files
- **Consolidated Results:** consolidated_results.csv
- **Raw Test Data:** Available in respective configuration/profile subdirectories
- **Configuration Snapshots:** redis_config_snapshot.txt in each configuration directory

## Methodology Notes
- Each configuration change included a 10s stabilization period
- System warmup performed with 5 requests before each test
- 5s pause between load profiles to reduce interference
- Idempotency testing with 30% repeated keys to measure cache effectiveness
