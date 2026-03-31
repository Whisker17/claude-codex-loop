# Review Loop v2 — Design Spec

## Overview

Redesign the review-loop plugin to support a two-stage workflow with role separation: Claude Code and Codex 5.4 collaborate through iterative review loops, with each taking turns as author and auditor. The new design replaces the stop-hook mechanism with command-driven execution, and uses background process + polling to eliminate Bash timeout issues.

## Goals

1. **Two-stage workflow**: design review loop + code review loop, with a user gate in between
2. **Role separation**: Claude Code authors design / Codex audits; Codex implements code / Claude Code audits
3. **Eliminate timeout issues**: Codex runs in background, Claude Code polls for completion
4. **Context management**: each round injects only the latest design + previous round's review/response pair
5. **Auditability**: every round produces persistent review and response files

## Non-Goals

- Replacing Codex with other review tools (out of scope for v2)
- Streaming Codex output to the user in real time (sacrificed for timeout reliability)
- Automatic merge to main (user controls branch management after completion)

## Flow

### Stage 1: Design Review Loop (max 5 rounds)

Author: Claude Code | Auditor: Codex

```
1. Preconditions (all checked before creating any state):
   a. Must be inside a Git repository. If not, abort with error:
      "review-loop requires a Git repository. Run git init or cd into a repo."
   b. Working tree must be clean (no uncommitted changes).
      If dirty, abort with error asking user to commit or stash first.
      This check happens before any files are created, so stash is safe.
2. Generate session-id, create state file
3. Create and checkout branch: review-loop/<session-id>
   If branch creation fails (e.g., branch already exists, HEAD is detached
   with no commits), abort and clean up state file.
   (all subsequent work — design artifacts, code changes — stays on this branch;
   the user's original branch is never modified)
4. Claude Code writes design spec -> specs/design.md
5. for round = 1 to 5:
     a. Snapshot worktree state before Codex runs:
        PRE_MODIFIED=$(git diff --name-only)
        PRE_STAGED=$(git diff --cached --name-only)
        PRE_UNTRACKED=$(git ls-files --others --exclude-standard)
     b. Execute: bash run-review-bg.sh design-review $round
        (background Codex to audit specs/design.md)
     c. Poll: bash check-review.sh every 10s until DONE/TIMEOUT/FAILED
     d. Integrity check (runs on EVERY terminal state — DONE, TIMEOUT, FAILED,
        including before retry and before skip):
        Compare post-Codex state against pre-Codex snapshot.
        POST_MODIFIED=$(git diff --name-only)
        POST_STAGED=$(git diff --cached --name-only)
        POST_UNTRACKED=$(git ls-files --others --exclude-standard)
        Compute deltas (files in POST but not in PRE for each category).
        Allowed new files: specs/reviews/design/round-$round-codex-review.md
        For any unauthorized delta:
          - Modified worktree files: git checkout -- <file>
          - Newly staged files that exist in HEAD: git reset HEAD -- <file> && git checkout -- <file>
          - Newly staged files that do NOT exist in HEAD (new files):
            git reset HEAD -- <file> && rm <file>
          - New untracked files: rm <file>
        Log warning for each reverted file.
     e. On TIMEOUT or FAILED: retry once, skip round on second failure
     f. Read specs/reviews/design/round-$round-codex-review.md
     g. If no substantive issues:
        - Write brief response to round-$round-claude-response.md
        - Break loop
     h. If issues exist:
        - Modify specs/design.md to address feedback
        - Write specs/reviews/design/round-$round-claude-response.md
          (what was accepted, modified, or disagreed with and why)
6. Final verification: if the loop exhausted all 5 rounds AND the last round
   modified specs/design.md, run one additional Codex audit pass as a
   "final-verification" step (not counted as a round — uses mode
   "design-review" but state phase = "design-verify"). No further
   modifications are made; if critical issues remain, log them for the
   user to review at the gate.
7. Output: "Design stage complete. Review specs/design.md and confirm."
8. Wait for user confirmation
```

### User Gate

User reviews `specs/design.md` and confirms. Only then does the flow proceed.

### Stage Transition: Design → Code

After user confirms at the gate, Claude Code commits all design-stage artifacts
on the review-loop branch before entering the code stage:

```
1. git add specs/design.md specs/reviews/design/ .claude/review-loop.log
2. git commit -m "review-loop: design stage complete (<session-id>)"
3. Verify the commit succeeded:
   - Success: proceed normally
   - "nothing to commit" (user already committed): proceed, use current HEAD
   - Any other failure (git identity missing, hook rejection, index lock,
     conflict): abort stage transition, output error, ask user to resolve
     manually. Do NOT continue to code stage — the design artifacts are not
     in HEAD and the baseline would be wrong.
4. Record BASELINE_SHA = HEAD
5. Update state file: phase = code, baseline_sha = BASELINE_SHA
```

