# Independent Validation Round — Implementation Design

## Overview

Add an independent validation sub-phase to both the design and code stages of review-loop. After the existing Claude-Codex review loop converges, a fresh Codex instance with zero shared review history re-examines the output using a different prompt focused on blind spots that collaborative review tends to miss. If validation finds issues, they are fed back into the regular review loop for another round of fixes before re-validation.

## Problem

Claude and Codex converge during iterative review (agreeing there are no remaining substantive issues), but independent post-hoc review still finds entirely new categories of problems. The two reviewers, operating under the same prompt framework with shared context, develop overlapping attention patterns — certain dimensions are never covered across any round.

## Design Principles

1. **Context isolation** — the independent reviewer sees only the output artifact (design doc or code diff) and the task description, with zero review history. Isolation is enforced at both the prompt layer (no review history injected) and the prompt instruction layer (explicit prohibition on reading review files from the workspace, including `specs/reviews/validation/` from prior cycles).
2. **Perspective diversity** — prompt templates focused specifically on dimensions that collaborative review tends to miss
3. **Minimal architecture change** — reuse existing `run-review-bg.sh` / `check-review.sh` infrastructure; add new prompt templates and modes only

## Artifact Naming Convention

All validation artifacts use a compact `c<cycle>` prefix to prevent naming collisions across validation cycles and with main review loop artifacts. Fix loop artifacts use `c<cycle>f<fix-round>` naming:

- Validation reviews: `design-c<cycle>-review.md`, `code-c<cycle>-review.md`
- Validation responses: `design-c<cycle>-response.md`
- Claude triage reviews: `code-c<cycle>-claude-review.md`
- Claude per-fix-round reviews: `code-c<cycle>f<fix-round>-claude-review.md`
- Design fix reviews from Codex: `design-c<cycle>f<fix-round>-codex-review.md`
- Code fix responses from Codex: `code-c<cycle>f<fix-round>-codex-response.md`

All under `specs/reviews/validation/`.

The round parameter passed to `run-review-bg.sh` and `build_prompt()` uses the composite token `c<cycle>` for validation rounds and `c<cycle>f<fix-round>` for fix rounds. The `validate_round()` function is updated to accept these tokens in addition to integers 1-5 and "verify".

## Validation and Verify Round Ordering

Independent validation runs **before** the existing verify round, not after it. The verify round remains the absolute terminal review pass.

### Design stage — complete algorithm

```
1. Regular design review loop (max 5 rounds) → converge or exhaust
2. Independent validation (max 2 cycles)
3. Verify round trigger: if (regular loop used all 5 rounds AND last round changed design)
   OR (any validation cycle changed design), run verify
4. User gate
   - If unresolved validation findings OR validation was skipped due to infrastructure failure:
     Output: "Design stage complete with unresolved validation findings.
     Review specs/design.md and specs/reviews/validation/ before confirming."
   - Otherwise:
     Output: "Design stage complete. Review specs/design.md and confirm."
```

### Code stage — complete algorithm

```
1. Regular code review loop (max 5 rounds) → converge or exhaust
2. Independent validation (max 2 cycles)
3. Verify round trigger: if (regular loop used all 5 rounds AND last round required code changes)
   OR (any validation cycle required code changes), run Claude-only verify
4. Completion
   - If unresolved validation findings OR validation was skipped due to infrastructure failure:
     Output: "Implementation complete with unresolved validation findings.
     Review specs/reviews/validation/ for details.
     All changes on branch review-loop/<session-id>."
   - Otherwise:
     Output: "Implementation complete. All changes on branch review-loop/<session-id>."
```

The verify round's "do NOT make further edits" and "do NOT invoke Codex" semantics are preserved — they apply only after all validation is complete.

## File Changes

### 1. New file: `review-loop/prompts/independent-design-review.md`

Independent validation prompt for design documents. Focuses on blind spots in collaborative design review.

