---
description: Drive the review-loop v2.1 design and code collaboration flow
argument-hint: <task description>
---

You are running the `review-loop` plugin.

## Goal

Execute the full v2.1 workflow:

1. Brainstorming stage (optional): after the session branch is created, Claude Code can use `superpowers:brainstorming` if available and the user opts in.
2. Design stage: Claude Code authors `specs/design.md` and asks Codex to audit it.
3. User gate: stop after the design stage and wait for explicit confirmation.
4. Code stage: Codex implements code, Claude Code reviews it, and Codex fixes issues iteratively.

## Required startup checks

Before creating any state:

- Confirm the current directory is inside a Git repository.
- Confirm the working tree is clean.
- Confirm the `codex` CLI is installed and available on `PATH`.

Abort with a clear error if any check fails.

Required error messages:

- Not a repository: `review-loop requires a Git repository. Run git init or cd into a repo.`
- Dirty worktree: tell the user to commit or stash changes before continuing.

## State and branch

- Generate a session id.
- Create `.claude/review-loop.local.md`.
- Create and check out `review-loop/<session-id>`.
- Record the user task description in the state file.
- Record `start_branch` with `git rev-parse --abbrev-ref HEAD` before switching branches.
- Record `start_sha` with `git rev-parse HEAD` before switching branches.
- Initialize `brainstorm_done: false`.
- If branch creation fails, clean up `.claude/review-loop.local.md` and stop immediately.

State file shape:

```yaml
---
active: true
session_id: ...
phase: design    # design | code | done
round: null
started_at: ...
branch: review-loop/<session-id>
start_branch: main
start_sha: abc123
baseline_sha: null
brainstorm_done: false
task: "..."
---
```

## Brainstorming (optional)

After the session branch is created and checked out:

0. Check if `superpowers:brainstorming` is listed in the available skills
   (visible in system-reminder messages at conversation start).
   a. If available:
      - Ask the user: "Brainstorming skill is available. Would you like to brainstorm before designing?" Wait for explicit opt-in.
      - If the user opts in:
        - Invoke the brainstorming skill with the user's task description.
        - Save output to `specs/brainstorm.md` on the session branch.
        - Do NOT include secrets, credentials, API keys, or sensitive data in the brainstorm output.
        - Wait for user confirmation that brainstorming output is acceptable.
        - Only after user confirms: set `brainstorm_done: true` in `.claude/review-loop.local.md`.
        - IMPORTANT: Do NOT invoke `superpowers:brainstorming` again for the remainder of this workflow.
        - All other superpowers skills remain available.
      - If the user declines:
        - Skip directly to the design stage.
        - `brainstorm_done` stays `false`.
   b. If not available:
      - Skip directly to the design stage.
      - The user's task description is the sole input.

## Design stage

1. Write `specs/design.md`:
   - Always use the task description from the state file as the authoritative input.
   - If brainstorming ran in this session (that is, `brainstorm_done: true` in the state file) and `specs/brainstorm.md` exists, use it as supplementary context that expands on the task.
   - If the brainstorm conflicts with the task description, the task description takes precedence.
   - If brainstorming was skipped or `specs/brainstorm.md` does not exist, use the task description alone.
   - A pre-existing `specs/brainstorm.md` from a previous session is ignored unless `brainstorm_done: true` is set for the current session.
2. For each round from 1 to 5:
   - Snapshot the worktree before Codex runs:

     ```bash
     PRE_MODIFIED=$(git diff --name-only)
     PRE_STAGED=$(git diff --cached --name-only)
     PRE_UNTRACKED=$(git ls-files --others --exclude-standard)
     ```

   - Execute `review-loop/scripts/run-review-bg.sh design-review <round>`.
   - Poll every 10 seconds with `review-loop/scripts/check-review.sh`.
   - Revert any unauthorized file deltas after Codex completes, times out, or fails by comparing:

     ```bash
     POST_MODIFIED=$(git diff --name-only)
     POST_STAGED=$(git diff --cached --name-only)
     POST_UNTRACKED=$(git ls-files --others --exclude-standard)
     ```

   - The only allowed new file in a design-review round is `specs/reviews/design/round-<round>-codex-review.md`.
   - For unauthorized deltas:
     - Modified tracked file: `git checkout -- <file>`
     - Newly staged file already in `HEAD`: `git reset HEAD -- <file> && git checkout -- <file>`
     - Newly staged new file: `git reset HEAD -- <file> && rm <file>`
     - New untracked file: `rm <file>`
   - Log a warning to `.claude/review-loop.log` for each reverted file.
   - Retry once on `TIMEOUT` or `FAILED`, then skip the round on a second failure.
   - Read `specs/reviews/design/round-<round>-codex-review.md`.
   - If there are no substantive issues, write `specs/reviews/design/round-<round>-claude-response.md` and stop the design loop.
   - Otherwise, update `specs/design.md` and write the matching Claude response file.