### Stage 2: Code Review Loop (max 5 rounds)

Author: Codex | Auditor: Claude Code

```
6. BASELINE_SHA already recorded during stage transition
7. Snapshot worktree state before code-implement:
   PRE_MODIFIED=$(git diff --name-only)
   PRE_STAGED=$(git diff --cached --name-only)
   PRE_UNTRACKED=$(git ls-files --others --exclude-standard)
8. Execute: bash run-review-bg.sh code-implement 1
   (Codex implements code based on specs/design.md)
9. Poll until complete
10. Code-stage integrity check (snapshot-delta, same mechanism as design stage):
    Capture POST snapshots, compute deltas against PRE.
    Allowed changes for code-implement mode:
      - Any project source/test files (the intended output)
      - .claude/review-loop-$SESSION_ID.* (session runtime files)
    Prohibited (revert if found in delta):
      - specs/design.md
      - specs/reviews/**
      - .claude/* except .claude/review-loop-$SESSION_ID.*
    Revert logic: same as design stage (worktree→checkout, staged existing→
    reset+checkout, staged new→reset+rm, untracked→rm). Log warning.
11. for round = 1 to 5:
     a. Snapshot worktree state before each review cycle:
        PRE_MODIFIED, PRE_STAGED, PRE_UNTRACKED (same as step 7)
     b. Stage all changes for review visibility:
        git add -A -- ':!specs/reviews/' ':!.claude/'
        (stages new + modified files, excludes review artifacts and runtime files)
     c. Claude Code reviews scoped diff:
        git diff --staged $BASELINE_SHA -- ':!specs/reviews/' ':!.claude/'
        (--staged ensures newly created files are included in the diff)
     d. git reset HEAD (unstage, so Codex can continue working on worktree)
     e. Write specs/reviews/code/round-$round-claude-review.md
     f. If no substantive issues: break loop
     g. Execute: bash run-review-bg.sh code-fix $round
        (Codex reads current round's claude-review and fixes code)
     h. Poll until complete
     i. Code-stage integrity check (snapshot-delta against step a's PRE):
        Allowed changes for code-fix mode:
          - Any project source/test files
          - .claude/review-loop-$SESSION_ID.*
          - specs/reviews/code/round-$round-codex-response.md (Codex's response)
        Prohibited (revert if found): specs/design.md, other specs/reviews/**,
        .claude/* except session files. Log warning for each reverted file.
     j. Codex writes specs/reviews/code/round-$round-codex-response.md
11. Final verification: if the loop exhausted all 5 rounds AND the last
    round had Codex fix code, Claude Code performs one additional review
    pass as a "final-verification" step (not counted as a round — state
    phase = "code-verify"). No further fixes are requested; if critical
    issues remain, log them in the output for user decision.
12. Output: "Implementation complete. All changes on branch review-loop/<session-id>."
```

Note: Round 1 starts from Claude Code's first review of Codex's initial implementation. The initial implementation itself is not counted as a round.

## File Structure

### Plugin files

```
review-loop/
├── scripts/
│   ├── run-review-bg.sh          # Background-launch Codex (audit or implement)
│   ├── check-review.sh           # Poll sentinel, return status
│   └── kill-review.sh            # Kill background process group on timeout/cancel
├── prompts/
│   ├── design-review.md          # Codex prompt: audit design spec
│   ├── code-implement.md         # Codex prompt: implement code from spec
│   └── code-fix.md               # Codex prompt: fix code per review feedback
├── commands/
│   ├── review-loop.md            # Main slash command (drives entire flow)
│   └── cancel-review.md          # Cancel command
├── hooks/
│   └── hooks.json                # Lightweight stop hook for cleanup only
└── AGENTS.md
```

### Runtime files (in user's project)

```
specs/
├── design.md                                 # Design document (single file, iteratively refined)
└── reviews/
    ├── design/
    │   ├── round-1-codex-review.md           # Round 1: Codex's audit of design
    │   ├── round-1-claude-response.md        # Round 1: Claude Code's response to audit
    │   ├── round-2-codex-review.md
    │   ├── round-2-claude-response.md
    │   └── ...
    └── code/
        ├── round-1-claude-review.md          # Round 1: Claude Code's audit of code
        ├── round-1-codex-response.md         # Round 1: Codex's response to audit
        ├── round-2-claude-review.md
        ├── round-2-codex-response.md
        └── ...

.claude/
├── review-loop.local.md                      # State file (contains session-id)
├── review-loop-<session-id>.pid              # Background Codex PID (session-scoped)
├── review-loop-<session-id>.sentinel         # Completion marker (session-scoped)
├── review-loop-<session-id>-codex-output.log # Codex stdout/stderr (session-scoped)
└── review-loop.log                           # Telemetry log (append-only, shared)
```

## Background Execution & Polling