```markdown
Role: Independent design validator (READ-ONLY role)
Task: Perform a completely independent review of the following design document.

CRITICAL: You are an independent validator. You have NOT participated in any
prior review of this document. You have NOT seen any prior review history.
Your job is to find problems that a collaborative, iterative review process
is likely to miss.

Collaborative reviews tend to develop shared assumptions over multiple rounds.
Focus specifically on:

- Assumptions stated as facts without validation
- Edge cases acknowledged but dismissed as "unlikely"
- Interfaces that are internally consistent but may break under real-world
  usage patterns
- Requirements that may have been implicitly dropped during iterative refinement
- Cross-cutting concerns (observability, deployment, rollback) that nobody owns
- Implicit dependencies between components that are not documented
- Error handling paths that are described in general terms but lack specifics

Constraints:
- You MUST NOT modify any files except your review output file
- Do not modify specs/design.md, source code, tests, or configuration
- Do not run git commit, git add, or any git write operations
- Do NOT reference or assume knowledge of any prior review rounds
- Do NOT read or access any files under specs/reviews/ (including
  specs/reviews/design/, specs/reviews/code/, and specs/reviews/validation/)
  or .claude/. Your review must be based solely on the design document and
  task description provided in this prompt.

Output requirements:
- Each issue: severity (critical/high/medium/low), description, recommendation
- For each issue, include a judgement: "likely missed by iterative review because: ..."
- Write ONLY to specs/reviews/validation/design-{{ROUND}}-review.md

The runtime context is appended below.
```

### 2. New file: `review-loop/prompts/independent-code-review.md`

Independent validation prompt for code changes. Focuses on implementation-level blind spots.

```markdown
Role: Independent code validator (READ-ONLY role)
Task: Perform a completely independent review of the following code changes
against the design specification.

CRITICAL: You are an independent validator. You have NOT participated in any
prior review of this code. You have NOT seen any prior review history.
Your job is to find problems that a collaborative, iterative review process
is likely to miss.

Collaborative code reviews tend to focus on whether the code matches the spec
and whether previously identified issues are fixed. They often miss:

- Unhandled error paths and failure modes
- Security vulnerabilities (injection, path traversal, race conditions)
- Deployment and rollback risks
- Deviations from the spec that were silently accepted
- Resource leaks and cleanup paths
- Edge cases in input validation and boundary conditions
- Cross-cutting concerns (logging, monitoring, graceful degradation)

Constraints:
- You MUST NOT modify any files except your review output file
- Do not modify source code, tests, specs, or configuration
- Do not run git commit, git add, or any git write operations
- Do NOT reference or assume knowledge of any prior review rounds
- Do NOT read or access any files under specs/reviews/ (including
  specs/reviews/design/, specs/reviews/code/, and specs/reviews/validation/)
  or .claude/. Your review must be based solely on the design document,
  code diff, and task description provided in this prompt.

Output requirements:
- Each issue: severity (critical/high/medium/low), description, recommendation
- For each issue, include a judgement: "likely missed by iterative review because: ..."
- Write ONLY to specs/reviews/validation/code-{{ROUND}}-review.md

The runtime context is appended below.
```

### 3. New file: `review-loop/prompts/validation-fix.md`

Prompt for Codex to fix issues found by independent validation during the code stage.

```markdown
Role: Code implementer
Task: Fix the issues identified by independent validation review.

IMPORTANT: These issues were found by an independent reviewer who examined the
code with fresh eyes, without any prior review context. They represent blind
spots that the regular review process missed. Treat them seriously.

The validation review and Claude's review are included below. If a "Previous
Claude Fix Review" section is present, it is the authoritative guide for what
still needs fixing — it supersedes the initial triage. Otherwise, follow the
initial Claude triage review. For each fix:
- Explain what you changed and why
- Ensure the fix does not introduce regressions

Constraints:
- Do not modify specs/design.md, specs/brainstorm.md, or anything under specs/reviews/
  except your designated output file
- Do not modify .claude/* except session-scoped runtime files
- Do not run git commit, git add, or any git write operations
- Do not invoke brainstorming skills

Write your response to specs/reviews/validation/code-{{ROUND}}-codex-response.md

The runtime context is appended below.
```

