---
description: Drive the review-loop v2 design and code collaboration flow
argument-hint: <task description>
---

You are running the `review-loop` plugin.

## Goal

Execute the full v2 workflow:

1. Design stage: Claude Code authors `specs/design.md` and asks Codex to audit it.
2. User gate: stop after the design stage and wait for explicit confirmation.
3. Code stage: Codex implements code, Claude Code reviews it, and Codex fixes issues iteratively.

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
- If branch creation fails, clean up `.claude/review-loop.local.md` and stop immediately.

## Design stage

1. Write `specs/design.md`.
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
3. If all 5 rounds were used and the last round changed `specs/design.md`, perform one final verification pass without making further design edits.
4. Output exactly: `Design stage complete. Review specs/design.md and confirm.`

Wait for the user before entering the code stage.

## Stage transition

After confirmation:

1. `git add specs/design.md specs/reviews/design/ .claude/review-loop.log`
2. `git commit -m "review-loop: design stage complete (<session-id>)"`
3. Record `HEAD` as `baseline_sha` in `.claude/review-loop.local.md`
4. Switch the state phase to `code`
5. If the commit fails for any reason other than `nothing to commit`, stop and ask the user to resolve the git issue manually.

## Code stage

1. Snapshot the worktree.
2. Execute `review-loop/scripts/run-review-bg.sh code-implement 1`.
3. Poll with `review-loop/scripts/check-review.sh`.
4. Revert unauthorized changes to protected paths.
   - Allowed for `code-implement`: project source and test files, plus `.claude/review-loop-<session-id>.*`
   - Protected paths: `specs/design.md`, everything under `specs/reviews/`, and any `.claude/*` path that is not session-scoped runtime state
5. For each round from 1 to 5:
   - Snapshot the worktree before each review cycle using the same `PRE_*` variables as the design stage.
   - `git add -A -- ':!specs/reviews/' ':!.claude/'`
   - Review `git diff --staged $BASELINE_SHA -- ':!specs/reviews/' ':!.claude/'`
   - `git reset HEAD`
   - Write `specs/reviews/code/round-<round>-claude-review.md`
   - If there are no substantive issues, stop the loop.
   - Otherwise, execute `review-loop/scripts/run-review-bg.sh code-fix <round>`
   - Poll with `review-loop/scripts/check-review.sh`
   - Revert unauthorized changes to protected paths
     - Allowed for `code-fix`: project source and test files, `.claude/review-loop-<session-id>.*`, and `specs/reviews/code/round-<round>-codex-response.md`
   - Read `specs/reviews/code/round-<round>-codex-response.md`
6. If all 5 review rounds are exhausted and the last round required code changes, perform one final review-only verification pass.
7. Output exactly: `Implementation complete. All changes on branch review-loop/<session-id>.`

## Final cleanup

On completion or cancellation, remove:

- `.claude/review-loop.local.md`
- `.claude/review-loop-<session-id>.pid`
- `.claude/review-loop-<session-id>.sentinel`
- `.claude/review-loop-<session-id>-codex-output.log`

Preserve:

- `specs/design.md`
- `specs/reviews/**`
- `.claude/review-loop.log`

## Cancellation

If the user asks to cancel at any point, run `review-loop/scripts/kill-review.sh <session-id>` and remove `.claude/review-loop.local.md`.