### run-review-bg.sh

```
Input:
  $1 = mode (design-review | code-implement | code-fix)
  $2 = round number (1-5) or "verify" (for final verification pass)

Logic:
  1. Read prompt template from prompts/$mode.md (relative to plugin root)
  2. Inject context files into prompt:
     - design-review: specs/design.md + previous round's review & response (if any)
     - code-implement: specs/design.md + previous round's review & response (if any)
     - code-fix: specs/design.md + current round's claude-review + previous round's codex-response (if any)
  3. Remove stale sentinel/pid files for this session before launching
  4. Launch Codex in background:
     nohup codex exec -C "$PROJECT_ROOT" --full-auto "$PROMPT" \
       > .claude/review-loop-$SESSION_ID-codex-output.log 2>&1 &
     Flags:
       -C "$PROJECT_ROOT"  — ensure correct working directory
       --full-auto          — skip interactive approval prompts
     The prompt itself instructs Codex to write output to the expected
     review/response file path. check-review.sh performs mode-specific
     validation after DONE (see check-review.sh for details).
  5. Write PID to .claude/review-loop-$SESSION_ID.pid
  6. Start watchdog: kill process group after 1200s (20 min), write "timeout" to sentinel
  7. Return immediately
```

Watchdog implementation:

```bash
# Launch Codex in its own process group (set -m or setsid)
setsid codex exec -C "$PROJECT_ROOT" --full-auto "$PROMPT" \
  > ".claude/review-loop-$SESSION_ID-codex-output.log" 2>&1 &
PGID=$!

# Watchdog kills entire process group
( sleep 1200 && kill -- -$PGID 2>/dev/null && echo "timeout" > ".claude/review-loop-$SESSION_ID.sentinel" ) &
```

When Codex completes normally, a wrapper writes `echo "done" > ".claude/review-loop-$SESSION_ID.sentinel"`. The watchdog's kill is harmless if the process group already exited. Using process-group kill ensures child processes (tests, sub-shells) spawned by Codex are also terminated.

### check-review.sh

```
Input:
  $1 = session-id
  $2 = mode (design-review | code-implement | code-fix)
  $3 = round number

Single invocation, returns immediately:
  1. Read .claude/review-loop-$SESSION_ID.pid, check if process is alive
  2. Check .claude/review-loop-$SESSION_ID.sentinel:
     - Exists, content = "done"    -> proceed to step 3
     - Exists, content = "timeout" -> stdout: TIMEOUT,  exit 1
     - Missing, process alive      -> stdout: RUNNING,  exit 2
     - Missing, process dead       -> stdout: FAILED,   exit 3
  3. On DONE, validate completion per mode:
     - design-review: verify specs/reviews/design/round-$round-codex-review.md exists
     - code-fix: verify specs/reviews/code/round-$round-codex-response.md exists
     - code-implement: skip file check (output is project file changes, not a
       single artifact); sentinel=done + clean exit is sufficient
     If validation fails -> stdout: FAILED, exit 3
     If validation passes -> stdout: DONE, exit 0
```

### Claude Code polling pattern (guided by slash command prompt)

```
Loop: call bash check-review.sh $SESSION_ID $MODE $ROUND every 10 seconds
  DONE    -> read review file, proceed to next step
  TIMEOUT -> retry once (re-run run-review-bg.sh), skip on second timeout
  RUNNING -> continue polling
  FAILED  -> retry once, skip on second failure
```

## Prompt Templates

### prompts/design-review.md

Codex audits Claude Code's design document.

```
Role: Independent design auditor (READ-ONLY role)
Task: Audit the following design document

Audit criteria:
- Requirements completeness: all use cases and edge cases covered
- Technical feasibility: implementation risks, blockers
- Architecture: module boundaries, dependencies, interface design
- Security: potential vulnerabilities
- Testability: can the design be verified

Constraints:
- You MUST NOT modify any files except your review output file
- Do not modify specs/design.md, source code, tests, or configuration
- Do not run git commit, git add, or any git write operations

Injected context:
- specs/design.md (full content)
- Previous round's codex-review + claude-response (if applicable)

Output requirements:
- Each issue: severity (critical/high/medium/low), description, recommendation
- Write ONLY to specs/reviews/design/round-{N}-codex-review.md
```

### prompts/code-implement.md

Codex implements code based on the design spec.

```
Role: Code implementer
Task: Implement code per the design document

Requirements:
- Follow the spec's architecture and interfaces strictly
- Write clear, testable code with necessary tests
- Work on the development branch only
- Do not modify specs/ directory or .claude/ directory

Injected context:
- specs/design.md (full content)

Output:
- Create/modify files directly in the project
  (Claude Code handles staging for review visibility; Codex should not
  commit or stage files itself)
```

### prompts/code-fix.md

Codex fixes code based on Claude Code's review.