### 4. New file: `review-loop/prompts/validation-design-fix.md`

Prompt for Codex to review design fixes made in response to independent validation findings.

```markdown
Role: Independent design auditor (READ-ONLY role)
Task: Review the design document after it was updated to address findings from
an independent validation review.

The validation review that triggered these changes is included below. Verify
that the identified issues have been properly addressed and check for any new
issues introduced by the fixes.

CRITICAL: Every round is a full audit. You must review the entire document as
if seeing it for the first time. The validation findings below are context for
understanding what was changed, but you MUST also examine all other aspects of
the document for new issues.

Audit criteria:
- Requirements completeness: all use cases and edge cases covered
- Technical feasibility: implementation risks, blockers
- Architecture: module boundaries, dependencies, interface design
- Security: potential vulnerabilities
- Testability: can the design be verified
- Interface consistency: naming, payload shapes, list/detail parity
- Completeness of fixes: changes addressing validation feedback may
  introduce new gaps

Constraints:
- You MUST NOT modify any files except your review output file
- Do not modify specs/design.md, source code, tests, or configuration
- Do not run git commit, git add, or any git write operations
- Do NOT read or access any files under specs/reviews/design/,
  specs/reviews/code/, or .claude/. The only specs/reviews/ content you
  should use is the validation findings provided in this prompt.
  Do NOT read specs/reviews/validation/ files directly — all relevant
  validation context is already included in this prompt.

Output requirements:
- Each issue: severity (critical/high/medium/low), description, recommendation
- Separate "validation issues (now fixed/still open)" from "newly identified" issues
- Write ONLY to specs/reviews/validation/design-{{ROUND}}-codex-review.md

The runtime context is appended below.
```

### 5. Modified: `review-loop/scripts/common.sh`

#### `validate_mode()` — add 4 new modes

```bash
review_loop::validate_mode() {
  local mode="$1"
  case "$mode" in
    design-review|code-implement|code-fix|\
    independent-design-review|independent-code-review|\
    validation-fix|validation-design-fix)
      ;;
    *)
      printf 'Unsupported mode: %s\n' "$mode" >&2
      exit 1
      ;;
  esac
}
```

#### `validate_round()` — accept validation round tokens

```bash
review_loop::validate_round() {
  local round="$1"
  if review_loop::is_integer "$round"; then
    if (( round >= 1 && round <= 5 )); then
      return 0
    fi
  fi
  if [[ "$round" == "verify" ]]; then
    return 0
  fi
  if [[ "$round" =~ ^c[12]$ ]]; then
    return 0
  fi
  if [[ "$round" =~ ^c[12]f[12]$ ]]; then
    return 0
  fi
  printf 'Unsupported round: %s\n' "$round" >&2
  exit 1
}
```

#### `expected_output_path()` — add 4 new cases

```bash
independent-design-review)
  printf 'specs/reviews/validation/design-%s-review.md\n' "$round"
  ;;
independent-code-review)
  printf 'specs/reviews/validation/code-%s-review.md\n' "$round"
  ;;
validation-fix)
  printf 'specs/reviews/validation/code-%s-codex-response.md\n' "$round"
  ;;
validation-design-fix)
  printf 'specs/reviews/validation/design-%s-codex-review.md\n' "$round"
  ;;
```

#### New helper: `append_diff_section()`

Assembles a diff that includes both tracked changes and untracked new files, matching the semantics of the regular code review path. Uses a temporary index to avoid mutating the real staging area.

