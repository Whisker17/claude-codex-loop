# Design: Connection Pool

## Requirements
- Thread-safe connection pool for PostgreSQL
- Configurable min_size and max_size
- Connections are lazily created up to max_size
- get_connection() blocks if pool is exhausted (with configurable timeout)
- release_connection() returns connection to pool
- Health check: validate connections before returning them
- Idle connections closed after idle_timeout (default 300s)