```
Role: Code implementer addressing audit feedback
Task: Read the review, fix code issues, write response

Injected context:
- specs/design.md (full content)
- Current round's claude-review (round-{N}-claude-review.md)
- Previous round's codex-response (if applicable, from round 2+)

Constraints:
- Do not modify specs/ directory or .claude/ directory (except the response file below)
- Do not run git commit, git add, or git stage — Claude Code handles staging
  for review visibility; Codex must not commit or stage files itself

Execution:
- For each issue: independently decide whether to agree
- Agreed: fix the code
- Disagreed: explain reasoning in response
- Write response to specs/reviews/code/round-{N}-codex-response.md
```

### Claude Code's review (no template needed)

Claude Code performs code review directly in the conversation — temporarily stages all changes (`git add -A`), reads scoped diff (`git diff --staged $BASELINE_SHA -- ':!specs/reviews/' ':!.claude/'`), then unstages (`git reset HEAD`). This ensures newly created files are included in the diff. Writes review to `specs/reviews/code/round-{N}-claude-review.md`. The response file `round-{N}-claude-response.md` in the design stage is also written directly by Claude Code.

## Context Management

Each round of Codex invocation receives a fresh context containing only:

1. `specs/design.md` (always present, latest version)
2. For design-review: previous round's codex-review + claude-response (if any)
3. For code-fix: **current** round's claude-review + previous round's codex-response (if any)

For Claude Code, the slash command prompt instructs it to only read the latest two reports when starting a new round, not the full history. The system's automatic context compression handles older messages naturally.

## State Management

### State file: `.claude/review-loop.local.md`

```yaml
---
active: true
session_id: 20260320-143022-a1b2c3
phase: design                                  # design | design-verify | gate | code | code-verify | done
round: 2                                       # current round 1-5 (null during verify phases)
started_at: 2026-03-20T14:30:22Z
branch: review-loop/20260320-143022-a1b2c3     # set at startup (branch created before design stage)
baseline_sha: abc123def                        # HEAD after design commit, set at stage transition
task: "user's task description"
---
```

Phase transitions: `design -> [design-verify] -> gate -> code -> [code-verify] -> done`

The `*-verify` phases are optional — they only occur when all 5 rounds are exhausted with unreviewed changes. During verify phases, `round` is set to `null`.

## Error Handling

Principle: **fail-open, never trap the user**.

| Scenario | Handling |
|----------|----------|
| Not a Git repository | Abort before creating state; ask user to run git init or cd into a repo |
| Branch creation fails | Abort, clean up state file; ask user to resolve (e.g., existing branch, detached HEAD) |
| Codex not installed | Check at startup, error and exit without creating state |
| Codex 20min timeout | Kill process group, auto-retry once, skip round on second timeout |
| Codex process crash | check-review.sh returns FAILED, retry once, skip on second failure |
| Review file not generated | Treat as FAILED, same as above |
| State file corrupted | Clean up all temp files, allow exit |
| User runs /cancel-review | Kill background process group, clean up state and session temp files |
| Working tree dirty at startup | Abort before creating any state; ask user to commit or stash |
| Design commit: "nothing to commit" | Non-fatal; user already committed, use current HEAD as baseline |
| Design commit: any other failure | Abort stage transition; output error, ask user to resolve manually |
| Design-review writes unauthorized files | Detect via pre/post snapshot delta; revert worktree, staged (existing→checkout, new→rm), and untracked; log warning; continue |
| Code-implement/fix modifies protected paths | Detect via pre/post snapshot delta with mode-specific allowlist; revert and log warning |
| 5-round limit reached | Enter *-verify phase (review-only), then end stage |

## Cleanup

Cleaned up on completion or cancellation:
- `.claude/review-loop.local.md`
- `.claude/review-loop-<session-id>.pid`
- `.claude/review-loop-<session-id>.sentinel`
- `.claude/review-loop-<session-id>-codex-output.log`

Preserved as records:
- `specs/design.md`
- `specs/reviews/**` (all review and response files)
- `.claude/review-loop.log` (telemetry)

## Migration from v1

v2 is a full rewrite. Key differences from v1:

| Aspect | v1 | v2 |
|--------|----|----|
| Trigger | Stop hook intercepts exit | Command-driven, Claude Code calls scripts proactively |
| Codex execution | Synchronous Bash call | Background process + polling |
| Stages | Single (code review only) | Two stages (design + code) |
| Roles | Claude Code implements, Codex reviews | Stage-dependent role swap |
| Review rounds | Single pass | Up to 5 rounds per stage |
| Timeout | Bash tool timeout (unreliable) | 20min watchdog per round with retry |
| Context | Accumulated in conversation | Fresh per round, only previous round's pair |
| Branch | Works on current branch | Creates dedicated branch at startup (both stages) |
| User involvement | None after start | Gate between design and code stages |
