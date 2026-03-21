# Review Loop v2.1 Implementation Design

## Overview

Incremental update to the review-loop plugin addressing two production issues: attention narrowing during review rounds and superpowers:brainstorming conflict. All changes are backwards-compatible.

## File Changes

### 1. `review-loop/prompts/design-review.md`

**Current state**: Minimal auditor prompt with basic audit criteria and constraints.

**Changes**: Full rewrite with stronger review instructions.

```markdown
Role: Independent design auditor (READ-ONLY role)
Task: Perform a complete, independent audit of the following design document.

CRITICAL: Every round is a full audit. You must review the entire document as
if seeing it for the first time. Previous review context (if provided below)
is supplementary — use it only to verify that previously identified issues
were addressed, but you MUST also examine all other aspects of the document
for new issues. Do NOT limit your review scope to previously raised issues.

Audit criteria:
- Requirements completeness: all use cases and edge cases covered
- Technical feasibility: implementation risks, blockers
- Architecture: module boundaries, dependencies, interface design
- Security: potential vulnerabilities
- Testability: can the design be verified
- Interface consistency: naming, payload shapes, list/detail parity
- Completeness of new additions: changes addressing prior feedback may
  introduce new gaps

Constraints:
- You MUST NOT modify any files except your review output file
- Do not modify specs/design.md, source code, tests, or configuration
- Do not run git commit, git add, or any git write operations

Output requirements:
- Each issue: severity (critical/high/medium/low), description, recommendation
- For regular rounds (with prior context): separate "previously identified
  (now fixed/still open)" from "newly identified" issues
- For verify rounds (no prior context): report all findings as fresh — do not
  attempt to classify issues as "previously identified" since no prior context
  is available
- Write ONLY to specs/reviews/design/round-{{ROUND}}-codex-review.md

The runtime context is appended below.
```

Key additions:
- CRITICAL full-audit mandate at the top
- Two new audit criteria: interface consistency, completeness of new additions
- Output format with conditional section split: regular rounds separate old/new issues, verify rounds report all findings as fresh

### 2. `review-loop/scripts/common.sh` — `build_prompt()` changes

**Current state**: `build_prompt()` always includes previous round context for both regular and verify rounds.

**Changes**: Add verify-round detection that strips prior review context and prepends a fresh-review header.

The change applies only to the `design-review` case within `build_prompt()`. The `code-fix` case is unchanged because code-stage verification is Claude-only (see section 3.D) — `code-fix verify` is never called.

```bash
# In the design-review case:
if [[ "$round" == "verify" ]]; then
  # Verify round: prepend independent review header, skip ALL prior context
  printf '\n## FULL INDEPENDENT REVIEW\n'
  printf 'This is a final verification pass. You MUST perform a complete,\n'
  printf 'independent review of the entire document from scratch. Ignore all\n'
  printf 'prior review history. Review as if seeing this document for the\n'
  printf 'first time.\n'
else
  # Regular round: include previous round context (existing behavior)
  previous_round="$(review_loop::previous_round_for_pair ...)"
  if [[ -n "$previous_round" ]]; then
    review_loop::append_file_section "Previous Codex Review" ...
    review_loop::append_file_section "Previous Claude Response" ...
  fi
fi
```

The `code-fix` case remains unchanged — only regular rounds (1-5) are used.

Note: The `validate_round()` function already accepts `"verify"` as a valid round value — no change needed there. While `code-fix verify` is technically callable via the shell interface, it is not invoked by the workflow. Adding validation to restrict it is out of scope for v2.1.

### 3. `review-loop/commands/review-loop.md`

**Current state**: Two-stage workflow (design + code) with no brainstorming or fresh-review instructions.

**Changes**:

#### A. Add optional brainstorming stage (after branch creation)

Insert a new section between "State and branch" and "Design stage". Brainstorming runs **after** the session branch is created to maintain branch isolation:

