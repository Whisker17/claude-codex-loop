---
description: Cancel an active review-loop session
---

Cancel the active `review-loop` session.

## Steps

1. Read `.claude/review-loop.local.md` and extract `session_id`, `start_branch`, and `start_sha`.
2. Run `review-loop/scripts/kill-review.sh <session_id>`.
3. Discard uncommitted changes: `git reset -- . && git checkout -- . && git clean -fd`.
4. Restore starting point:
   - If `start_branch` is not `HEAD`: `git checkout <start_branch>`
   - If `start_branch` is `HEAD`: `git checkout --detach <start_sha>`
5. Delete the session branch: `git branch -D review-loop/<session-id>`.
6. Tell the user that session work has been discarded. Only artifacts already present on `start_branch` before the session started will remain.
