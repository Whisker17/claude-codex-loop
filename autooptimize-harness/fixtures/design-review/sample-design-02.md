# Design: Real-Time Collaborative Document Editor (Backend)

## Overview

Backend service for a collaborative document editor supporting multiple simultaneous users editing the same document. Uses Operational Transformation (OT) for conflict resolution and WebSocket for real-time synchronization.

## Architecture

### Components

1. **DocumentService** — CRUD operations, version management
2. **OTEngine** — transforms concurrent operations for consistency
3. **SessionManager** — tracks active editing sessions and connected clients
4. **WebSocketHandler** — real-time bidirectional communication
5. **PersistenceLayer** — stores documents and operation history in MongoDB

### Data Model

```
Document:
  id: string
  title: string
  content: string            # current document state
  version: int               # monotonically increasing
  last_modified: datetime
  created_by: string

Operation:
  id: string
  document_id: string
  user_id: string
  type: "insert" | "delete"
  position: int              # character position in document
  content: string            # for insert: text to insert; for delete: empty
  length: int                # for delete: number of chars to delete
  base_version: int          # version this op was created against
  server_version: int        # version assigned by server after transform
  timestamp: datetime
```

### Operational Transformation

When the server receives an operation from a client:

1. The client sends `(operation, base_version)`
2. Server fetches all operations between `base_version` and current `version`
3. Transform the incoming operation against each intermediate operation sequentially
4. Apply the transformed operation to the document
5. Increment document version
6. Broadcast the transformed operation to all other connected clients

Transform rules:
- **insert vs insert**: if positions conflict, the operation from the user with the lower user_id wins (goes first)
- **insert vs delete**: adjust positions based on whether the insert falls within, before, or after the delete range
- **delete vs delete**: handle overlapping ranges by adjusting length and position

### WebSocket Protocol

```
Client -> Server:
  { type: "operation", doc_id: "...", op: {...}, base_version: N }
  { type: "cursor",    doc_id: "...", position: N }
  { type: "join",      doc_id: "..." }
  { type: "leave",     doc_id: "..." }

Server -> Client:
  { type: "operation", op: {...}, server_version: N, user_id: "..." }
  { type: "cursor",    user_id: "...", position: N }
  { type: "sync",      content: "...", version: N }
  { type: "users",     users: [...] }
```

### Conflict Resolution Flow

1. Client A and Client B both edit at version 5
2. Client A's op arrives first → transformed against nothing → becomes version 6
3. Client B's op arrives → base_version=5, current=6 → transform against Client A's op → becomes version 7
4. Server broadcasts A's op to B, B's transformed op to A

### Persistence

- Operations are stored permanently for history/undo
- Document content is updated in-place after each operation
- A snapshot is saved every 100 operations to allow fast reconstruction
- On server restart, replay all operations since last snapshot

### Session Management

- Each document has a session with a list of active users
- Sessions are stored in Redis with TTL=300s
- Heartbeat every 30s refreshes the TTL
- If TTL expires, user is removed from session and cursor broadcast stops

### Scaling

- Multiple server instances behind a load balancer
- WebSocket connections are sticky per server instance
- Cross-instance operation broadcasting via Redis Pub/Sub
- Document-level locking with Redis SETNX for operation ordering

### Testing

- Unit tests for OT transform correctness with known operation pairs
- Integration test: simulate 3 clients making concurrent edits
- Fuzz test: random operations on random documents to check convergence
