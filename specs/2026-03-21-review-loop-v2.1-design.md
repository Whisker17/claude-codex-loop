# Review Loop v2.1 — Design Spec

## Summary

This is an incremental iteration on the v2 design (`specs/2026-03-20-review-loop-v2-design.md`). It addresses two issues discovered in production use:

1. **Attention narrowing**: review rounds progressively narrow scope to previously found issues, causing the final "APPROVED" to mean "those specific issues are fixed" rather than "the document is clean."
2. **Superpowers conflict**: when the `superpowers:brainstorming` skill is installed, it intercepts the design-writing step and breaks the review-loop pipeline.

## Changes from v2

| Area | v2 | v2.1 |
|------|-----|------|
| Stages | 2 (design + code) | 2 + optional brainstorming (brainstorm? → design → code) |
| Brainstorming | Not addressed | Optional first stage; uses superpowers if available, skips if not |
| Review scope | Implicit full review each round | Explicit full independent review mandate each round |
| Verify rounds | Same prompt as regular rounds | Unconstrained prompt, no prior review context |
| Review output format | Flat list of issues | Separated into "previously identified" and "newly identified" |

---

## Change 1: Optional Brainstorming Stage

### Problem

The `superpowers:brainstorming` skill triggers automatically before "creative work." When review-loop enters its design stage and starts writing `specs/design.md`, brainstorming intercepts with interactive Q&A, breaking the automated pipeline. Meanwhile, not all users have superpowers installed.

### Design

Brainstorming becomes an **optional first stage** that runs before any state or branch creation.

#### Detection

The review-loop command prompt instructs Claude Code to check whether `superpowers:brainstorming` is listed in the available skills (visible in system-reminder messages at conversation start).

- **Available**: invoke the brainstorming skill with the user's task description. Save output to `specs/brainstorm.md`. Wait for user confirmation before proceeding.
- **Not available**: skip directly to state/branch creation and the design stage. The user's task description is the sole input.

#### Skill suppression

After the brainstorming stage completes (or is skipped), the `superpowers:brainstorming` skill MUST NOT be re-invoked for the remainder of the workflow. This is declared in the review-loop command prompt. Other superpowers skills (TDD, debugging, etc.) remain available during the code stage.

#### Conditional design input

The design stage uses `specs/brainstorm.md` as primary input **if the file exists**. Otherwise it works from the task description alone. This is expressed as:

```
1. Write `specs/design.md`:
   - If `specs/brainstorm.md` exists, use it as the primary input.
   - Otherwise, use the task description from the state file.
```

#### Phase transitions

The `brainstorm` phase is optional. Two valid flows:

```
With superpowers:    brainstorm → design → [design-verify] → gate → code → [code-verify] → done
Without superpowers: design → [design-verify] → gate → code → [code-verify] → done
```

The state file's `phase` field starts at `brainstorm` when superpowers is detected, or `design` when it is not.

#### Artifacts

When brainstorming runs, `specs/brainstorm.md` is:
- Created before branch creation (in the project root)
- Committed alongside design artifacts during stage transition: `git add specs/brainstorm.md specs/design.md specs/reviews/design/ .claude/review-loop.log`
- Preserved on cleanup (not deleted)

When brainstorming is skipped, `specs/brainstorm.md` does not exist and is not referenced.

---

## Change 2: Fresh Independent Review Each Round

### Problem

In iterative review loops, each round's prompt naturally anchors the reviewer on previously found issues. The pattern observed in production:

| Round | Effective prompt | Result |
|-------|-----------------|--------|
| 1 | "Full review of the spec" | 10 issues found |
| 2 | "Verify these 10 issues" | Attention locked on old issues, 3 new ones found incidentally |
| 3 | "Verify these 3 issues, only critical/high" | Nearly no broad review, APPROVED |

The final APPROVED means "those specific issues are fixed," not "the document is clean." A fresh Codex session without this anchoring easily finds issues the loop missed.

### Design

Two complementary fixes applied to both design-review (Codex reviews) and code-review (Claude Code reviews) stages.

#### Fix A: Prompt-level full review mandate

The `design-review.md` prompt template now explicitly states:

> CRITICAL: Every round is a full audit. You must review the entire document as if seeing it for the first time. Previous review context (if provided below) is supplementary — use it only to verify that previously identified issues were addressed, but you MUST also examine all other aspects of the document for new issues. Do NOT limit your review scope to previously raised issues.

Additional audit criteria added:
- Interface consistency (naming, payload shapes, list/detail parity)
- Completeness of new additions (changes addressing prior feedback may introduce new gaps)

Output format requires separating "previously identified (now fixed/still open)" from "newly identified" issues.

#### Fix B: Verify rounds strip prior context

The `build_prompt()` function in `common.sh` now behaves differently for verify rounds (`round == "verify"`):

1. **Prepends** a "FULL INDEPENDENT REVIEW" header:
   > This is a final verification pass. You MUST perform a complete, independent review of the entire document from scratch. Ignore all prior review history. Review as if seeing this document for the first time.

2. **Omits** all prior review context (previous codex-review, claude-response, codex-response). Only the design document (or code diff) is included.

For regular rounds (1-5), previous round context is still included to help verify fixes, but the template instructions prevent scope narrowing.

#### Fix C: Claude Code orchestrator instructions

The `review-loop.md` command prompt now explicitly instructs Claude Code during the code stage:

> CRITICAL: Each round must be a full, independent review of the entire diff against the spec. Do NOT narrow scope to only issues from previous rounds. Previous findings may have been fixed but new issues may have been introduced. Review as if seeing the code for the first time each round.

The final verification is marked as:

> This verification must be a completely unconstrained full review — ignore all prior review history and review as if seeing the code for the first time.

---

## Updated File Structure

