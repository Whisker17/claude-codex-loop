# Round 4 — Claude Response

## Previously Identified Issues

### Previous Issue 1 (High): code-fix verify contradiction between sections
**Status**: Fixed. Removed the `code-fix` verify branch from section 2 entirely. Section 2 now explicitly states the change applies only to the `design-review` case, and that `code-fix` is unchanged because code-stage verification is Claude-only (per section 3.D). The note clarifies that while `code-fix verify` is technically callable via the shell interface, it is not invoked by the workflow.

### Previous Issue 4 (Medium): Brainstorm data exposure
**Status**: Fixed. Added explicit "no secrets/credentials/API keys" rule to the brainstorming output step. The instruction now reads: "Do NOT include secrets, credentials, API keys, or sensitive data in brainstorm output — this file will be committed to the branch."

## Newly Identified Issues

### Issue 1 (High): brainstorm_done never set to true
**Status**: Fixed. Added explicit step "Set `brainstorm_done: true` in `.claude/review-loop.local.md`" immediately after saving `specs/brainstorm.md` and before waiting for user confirmation.

### Issue 2 (Medium): Hook-driven cancellation loses start_branch
**Status**: Addressed. Added explicit documentation that hook-driven cancellation (`kill-review.sh --from-hook`) does NOT restore branches — only explicit `/cancel-review` does. Rationale: hook cleanup happens when the Claude Code session ends, not mid-workflow; the user can manually switch branches; attempting branch operations in a hook is fragile. Also addressed detached HEAD: `start_branch` stores `git rev-parse --abbrev-ref HEAD` output, and cancellation uses `git checkout <start_branch> || git checkout --detach <start_branch>` to handle both cases.

### Issue 3 (Medium): Tests don't map to executable behavior
**Status**: Fixed. Split tests into two categories: (1) prompt-content assertions that are testable via the shell harness (verify prompt assembly, staging exclusions), and (2) workflow behavior tests that are explicitly marked as manual-verification-only since they depend on Claude's interpretation of markdown instructions, not shell scripts. This avoids false coverage claims.