```bash
review_loop::append_diff_section() {
  local title="$1"
  local baseline_sha="$2"
  local diff
  local tmp_index

  # Create a temporary index to stage all changes without affecting the real index
  tmp_index="$(mktemp "${TMPDIR:-/tmp}/review-loop-diff-idx.XXXXXX")"
  trap "rm -f '$tmp_index'" RETURN

  # Copy current HEAD tree into temp index, then add all working tree changes
  GIT_INDEX_FILE="$tmp_index" git read-tree HEAD
  GIT_INDEX_FILE="$tmp_index" git add -A -- ':!specs/reviews/' ':!specs/brainstorm.md' ':!.claude/'

  diff="$(GIT_INDEX_FILE="$tmp_index" git diff --cached "$baseline_sha" -- ':!specs/reviews/' ':!specs/brainstorm.md' ':!.claude/')"
  rm -f "$tmp_index"
  trap - RETURN

  [[ -n "$diff" ]] || return 0
  printf '\n## %s\n```diff\n%s\n```\n' "$title" "$diff"
}
```

#### New helper: `validation_cycle_from_round()`

```bash
review_loop::validation_cycle_from_round() {
  local round="$1"
  printf '%s\n' "${round:1:1}"
}
```

#### `build_prompt()` — add 4 new cases

```bash
independent-design-review)
  # Zero review history — only design doc (already appended) and task
  # Do NOT append any files from specs/reviews/
  ;;
independent-code-review)
  # Zero review history — design doc (already appended) + code diff
  local baseline_sha
  baseline_sha="$(review_loop::read_state_field "baseline_sha" || true)"
  if [[ -n "$baseline_sha" ]]; then
    review_loop::append_diff_section "Code Changes" "$baseline_sha"
  fi
  ;;
validation-fix)
  # Include: validation review + Claude's triage + per-fix-round Claude review + code diff
  local baseline_sha cycle
  baseline_sha="$(review_loop::read_state_field "baseline_sha" || true)"
  cycle="$(review_loop::validation_cycle_from_round "$round")"
  review_loop::append_file_section "Validation Review" \
    "$project_root/specs/reviews/validation/code-c${cycle}-review.md"
  review_loop::append_file_section "Claude Triage Review" \
    "$project_root/specs/reviews/validation/code-c${cycle}-claude-review.md"
  # For fix round 2: include Claude's round-1 review and Codex's round-1 response
  if [[ "$round" == "c${cycle}f2" ]]; then
    review_loop::append_file_section "Previous Claude Fix Review" \
      "$project_root/specs/reviews/validation/code-c${cycle}f1-claude-review.md"
    review_loop::append_file_section "Previous Fix Response" \
      "$project_root/specs/reviews/validation/code-c${cycle}f1-codex-response.md"
  fi
  if [[ -n "$baseline_sha" ]]; then
    review_loop::append_diff_section "Code Changes" "$baseline_sha"
  fi
  ;;
validation-design-fix)
  # Include: validation review + Claude's response + design doc (already appended)
  local cycle
  cycle="$(review_loop::validation_cycle_from_round "$round")"
  review_loop::append_file_section "Validation Findings" \
    "$project_root/specs/reviews/validation/design-c${cycle}-review.md"
  review_loop::append_file_section "Claude Validation Response" \
    "$project_root/specs/reviews/validation/design-c${cycle}-response.md"
  # For fix round 2: include previous fix review
  if [[ "$round" == "c${cycle}f2" ]]; then
    review_loop::append_file_section "Previous Fix Review" \
      "$project_root/specs/reviews/validation/design-c${cycle}f1-codex-review.md"
  fi
  ;;
```

### 6. Modified: `review-loop/commands/review-loop.md`

**IMPORTANT**: The existing verify round steps (design step 3, code step 6) and terminal output steps (design step 4, code step 7) in `review-loop.md` must be **replaced** with the new end-to-end algorithms below — not merely preceded by validation insertions. The new algorithms incorporate validation, verify, and output into a single coherent flow per stage.

#### A. Design stage — replace steps 3-4 with validation + verify + output

Replace the existing design stage verify round and "Design stage complete" output with:

