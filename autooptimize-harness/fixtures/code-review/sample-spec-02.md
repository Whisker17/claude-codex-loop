# Design: Event Sourcing Aggregate Store

## Requirements
- Store domain events for aggregates (e.g., Order, User)
- Reconstruct aggregate state by replaying events
- Optimistic concurrency: reject writes if expected_version doesn't match
- Snapshot every 50 events for fast reconstruction
- Thread-safe for concurrent reads and writes to different aggregates
- Event handlers notified after successful append
