---
description: Cancel an active review-loop session
---

Cancel the active `review-loop` session.

## Steps

1. Read `.claude/review-loop.local.md` and extract `session_id`.
2. Run `plugins/review-loop/scripts/kill-review.sh <session_id>`.
3. Remove `.claude/review-loop.local.md`.
4. Tell the user which runtime files were cleaned up and which audit artifacts remain in `specs/reviews/`.
