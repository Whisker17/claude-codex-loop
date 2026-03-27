# Design: REST API Rate Limiter Middleware

## Requirements
- Python Flask middleware using sliding window algorithm
- 100 requests per 60-second window per client IP
- Thread-safe using threading.Lock
- Support X-Forwarded-For header for proxy deployments
- Return 429 with calculated Retry-After header
- Health check endpoint (/health) exempt from rate limiting
- Configurable MAX_REQUESTS and WINDOW_SECONDS

## Architecture
- `rate_limiter.py`: RateLimiter class with is_allowed(ip) method
- `app.py`: Flask app with before_request middleware
- `test_rate_limiter.py`: Tests for rate limiting logic
- RateLimiter takes a clock function parameter for testability
- Storage interface: abstract base, with InMemoryStore implementation