```markdown
## Brainstorming (optional)

After the session branch is created and checked out:

0. Check if `superpowers:brainstorming` is listed in the available skills
   (visible in system-reminder messages at conversation start).
   a. If available:
      - Ask the user: "Brainstorming skill is available. Would you like to
        brainstorm before designing?" Wait for explicit opt-in.
      - If the user opts in:
        - Invoke the brainstorming skill with the user's task description
        - Save output to `specs/brainstorm.md` (on the session branch).
          Do NOT include secrets, credentials, API keys, or sensitive data in
          brainstorm output — this file will be committed to the branch.
        - Wait for user confirmation that brainstorming output is acceptable
        - Only after user confirms: set `brainstorm_done: true` in
          `.claude/review-loop.local.md`
        - IMPORTANT: Do NOT invoke `superpowers:brainstorming` again for the
          remainder of this workflow. All other superpowers skills remain available.
      - If the user declines:
        - Skip directly to the design stage
        - `brainstorm_done` stays `false`
   b. If not available:
      - Skip directly to the design stage
      - The user's task description is the sole input
```

#### B. Update design stage to use brainstorm.md

The design stage uses `specs/brainstorm.md` as **supplementary context**, not as a replacement for the user's task. Usage is gated on whether the **current session** generated brainstorm output:

```markdown
4. Write `specs/design.md`:
   - Always use the task description from the state file as the authoritative input.
   - If brainstorming ran in this session (i.e., `brainstorm_done: true` in state file)
     AND `specs/brainstorm.md` exists, use it as supplementary context that expands
     on the task. If the brainstorm conflicts with the task description, the task
     description takes precedence.
   - If brainstorming was skipped or `specs/brainstorm.md` does not exist, use the
     task description alone.
   - A pre-existing `specs/brainstorm.md` from a previous session is ignored unless
     `brainstorm_done: true` is set for the current session.
```

#### C. Add verify round orchestration to design stage

The design stage verify step is a Codex review pass that uses the **same snapshot, allowed-file, rollback, logging, and retry procedure** as regular design-review rounds. The only differences are: no prior context in the prompt, and the allowed output file is `round-verify-codex-review.md`.

```markdown
3. If all 5 rounds were used and the last round changed `specs/design.md`,
   perform one final verification pass:
   - Snapshot the worktree (same PRE_* variables as regular rounds)
   - Execute `review-loop/scripts/run-review-bg.sh design-review verify`
   - Poll with `review-loop/scripts/check-review.sh`
   - Revert unauthorized file deltas (allowed new file: `specs/reviews/design/round-verify-codex-review.md`)
   - Retry once on TIMEOUT or FAILED, then skip on second failure
   - Read `specs/reviews/design/round-verify-codex-review.md`
   - Do NOT make further design edits regardless of findings
   - Write `specs/reviews/design/round-verify-claude-response.md`
```

#### D. Code stage verify is Claude-only

The code stage verify step is a **Claude-only review**. There is no `code-fix verify` invocation — this avoids reusing an editing prompt for a no-more-edits step:

```markdown
6. If all 5 review rounds are exhausted and the last round required code changes,
   perform one final review-only verification pass:
   - Write `specs/reviews/code/round-verify-claude-review.md` with a full
     independent review of the diff (no reference to prior rounds)
   - This is the final artifact. Do NOT invoke Codex or perform additional iterations.
```

The `code-fix` case in `build_prompt()` is unchanged — no verify branch is added or removed. Code-stage verification is Claude-only, so `code-fix verify` is never invoked by the workflow. The shell interface technically permits `code-fix verify` calls, but this is tolerated as out of scope for v2.1 (see section 2 and Implementation Notes).

#### E. Add fresh-review instructions for code stage

Add to the code stage section:

```markdown
CRITICAL: Each round must be a full, independent review of the entire diff
against the spec. Do NOT narrow scope to only issues from previous rounds.
Previous findings may have been fixed but new issues may have been introduced.
Review as if seeing the code for the first time each round.

Final verification must be a completely unconstrained full review — ignore
all prior review history and review as if seeing the code for the first time.
```

#### F. Update stage transition commit

The `git add` for stage transition conditionally includes `specs/brainstorm.md`:

