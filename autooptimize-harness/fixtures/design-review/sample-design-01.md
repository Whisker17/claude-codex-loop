# Design: Distributed Task Queue

## Overview

A Python distributed task queue for processing background jobs across multiple worker processes. Workers pull tasks from a shared PostgreSQL-backed queue. Supports task priorities, retries with exponential backoff, and dead-letter handling.

## Architecture

### Components

1. **TaskQueue** — enqueue/dequeue interface backed by PostgreSQL
2. **Worker** — long-running process that polls for tasks and executes handlers
3. **Scheduler** — cron-like scheduler that enqueues recurring tasks
4. **DeadLetterHandler** — moves permanently failed tasks to a dead-letter table

### Database Schema

```sql
CREATE TABLE tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    queue_name VARCHAR(255) NOT NULL,
    payload JSONB NOT NULL,
    priority INT DEFAULT 0,        -- higher = more important
    status VARCHAR(50) DEFAULT 'pending',  -- pending, running, completed, failed, dead
    attempts INT DEFAULT 0,
    max_attempts INT DEFAULT 3,
    created_at TIMESTAMP DEFAULT NOW(),
    scheduled_at TIMESTAMP DEFAULT NOW(),
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    locked_by VARCHAR(255),        -- worker ID holding the lock
    locked_until TIMESTAMP,        -- lock expiry for crash recovery
    error_message TEXT
);

CREATE INDEX idx_tasks_dequeue ON tasks (queue_name, priority, scheduled_at)
    WHERE status = 'pending';
```

### Dequeue Algorithm

```python
def dequeue(self, queue_name: str) -> Optional[Task]:
    """Atomically claim the next available task."""
    result = db.execute("""
        UPDATE tasks
        SET status = 'running',
            locked_by = :worker_id,
            locked_until = NOW() + INTERVAL '5 minutes',
            started_at = NOW(),
            attempts = attempts + 1
        WHERE id = (
            SELECT id FROM tasks
            WHERE queue_name = :queue_name
              AND status = 'pending'
              AND scheduled_at <= NOW()
            ORDER BY priority, scheduled_at
            LIMIT 1
            FOR UPDATE SKIP LOCKED
        )
        RETURNING *
    """, {"queue_name": queue_name, "worker_id": self.worker_id})
    return result.fetchone()
```

### Retry Logic

When a task fails:
1. If `attempts < max_attempts`: set status back to 'pending', set `scheduled_at` to `NOW() + backoff_delay`
2. If `attempts >= max_attempts`: set status to 'dead', move to dead-letter table
3. Backoff delay: `min(base_delay * 2^attempts, max_delay)` where base_delay=10s, max_delay=3600s

### Worker Lifecycle

```
1. Worker starts, registers with unique worker_id
2. Poll loop:
   a. Call dequeue() to get a task
   b. If task found: execute handler, mark complete or failed
   c. If no task: sleep for poll_interval (default 1s)
3. On graceful shutdown: finish current task, release locks
4. Crash recovery: a sweeper process runs every 60s, finds tasks where
   locked_until < NOW() AND status = 'running', resets them to 'pending'
```

### Scheduler

The scheduler runs as a separate process:
1. Reads cron definitions from a YAML config file
2. Every 30 seconds, checks which jobs are due
3. Enqueues a task for each due job
4. Tracks last_run per job to prevent duplicate enqueues

### Configuration

```yaml
queues:
  default:
    workers: 4
    poll_interval: 1
  critical:
    workers: 2
    poll_interval: 0.5
    max_attempts: 5

schedules:
  cleanup_old_data:
    cron: "0 2 * * *"
    queue: default
    payload: {}
  send_daily_report:
    cron: "0 8 * * 1-5"
    queue: critical
    payload: {report_type: "daily"}
```

### Testing Strategy

- Unit tests for dequeue atomicity using concurrent threads
- Integration tests with a test PostgreSQL database
- Retry behavior tested with mock clock
- Scheduler tested with frozen time