```markdown
## Design stage — independent validation

After the regular design review loop converges:

For each validation cycle from 1 to 2:
  1. Snapshot the worktree (same PRE_* procedure as regular rounds).
  2. Execute `review-loop/scripts/run-review-bg.sh independent-design-review c<cycle>`.
  3. Poll with `review-loop/scripts/check-review.sh`.
  4. Revert unauthorized file deltas. Allowed new file:
     `specs/reviews/validation/design-c<cycle>-review.md`.
  5. On TIMEOUT or FAILED: retry once, then skip this cycle on second failure.
     Log the failure to `.claude/review-loop.log`.
     Set `validation_skipped = true` for this stage.
  6. If the review file does not exist after step 5, skip to next cycle.
  7. Read `specs/reviews/validation/design-c<cycle>-review.md`.
  8. If no substantive issues → validation passed, exit the validation loop.
  9. If substantive issues found:
     a. Claude updates `specs/design.md` to address the findings.
     b. Claude writes `specs/reviews/validation/design-c<cycle>-response.md`.
     c. Enter a fix review loop (max 2 rounds):
        - Snapshot the worktree.
        - Execute `run-review-bg.sh validation-design-fix c<cycle>f<fix-round>`.
        - Poll with `check-review.sh`.
        - On TIMEOUT or FAILED: retry once, then skip this fix round on second failure.
          Log the failure. Treat unresolved fix rounds as unresolved validation findings.
        - Revert unauthorized file deltas. Allowed new file:
          `specs/reviews/validation/design-c<cycle>f<fix-round>-codex-review.md`.
        - If the review file does not exist, treat fix loop as converged (best-effort).
        - Read the review. If no substantive issues → fix loop converges.
        - Otherwise Claude updates design.md and continues.
     d. Continue to the next validation cycle.

If 2 validation cycles complete and the last cycle still had substantive issues,
set `unresolved_validation = true`.

## Design stage — verify round

Verify round trigger: run if (regular loop used all 5 rounds AND last round
changed design) OR (any validation cycle changed design).

If triggered:
  - Snapshot the worktree (same PRE_* procedure).
  - Execute `run-review-bg.sh design-review verify`.
  - Poll with `check-review.sh`.
  - Revert unauthorized file deltas. Allowed new file:
    `specs/reviews/design/round-verify-codex-review.md`.
  - Retry once on TIMEOUT or FAILED, then skip on second failure.
  - Read `specs/reviews/design/round-verify-codex-review.md`.
  - Do NOT make further design edits regardless of findings.
  - Write `specs/reviews/design/round-verify-claude-response.md`.

## Design stage — terminal output

If `unresolved_validation` OR `validation_skipped`:
  Output exactly: `Design stage complete with unresolved validation findings.
  Review specs/design.md and specs/reviews/validation/ before confirming.`
Otherwise:
  Output exactly: `Design stage complete. Review specs/design.md and confirm.`

Wait for the user before entering the code stage.
```

#### B. Code stage — replace steps 6-7 with validation + verify + output

Replace the existing code stage verify round and "Implementation complete" output with:

```markdown
## Code stage — independent validation

After the regular code review loop converges:

For each validation cycle from 1 to 2:
  1. Snapshot the worktree (same PRE_* procedure as regular rounds).
  2. Execute `review-loop/scripts/run-review-bg.sh independent-code-review c<cycle>`.
  3. Poll with `review-loop/scripts/check-review.sh`.
  4. Revert unauthorized file deltas. Allowed new file:
     `specs/reviews/validation/code-c<cycle>-review.md`.
  5. On TIMEOUT or FAILED: retry once, then skip this cycle on second failure.
     Log the failure. Set `validation_skipped = true`.
  6. If the review file does not exist after step 5, skip to next cycle.
  7. Read `specs/reviews/validation/code-c<cycle>-review.md`.
  8. If no substantive issues → validation passed, exit the validation loop.
  9. If substantive issues found:
     a. Claude writes `specs/reviews/validation/code-c<cycle>-claude-review.md`
        triaging which issues require fixes.
     b. Enter a fix loop (max 2 rounds):
        - Snapshot the worktree.
        - Execute `run-review-bg.sh validation-fix c<cycle>f<fix-round>`.
        - Poll with `check-review.sh`.
        - On TIMEOUT or FAILED: retry once, then skip this fix round on second failure.
          Log the failure. Treat unresolved fix rounds as unresolved validation findings.
        - Revert unauthorized changes to protected paths.
          Allowed: project source + test files,
          `specs/reviews/validation/code-c<cycle>f<fix-round>-codex-response.md`.
        - If the response file does not exist, treat fix loop as converged (best-effort).
        - Read the Codex response.
        - Claude writes `specs/reviews/validation/code-c<cycle>f<fix-round>-claude-review.md`
          reviewing the full diff. This review becomes the authoritative context for
          the next fix round — it supersedes the initial triage for directing Codex.
        - If no substantive issues → fix loop converges.
        - Otherwise continue.
     c. Continue to the next validation cycle.

If 2 validation cycles complete and the last cycle still had issues,
set `unresolved_validation = true`.

## Code stage — verify round

Verify round trigger: run if (regular loop used all 5 rounds AND last round
required code changes) OR (any validation cycle required code changes).

If triggered:
  - Write `specs/reviews/code/round-verify-claude-review.md` with a full
    independent review of the diff and no reference to prior rounds.
  - This is a Claude-only review. Do NOT invoke Codex or perform additional iterations.

## Code stage — terminal output

If `unresolved_validation` OR `validation_skipped`:
  Output exactly: `Implementation complete with unresolved validation findings.
  Review specs/reviews/validation/ for details.
  All changes on branch review-loop/<session-id>.`
Otherwise:
  Output exactly: `Implementation complete. All changes on branch review-loop/<session-id>.`
```

#### C. Stage transition — include validation artifacts (conditional)

```markdown
1. If `brainstorm_done: true` AND `specs/brainstorm.md` exists: `git add specs/brainstorm.md`
2. `git add specs/design.md specs/reviews/design/ .claude/review-loop.log`
3. If `specs/reviews/validation/` exists (directory): `git add specs/reviews/validation/`
4. `git commit -m "review-loop: design stage complete (<session-id>)"`
```

#### D. Protected paths

Validation review files (`specs/reviews/validation/*-review.md` and `specs/reviews/validation/*-claude-review.md`) are protected during fix rounds. Only the designated output file for the current round is allowed.

### 7. Modified: `review-loop/AGENTS.md`

Add after "Code stage":

```markdown
## Independent validation

- Runs after each stage's regular review loop converges, before the verify round.
- Uses a fresh Codex instance with zero shared review history.
- Codex must only write the current round's output file under `specs/reviews/validation/`.
- Do NOT read or access any files under specs/reviews/ (including design/, code/,
  and validation/) or .claude/. Review must be based solely on the artifacts
  provided in the prompt.
- The validation prompt is intentionally different from regular review prompts,
  focusing on blind spots that collaborative review tends to miss.
- If validation finds issues, they are fed back into a fix loop
  (max 2 rounds per cycle, max 2 cycles per stage).
- Validation review files are protected — fix rounds must not modify them.
- Do not invoke brainstorming skills.
```

### 8. Modified: `tests/review-loop.test.sh`

#### New test cases (19 total)