```markdown
1. If `brainstorm_done: true` AND `specs/brainstorm.md` exists: `git add specs/brainstorm.md`
2. `git add specs/design.md specs/reviews/design/ .claude/review-loop.log`
3. `git commit -m "review-loop: design stage complete (<session-id>)"`
```

Staging of `specs/brainstorm.md` is gated on both the session flag and file existence. A stale brainstorm file from a previous session (where `brainstorm_done: false`) is never staged.

#### G. Add specs/brainstorm.md to code-stage protected paths

Update the code stage's protected-path rollback logic:

```markdown
- Protected paths: `specs/design.md`, `specs/brainstorm.md`, everything under
  `specs/reviews/`, and any `.claude/*` path that is not session-scoped runtime state
```

Also update the staging exclusions:

```markdown
- `git add -A -- ':!specs/reviews/' ':!specs/brainstorm.md' ':!.claude/'`
- Review `git diff --staged $BASELINE_SHA -- ':!specs/reviews/' ':!specs/brainstorm.md' ':!.claude/'`
```

#### H. Update state file to record starting branch and brainstorm status

Add `start_branch` and `brainstorm_done` fields:

```yaml
---
active: true
session_id: ...
phase: design
round: null
started_at: ...
branch: review-loop/<session-id>
start_branch: main                    # git rev-parse --abbrev-ref HEAD (may be "HEAD" if detached)
start_sha: abc123                     # git rev-parse HEAD (immutable starting commit)
baseline_sha: null
brainstorm_done: false                # set to true only if brainstorming ran in this session
task: "..."
---
```

#### I. Update cancellation flow

Cancellation must read `start_branch` **before** `kill-review.sh` deletes the state file.

In `review-loop/commands/review-loop.md`:

```markdown
## Cancellation

If the user asks to cancel at any point:
1. Read `start_branch`, `start_sha`, and `session_id` from `.claude/review-loop.local.md`
2. Run `review-loop/scripts/kill-review.sh <session-id>`
   (this kills the process and removes runtime files + state file)
3. Discard all uncommitted session changes: `git reset -- . && git checkout -- . && git clean -fd`
4. Check out the starting point:
   - If `start_branch` is not `HEAD`: `git checkout <start_branch>`
   - If `start_branch` is `HEAD` (detached): `git checkout --detach <start_sha>`
5. Delete the session branch: `git branch -D review-loop/<session-id>`

Cancellation means "discard session work." All uncommitted changes are discarded
before branch restoration. Committed work on the session branch is lost when the
branch is deleted.
```

In `review-loop/commands/cancel-review.md` (new change):

```markdown
## Steps

1. Read `.claude/review-loop.local.md` and extract `session_id`, `start_branch`, and `start_sha`.
2. Run `review-loop/scripts/kill-review.sh <session_id>`.
3. Discard uncommitted changes: `git reset -- . && git checkout -- . && git clean -fd`.
4. Restore starting point:
   - If `start_branch` is not `HEAD`: `git checkout <start_branch>`
   - If `start_branch` is `HEAD`: `git checkout --detach <start_sha>`
5. Delete the session branch: `git branch -D review-loop/<session-id>`.
6. Tell the user which runtime files were cleaned up and which audit artifacts
   remain in `specs/reviews/`.
```

**Hook-driven cancellation**: The Stop hook calls `kill-review.sh --from-hook`, which deletes the state file immediately. This means hook-driven cancellation does **not** restore `start_branch` or delete the session branch — it only kills the background process and cleans up runtime files. Branch restoration requires explicit cancellation via `/cancel-review` or the cancel flow in `review-loop.md`. This is acceptable because:
- Hook-driven cleanup happens when the Claude Code session ends (not mid-workflow)
- The user can manually switch branches after session end
- Attempting branch operations in a hook is fragile and can conflict with user actions

**Detached HEAD**: The startup checks in `review-loop.md` require a clean worktree but do not require a local branch. `start_branch` stores the output of `git rev-parse --abbrev-ref HEAD` (returns `HEAD` when detached), and `start_sha` stores the immutable commit SHA via `git rev-parse HEAD`. On cancellation from detached HEAD, restoration uses `git checkout --detach <start_sha>` to return to the exact starting commit.

#### J. Update state file phase

The `phase` field uses only three values that the command prompt actually persists:

```markdown
phase: design    # design | code | done
```

The brainstorming step is interactive and completes before the design loop begins — it does not need its own persisted phase.

#### K. Update description frontmatter

Change from "v2" to "v2.1":
```yaml
description: Drive the review-loop v2.1 design and code collaboration flow
```

### 4. `review-loop/AGENTS.md`

**Current state**: Documents two-stage workflow (design + code).

**Changes**: Add brainstorming stage documentation and brainstorming-suppression note for Codex sessions.

```markdown
# review-loop Agents

This plugin coordinates Claude Code and Codex in an optional three-stage workflow.

## Brainstorming stage (optional)

- Runs after branch creation if `superpowers:brainstorming` is available.
- Claude Code invokes the brainstorming skill to explore requirements and constraints.
- Output saved to `specs/brainstorm.md` on the session branch.
- Once complete, `superpowers:brainstorming` is suppressed for the rest of the workflow.

## Design stage

- Claude Code is the author.
- Codex is a read-only auditor.
- Codex must only write the current round review file under `specs/reviews/design/`.
- Each review round is a full, independent audit — reviewers must not narrow scope
  to previously raised issues only.
- Verify rounds receive no prior review context to ensure fresh perspective.
- Do not invoke brainstorming skills — brainstorming has already been completed
  or was intentionally skipped.

## Code stage

- Codex is the implementer.
- Claude Code is the reviewer.
- Codex must not modify `specs/design.md` or `specs/brainstorm.md`.
- Codex must not modify `.claude/` except session-scoped runtime files and the
  current `specs/reviews/code/round-*-codex-response.md` file when asked to
  answer review feedback.
- Each review round is a full, independent review of the entire diff against spec.
- Final verification is Claude-only (no Codex invocation).
- Do not invoke brainstorming skills — brainstorming has already been completed
  or was intentionally skipped.

## General constraints

- Never commit, stage, or reset git state from Codex prompts.
- Keep context limited to the current design plus the current review loop artifacts.
- Preserve all review files as audit records.
- Shared shell helpers live in `review-loop/scripts/common.sh`; runtime scripts
  source it for state lookup, session file paths, and prompt assembly.
- `REVIEW_LOOP_TIMEOUT_SECONDS` may be set for testing or debugging to override
  the default 1200 second watchdog timeout.
```

### 5. `review-loop/prompts/code-implement.md` (new change)

Add brainstorming-suppression instruction to the existing prompt:

```markdown
Do not invoke brainstorming skills. Brainstorming has already been completed
or was intentionally skipped for this session.
```

### 6. `review-loop/prompts/code-fix.md` (new change)

Add the same brainstorming-suppression instruction:

```markdown
Do not invoke brainstorming skills. Brainstorming has already been completed
or was intentionally skipped for this session.
```

### 7. `review-loop/commands/cancel-review.md` (new change)

Update cancellation to restore starting branch and delete session branch:

```markdown
## Steps

1. Read `.claude/review-loop.local.md` and extract `session_id`, `start_branch`, and `start_sha`.
2. Run `review-loop/scripts/kill-review.sh <session_id>`.
3. Discard uncommitted changes: `git reset -- . && git checkout -- . && git clean -fd`.
4. Restore starting point:
   - If `start_branch` is not `HEAD`: `git checkout <start_branch>`
   - If `start_branch` is `HEAD`: `git checkout --detach <start_sha>`
5. Delete the session branch: `git branch -D review-loop/<session-id>`.
6. Tell the user which runtime files were cleaned up and which audit artifacts
   remain in `specs/reviews/`.
```

### 8. `tests/review-loop.test.sh` (new change)

Update existing tests and add new test cases for v2.1 contracts:

**Update existing tests:**
- Tests asserting verify-round prompt includes prior context → update to assert verify strips prior context and prepends FULL INDEPENDENT REVIEW header
- Tests asserting cancel-review.md steps → update for new step order (read state before kill, restore branch, delete branch)

**Add new test cases (prompt-content assertions — testable via shell harness):**
- `test_design_review_verify_prompt_no_prior_context`: call `build_prompt design-review verify` and assert output does not contain "Previous Codex Review" or "Previous Claude Response", and does contain "FULL INDEPENDENT REVIEW"
- `test_design_review_regular_prompt_includes_prior_context`: call `build_prompt design-review 2` and assert output includes previous review/response sections (unchanged behavior)
- `test_brainstorm_md_protected_in_code_stage_exclusions`: verify that the staging exclusion pathspecs documented in the design are used (grep command prompt for `':!specs/brainstorm.md'`)

**Workflow behavior tests (manual verification matrix — not automatable in shell harness):**
The following behaviors are orchestrated by Claude via markdown command instructions, not by shell scripts. They cannot be tested by the shell harness and are verified via the manual verification matrix in the "Verification Scenarios" section:
- `brainstorm_done` flag gating brainstorm usage
- `start_branch` persistence and restoration on cancellation
- Cancellation flow (read state → kill → restore branch → delete branch)

## Implementation Notes

- No new files are created in the plugin directory (only existing files modified)
- No changes to `run-review-bg.sh`, `check-review.sh`, `kill-review.sh`, or `hooks.json`
- The `validate_round()` function in `common.sh` already handles `"verify"` — no change needed
- The state file adds three new fields: `start_branch`, `start_sha`, and `brainstorm_done`
- The `phase` field keeps only the three values the command prompt actually persists: `design`, `code`, `done`
- Brainstorming detection relies on the skills list in system-reminder messages. If this context is unavailable (e.g., truncated conversation), the fallback is to skip brainstorming — the design stage works identically without it.
- The `superpowers:brainstorming` conflict only affects Claude Code (the orchestrator). Codex background sessions launched via `codex exec` do not have superpowers installed. However, AGENTS.md and Codex prompts explicitly suppress brainstorming as defense-in-depth.
- Verify rounds use the `verify` round token with `run-review-bg.sh` for design-review only. Code-stage verification is Claude-only — no `code-fix verify` path.
- The `build_prompt()` function only adds verify-round logic to the `design-review` case. The `code-fix` case is unchanged since `code-fix verify` is never called by the workflow.
- Hook-driven cancellation (Stop hook → `kill-review.sh --from-hook`) does not restore branches — only explicit `/cancel-review` does. This is by design.
- `specs/brainstorm.md` usage and staging are both session-scoped via the `brainstorm_done` flag — a leftover brainstorm file from a previous session cannot bleed into a new one and is not staged at transition.
- `specs/brainstorm.md` is committed at stage transition and preserved (not ephemeral). The brainstorming prompt includes an explicit "no secrets/credentials/API keys" rule. The brainstorming skill itself is interactive and runs under user supervision. These combined controls are proportionate for a session-branch artifact.

## Verification Scenarios

Lightweight manual verification matrix for the new v2.1 branches:

1. **Brainstorming present**: superpowers available → brainstorm.md created → `brainstorm_done: true` set → design uses it as supplementary context → brainstorm.md committed at stage transition → brainstorm.md protected during code stage
2. **Brainstorming absent**: superpowers not available → no brainstorm.md → `brainstorm_done: false` → design uses task description alone → stage transition skips brainstorm.md → code stage unaffected
3. **Stale brainstorm.md**: previous session left brainstorm.md → new session has `brainstorm_done: false` → stale file ignored by design stage
4. **Verify round prompt assembly**: design-review verify → FULL INDEPENDENT REVIEW header, no prior reviews
5. **Code stage verify**: Claude-only review, no Codex invocation, `round-verify-claude-review.md` written
6. **Regular round prompt assembly**: round 2+ → includes previous round's review/response pair (unchanged from v2)
7. **Cancellation with uncommitted changes**: read state, kill review, discard uncommitted changes (`git reset -- . && git checkout -- . && git clean -fd`), restore start_branch/start_sha, delete session branch
8. **Cancellation from detached HEAD**: start_sha used to restore exact commit; `git checkout --detach <start_sha>`
9. **Hook-driven cancellation**: kills process and removes runtime files only; does not restore branches
