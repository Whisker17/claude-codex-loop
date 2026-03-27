# Design: Multi-Tenant API Gateway with Rate Limiting and Billing

## Overview

An API gateway that routes requests to downstream microservices, enforces per-tenant rate limits, tracks usage for billing, and handles authentication. Built in Python with asyncio.

## Architecture

### Components

1. **Router** — maps incoming requests to downstream services based on path patterns
2. **AuthMiddleware** — validates API keys and resolves tenant context
3. **RateLimiter** — per-tenant sliding window rate limiting using Redis
4. **UsageTracker** — records API calls for billing aggregation
5. **CircuitBreaker** — prevents cascading failures to unhealthy downstream services
6. **ResponseCache** — caches GET responses to reduce downstream load

### Request Flow

```
Client → AuthMiddleware → RateLimiter → ResponseCache → CircuitBreaker → Router → Downstream
                                                                                      ↓
Client ← ResponseCache ← UsageTracker ←────────────────────────────────────── Response
```

### Authentication

1. Extract API key from `Authorization: Bearer <key>` header
2. Look up key in Redis cache (TTL=60s) or fall back to PostgreSQL
3. Resolve tenant_id, plan_tier, and permissions
4. Attach tenant context to request
5. Invalid/missing key → 401

### Rate Limiting

Per-tenant limits based on plan tier:
- Free: 100 req/min
- Pro: 1000 req/min
- Enterprise: 10000 req/min

Implementation:
```python
async def check_rate_limit(self, tenant_id: str, tier: str) -> bool:
    key = f"ratelimit:{tenant_id}"
    now = time.time()
    window = 60

    pipe = self.redis.pipeline()
    pipe.zremrangebyscore(key, 0, now - window)
    pipe.zadd(key, {str(now): now})
    pipe.zcard(key)
    pipe.expire(key, window)
    _, _, count, _ = await pipe.execute()

    limit = self.tier_limits[tier]
    return count <= limit
```

### Usage Tracking

After each successful response:
1. Publish usage event to Redis Stream: `{tenant_id, endpoint, method, status_code, response_time_ms, timestamp}`
2. A background consumer aggregates events into per-tenant daily counters in PostgreSQL
3. Billing service reads daily counters at end of billing cycle

### Circuit Breaker

Per-downstream-service circuit breaker with three states:
- **Closed**: requests pass through. Track failure rate over last 60 seconds.
- **Open**: all requests immediately return 503. Transition to half-open after 30 seconds.
- **Half-open**: allow one probe request. If success → closed. If failure → open.

Failure threshold: 50% of requests in the window, minimum 10 requests.

### Response Cache

- Cache GET responses in Redis with key `cache:{tenant_id}:{method}:{path}:{query_hash}`
- TTL based on downstream Cache-Control header, default 60s
- Invalidate on any non-GET request to the same path prefix
- Cache is per-tenant to prevent data leakage between tenants

### Configuration

```yaml
routes:
  /api/users/*: {service: user-service, port: 8001}
  /api/orders/*: {service: order-service, port: 8002}
  /api/products/*: {service: product-service, port: 8003}

rate_limits:
  free: 100
  pro: 1000
  enterprise: 10000

circuit_breaker:
  failure_threshold: 0.5
  min_requests: 10
  open_duration: 30
  window: 60
```

### Error Handling

- Auth failure → 401
- Rate limit exceeded → 429 with Retry-After
- Circuit open → 503 with Retry-After
- Downstream timeout → 504
- Internal error → 500

### Testing

- Auth: test valid/invalid/expired keys
- Rate limiting: test per-tenant isolation and limit enforcement
- Circuit breaker: test state transitions
- Cache: test hit/miss/invalidation
- Integration: end-to-end request flow through all middleware