3. If all 5 rounds were used and the last round changed `specs/design.md`, perform one final verification pass:
   - Snapshot the worktree using the same `PRE_*` variables as regular design-review rounds.
   - Execute `review-loop/scripts/run-review-bg.sh design-review verify`.
   - Poll with `review-loop/scripts/check-review.sh`.
   - Revert unauthorized file deltas using the same rollback and logging procedure as regular design-review rounds.
   - The only allowed new file in this verify round is `specs/reviews/design/round-verify-codex-review.md`.
   - Retry once on `TIMEOUT` or `FAILED`, then skip on a second failure.
   - Read `specs/reviews/design/round-verify-codex-review.md`.
   - Do NOT make further design edits regardless of findings.
   - Write `specs/reviews/design/round-verify-claude-response.md`.
4. Output exactly: `Design stage complete. Review specs/design.md and confirm.`

Wait for the user before entering the code stage.

## Stage transition

After confirmation:

1. If `brainstorm_done: true` AND `specs/brainstorm.md` exists: `git add specs/brainstorm.md`
2. `git add specs/design.md specs/reviews/design/ .claude/review-loop.log`
3. `git commit -m "review-loop: design stage complete (<session-id>)"`
4. Record `HEAD` as `baseline_sha` in `.claude/review-loop.local.md`.
5. Switch the state phase to `code`.
6. If the commit fails for any reason other than `nothing to commit`, stop and ask the user to resolve the git issue manually.

## Code stage

CRITICAL: Each round must be a full, independent review of the entire diff
against the spec. Do NOT narrow scope to only issues from previous rounds.
Previous findings may have been fixed but new issues may have been introduced.
Review as if seeing the code for the first time each round.

Final verification must be a completely unconstrained full review - ignore
all prior review history and review as if seeing the code for the first time.

1. Snapshot the worktree.
2. Execute `review-loop/scripts/run-review-bg.sh code-implement 1`.
3. Poll with `review-loop/scripts/check-review.sh`.
4. Revert unauthorized changes to protected paths.
   - Allowed for `code-implement`: project source and test files, plus `.claude/review-loop-<session-id>.*`
   - Protected paths: `specs/design.md`, `specs/brainstorm.md`, everything under `specs/reviews/`, and any `.claude/*` path that is not session-scoped runtime state
5. For each round from 1 to 5:
   - Snapshot the worktree before each review cycle using the same `PRE_*` variables as the design stage.
   - `git add -A -- ':!specs/reviews/' ':!specs/brainstorm.md' ':!.claude/'`
   - Review `git diff --staged $BASELINE_SHA -- ':!specs/reviews/' ':!specs/brainstorm.md' ':!.claude/'`
   - `git reset HEAD`
   - Write `specs/reviews/code/round-<round>-claude-review.md`
   - If there are no substantive issues, stop the loop.
   - Otherwise, execute `review-loop/scripts/run-review-bg.sh code-fix <round>`
   - Poll with `review-loop/scripts/check-review.sh`
   - Revert unauthorized changes to protected paths
     - Allowed for `code-fix`: project source and test files, `.claude/review-loop-<session-id>.*`, and `specs/reviews/code/round-<round>-codex-response.md`
   - Read `specs/reviews/code/round-<round>-codex-response.md`
6. If all 5 review rounds are exhausted and the last round required code changes, perform one final review-only verification pass:
   - Write `specs/reviews/code/round-verify-claude-review.md` with a full independent review of the diff and no reference to prior rounds.
   - This is the final artifact. Do NOT invoke Codex or perform additional iterations.
   - There is no `code-fix verify` invocation in this workflow.
7. Output exactly: `Implementation complete. All changes on branch review-loop/<session-id>.`

## Final cleanup

On normal completion, remove:

- `.claude/review-loop.local.md`
- `.claude/review-loop-<session-id>.pid`
- `.claude/review-loop-<session-id>.sentinel`
- `.claude/review-loop-<session-id>-codex-output.log`

On normal completion, preserve:

- `specs/brainstorm.md`
- `specs/design.md`
- `specs/reviews/**`
- `.claude/review-loop.log`

Note: On cancellation, only artifacts already present on `start_branch` survive.
Uncommitted session files are removed by `git clean -fd`, and committed session
files are lost when the session branch is deleted.

## Cancellation

If the user asks to cancel at any point:

1. Read `start_branch`, `start_sha`, and `session_id` from `.claude/review-loop.local.md`.
2. Run `review-loop/scripts/kill-review.sh <session-id>`.
3. Discard all uncommitted session changes: `git reset -- . && git checkout -- . && git clean -fd`.
4. Check out the starting point:
   - If `start_branch` is not `HEAD`: `git checkout <start_branch>`
   - If `start_branch` is `HEAD` (detached): `git checkout --detach <start_sha>`
5. Delete the session branch: `git branch -D review-loop/<session-id>`.

Cancellation means "discard session work." All uncommitted changes are discarded
before branch restoration. Committed work on the session branch is lost when the
branch is deleted.

Hook-driven cancellation via the Stop hook only kills the background process and
removes runtime files. It does not restore branches or delete the session branch.