1. `test_independent_design_review_prompt_no_review_history` — `build_prompt independent-design-review c1` with existing review files; assert no review history leaks
2. `test_independent_design_review_prompt_includes_design_and_task` — assert design.md content and task present
3. `test_independent_code_review_prompt_includes_diff` — set up git repo with baseline_sha, make changes (including new untracked files), assert `## Code Changes` section contains diff including new files
4. `test_independent_code_review_prompt_no_review_history` — assert no `specs/reviews/code/` or `specs/reviews/validation/` content leaks in
5. `test_validation_fix_prompt_includes_validation_and_triage` — assert both validation review and Claude triage review present in `c1f1` prompt
6. `test_validation_fix_prompt_round_2_includes_previous_response` — assert `c1f2` prompt includes previous Claude fix review and Codex response from `c1f1`
7. `test_validation_design_fix_prompt_includes_validation_findings` — assert `c1f1` prompt contains validation findings
8. `test_validation_output_paths` — assert correct paths for all 4 new modes
9. `test_validate_round_accepts_validation_tokens` — assert `c1`, `c2`, `c1f1`, `c1f2`, `c2f1`, `c2f2` accepted; `c3`, `c1f3`, `c0` rejected
10. `test_run_review_bg_independent_design_review` — end-to-end with fake codex, round `c1`
11. `test_run_review_bg_validation_fix` — end-to-end with fake codex, round `c1f1`
12. `test_validation_skip_on_double_failure` — fake codex exits non-zero, no output; verify cycle treated as skipped
13. `test_validation_cycle_2_uses_distinct_artifacts` — run `independent-design-review c2`; assert output path uses `c2` prefix, not `c1`
14. `test_append_diff_section_includes_untracked_files` — create new untracked file, call `append_diff_section`; assert new file appears in diff output
15. `test_validation_fix_c2f1_prompt` — build prompt for `validation-fix c2f1`; assert it reads from `code-c2-review.md` and `code-c2-claude-review.md`
16. `test_run_review_bg_independent_code_review` — end-to-end with fake codex, round `c1`; assert sentinel, output, and diff in prompt
17. `test_run_review_bg_validation_design_fix` — end-to-end with fake codex, round `c1f1`; assert validation findings in prompt
18. `test_validation_design_fix_prompt_includes_claude_response` — assert `c1f1` prompt contains Claude's validation response (`design-c1-response.md`)
19. `test_check_review_with_validation_round_tokens` — call `check-review.sh` with composite validation tokens (`c1`, `c1f1`); assert correct status reporting

### No changes to

- `review-loop/scripts/run-review-bg.sh` — new modes flow through existing infrastructure
- `review-loop/scripts/check-review.sh` — already mode-agnostic
- `review-loop/scripts/kill-review.sh` — already session-agnostic
- `review-loop/hooks/hooks.json` — no hook changes
- `review-loop/commands/cancel-review.md` — validation cancellation uses existing behavior
- State file schema — no new fields; validation is a synchronous sub-phase

## Review Artifact Layout

```
specs/reviews/
  design/                                        # existing — regular design review
    round-1-codex-review.md
    round-1-claude-response.md
    ...
  code/                                          # existing — regular code review
    round-1-claude-review.md
    round-1-codex-response.md
    ...
  validation/                                    # new — independent validation
    design-c1-review.md                          # validation of design (cycle 1)
    design-c1-response.md                        # Claude's response (cycle 1)
    design-c1f1-codex-review.md                  # fix review round 1 (cycle 1)
    design-c1f2-codex-review.md                  # fix review round 2 (cycle 1)
    design-c2-review.md                          # validation of design (cycle 2)
    code-c1-review.md                            # validation of code (cycle 1)
    code-c1-claude-review.md                     # Claude's initial triage (cycle 1)
    code-c1f1-codex-response.md                  # Codex fix response (cycle 1, fix 1)
    code-c1f1-claude-review.md                   # Claude review after fix 1 (cycle 1)
    code-c1f2-codex-response.md                  # Codex fix response (cycle 1, fix 2)
    code-c2-review.md                            # validation of code (cycle 2)
```

## Context Isolation

Context isolation for independent validation is enforced at two layers:

1. **Prompt-assembly layer**: `build_prompt()` for `independent-design-review` and `independent-code-review` modes does not inject any files from `specs/reviews/` (including `specs/reviews/validation/` from prior cycles) or `.claude/`. Only the design document, task description, and (for code review) the code diff are included.

2. **Prompt-instruction layer**: The prompt templates explicitly prohibit the validator from reading or accessing any files under `specs/reviews/` (all three subdirectories: `design/`, `code/`, `validation/`) or `.claude/`. This instruction is reinforced in `AGENTS.md`.

**Acknowledged limitation**: Codex runs via `codex exec -C "$project_root" --full-auto` in the full workspace and could technically access any file. True filesystem isolation (e.g., running in a scratch worktree with only allowed files) would provide stronger guarantees but is out of scope for this iteration. The prompt-level prohibition is the pragmatic first step — if validation results show evidence of context leakage in practice, filesystem isolation can be added as a follow-up.