### Plugin files (unchanged from v2)

```
review-loop/
├── scripts/
│   ├── run-review-bg.sh
│   ├── check-review.sh
│   ├── kill-review.sh
│   └── common.sh
├── prompts/
│   ├── design-review.md          # Updated: full independent review mandate
│   ├── code-implement.md         # Unchanged
│   └── code-fix.md               # Unchanged
├── commands/
│   ├── review-loop.md            # Updated: brainstorming stage + fresh review instructions
│   └── cancel-review.md          # Unchanged
├── hooks/
│   └── hooks.json                # Unchanged
└── AGENTS.md                     # Updated: brainstorming stage documented
```

### Runtime files (in user's project)

```
specs/
├── brainstorm.md                             # (optional) Brainstorming output from superpowers
├── design.md                                 # Design document (iteratively refined)
└── reviews/
    ├── design/
    │   ├── round-1-codex-review.md           # Now: separated "previously identified" / "newly identified"
    │   ├── round-1-claude-response.md
    │   └── ...
    └── code/
        ├── round-1-claude-review.md          # Now: separated "previously identified" / "newly identified"
        ├── round-1-codex-response.md
        └── ...

.claude/
├── review-loop.local.md                      # phase now starts at brainstorm or design
└── (other session files unchanged)
```

---

## Updated State Management

### State file: `.claude/review-loop.local.md`

```yaml
---
active: true
session_id: 20260321-100000-x1y2z3
phase: brainstorm                              # brainstorm | design | design-verify | gate | code | code-verify | done
round: null                                    # null during brainstorm, 1-5 during loop, null during verify
started_at: 2026-03-21T10:00:00Z
branch: review-loop/20260321-100000-x1y2z3
baseline_sha: null                             # set at stage transition
task: "user's task description"
---
```

Phase transitions:

```
[brainstorm] → design → [design-verify] → gate → code → [code-verify] → done
 (optional)              (optional)                       (optional)
```

---

## Updated Flow

### Stage 0: Brainstorming (optional, interactive)

```
0. Check if superpowers:brainstorming skill is listed in available skills.
   a. If available:
      - Invoke the brainstorming skill with the user's task description
      - Brainstorming explores requirements, constraints, edge cases, tradeoffs
      - Save output to specs/brainstorm.md
      - Wait for user confirmation that brainstorming is complete
      - Suppress superpowers:brainstorming for the rest of the workflow
   b. If not available:
      - Skip directly to Stage 1
      - The user's task description is the sole design input
```

### Stage 1: Design Review Loop (unchanged flow, updated prompts)

```
1. Preconditions (same as v2)
2. Generate session-id, create state file (phase = design)
3. Create and checkout branch
4. Write specs/design.md
   - If specs/brainstorm.md exists: use it as primary input
   - Otherwise: use task description from state file
5. For round = 1 to 5:
   a. Snapshot worktree
   b. Execute design-review via Codex
      (Codex prompt now mandates full independent review each round)
   c. Poll, integrity check, retry logic (unchanged)
   d. Read review — expect both "previously identified" and "newly identified" sections
   e. If no substantive issues: write response, break
   f. Otherwise: update design, write response
6. Final verification (if needed):
   - Prompt prepends FULL INDEPENDENT REVIEW header
   - Omits all prior review context
   - Codex reviews document completely fresh
7. Output: "Design stage complete. Review specs/design.md and confirm."
```

### User Gate (unchanged)

### Stage Transition (updated commit)

```
1. git add specs/brainstorm.md specs/design.md specs/reviews/design/ .claude/review-loop.log
   (specs/brainstorm.md is silently skipped by git add if it doesn't exist)
2-5. (same as v2)
```

### Stage 2: Code Review Loop (unchanged flow, updated review instructions)

```
Each Claude Code review round:
- MUST be a full, independent review of the entire diff against spec
- MUST NOT narrow scope to previous findings only
- Output separates "previously identified" from "newly identified"

Final verification:
- Completely unconstrained — ignore all prior review history
```

---

## Updated Prompt Templates

### prompts/design-review.md

```
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

Injected context:
- specs/design.md (full content, always)
- Previous round's codex-review + claude-response (rounds 2-5 only; omitted
  for verify rounds)
- Verify rounds: prepended with FULL INDEPENDENT REVIEW header, no prior context

Output requirements:
- Each issue: severity (critical/high/medium/low), description, recommendation
- Clearly separate "previously identified (now fixed/still open)" from
  "newly identified" issues
- Write ONLY to specs/reviews/design/round-{N}-codex-review.md
```

### prompts/code-implement.md (unchanged)

### prompts/code-fix.md (unchanged)

### build_prompt() behavior (common.sh)

```
For all modes:
  - If round == "verify":
    1. Prepend FULL INDEPENDENT REVIEW header
    2. Skip all previous review context injection
  - If round is numeric (1-5):
    1. Include previous round context as before
    2. Template instructions prevent scope narrowing

For design-review:
  - Verify: design document only, no prior reviews
  - Regular: design document + previous round's review/response pair

For code-fix:
  - Verify: current claude-review only, no prior codex-response
  - Regular: current claude-review + previous round's codex-response
```

---

## Migration from v2

This is a backwards-compatible iteration. No structural changes to scripts, state file format, or file layout. Changes are limited to:

1. **Prompt content**: `design-review.md` updated with stronger review instructions
2. **Prompt assembly**: `build_prompt()` in `common.sh` strips prior context for verify rounds
3. **Command prompt**: `review-loop.md` gains brainstorming stage and fresh-review instructions
4. **Documentation**: `AGENTS.md` updated to reflect three-stage workflow

Existing v2 sessions in progress are unaffected — the state file format is unchanged, and the new prompt behavior only applies to newly launched rounds.