## Implementation Notes

- New modes reuse the existing `run-review-bg.sh` → `check-review.sh` → sentinel flow without modification.
- The `validate_round()` function is updated to accept composite tokens (`c1`, `c2`, `c1f1`, etc.).
- The `append_diff_section()` helper uses a temporary git index to include both tracked changes and new untracked files in the diff, matching the semantics of the regular code review path which stages everything before diffing. The temporary index is cleaned up immediately after use.
- The `validation-design-fix` mode provides a clean mechanism for injecting validation findings and Claude's response into Codex's prompt via `build_prompt()`.
- The `validation-fix` mode includes: validation review, Claude's initial triage, and (for fix round 2) the previous Claude fix review and Codex response. This ensures Codex always has the latest context.
- Claude writes per-fix-round review artifacts (`code-c<cycle>f<fix-round>-claude-review.md`) so that fix round 2 of `validation-fix` receives updated context rather than stale initial triage.
- `specs/reviews/validation/` staging is conditional on directory existence (`[ -d specs/reviews/validation ]`).
- On double failure (outer validation cycles or inner fix loops), the affected step is skipped, the failure is logged, and the final output message reflects unresolved findings. This avoids both blocking on infrastructure failures and falsely claiming validation passed.
- Inner fix loops mirror the outer validation cycle's retry/skip/log behavior: retry once on TIMEOUT/FAILED, skip on second failure, log, treat as unresolved.
- For `validation-fix`, the latest Claude per-fix-round review is authoritative for the next fix round, superseding the initial triage. The prompt template explicitly directs Codex to follow the most recent Claude review when present.
- The existing verify round and terminal output steps in `review-loop.md` are fully **replaced** (not just preceded by validation insertions) to ensure a single coherent flow per stage.

## Verification Scenarios

1. **Design validation passes on first cycle**: regular loop converges → independent-design-review finds no issues → verify round (if applicable) → user gate with standard message
2. **Design validation finds issues, fixed in one cycle**: validation review has issues → Claude fixes design → fix loop (validation-design-fix) converges → second validation passes → verify round → user gate
3. **Design validation exhausts 2 cycles**: both cycles find issues → verify round → user gate with "unresolved validation findings" message
4. **Code validation passes on first cycle**: regular loop converges → independent-code-review finds no issues → verify round (if applicable) → standard completion message
5. **Code validation finds issues, fixed in one cycle**: validation review has issues → Claude triage → validation-fix → fix loop converges → second validation passes → verify round → completion
6. **Code validation exhausts 2 cycles**: both cycles find issues → verify round → completion with "unresolved validation findings" message
7. **Validation prompt isolation**: prompts contain zero content from `specs/reviews/design/`, `specs/reviews/code/`, or `specs/reviews/validation/` (prior cycles); prompt instructions prohibit reading those paths
8. **Fix loop context**: validation-design-fix includes validation findings; validation-fix includes validation review + Claude triage + per-fix-round Claude review + previous Codex response
9. **Cancellation during validation**: same as regular cancellation
10. **Timeout/failure during validation**: retry once, skip on second failure, set `validation_skipped`, log, final message reflects skipped validation
11. **Validation failure with no artifacts**: stage transition conditional `git add` succeeds; workflow continues
12. **Artifact naming across cycles**: `c1`/`c2` prefixes, `c<N>f<M>` for fix rounds — no collisions
13. **Diff includes untracked files**: `append_diff_section` uses temporary index to capture new files
14. **Cycle 2 independence**: cycle 2 validator cannot access cycle 1 validation artifacts via prompt
15. **Fix loop failure**: inner fix loop TIMEOUT/FAILED retries once, skips on second failure, logs, sets unresolved
16. **Design validation response consumed**: `validation-design-fix` prompt includes Claude's validation response
17. **validation-fix authority**: fix round 2 prompt includes latest Claude fix review which supersedes initial triage
18. **Verify/output end-to-end**: existing verify and output steps fully replaced (not just preceded) in review-loop.md
