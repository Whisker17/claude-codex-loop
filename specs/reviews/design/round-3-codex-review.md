# Design Audit

## Previously Identified Issues

### Previous Issue 1
Status: Fixed
Severity: High

Description: Verify-round orchestration is now specified explicitly for both stages, including the `verify` round token and the expected `round-verify-*` artifacts (`specs/design.md:150-178`).

Recommendation: None.

### Previous Issue 2
Status: Fixed
Severity: High

Description: `specs/brainstorm.md` is now included in the code-stage protected paths and staging exclusions (`specs/design.md:206-220`), which closes the audit-trail gap from round 2.

Recommendation: None.

### Previous Issue 3
Status: Fixed
Severity: High

Description: The design now adds explicit brainstorming-suppression text to both `code-implement.md` and `code-fix.md`, and mirrors that rule in `AGENTS.md` (`specs/design.md:269-338`).

Recommendation: None.

### Previous Issue 4
Status: Still open
Severity: Medium

Description: Cancellation is still not specified end-to-end. The design adds `start_branch` and new inline cancellation steps (`specs/design.md:222-249`), but it never includes `review-loop/commands/cancel-review.md` in the file-change list even though the dedicated cancel command still only kills the session and removes the state file (`review-loop/commands/cancel-review.md:9-12`). The proposed step order is also self-contradictory: `kill-review.sh` already deletes `.claude/review-loop.local.md` (`review-loop/scripts/kill-review.sh:39`), so the only persisted copy of `start_branch` is gone before step 2 unless the caller cached it first, which the design does not require.

Recommendation: Update both cancellation entrypoints to read and retain `start_branch` before invoking cleanup, or move branch restoration and branch deletion into a shared helper that consumes state before removing it.

### Previous Issue 5
Status: Fixed
Severity: Medium

Description: The design stage now keeps the task description authoritative and treats `specs/brainstorm.md` as supplementary context (`specs/design.md:137-147`).

Recommendation: None.

### Previous Issue 6
Status: Fixed
Severity: Medium

Description: The fallback for missing skill-availability context is now defined: skip brainstorming and proceed with the task description alone (`specs/design.md:130-132`, `specs/design.md:347`).

Recommendation: None.

### Previous Issue 7
Status: Fixed
Severity: Low

Description: The design now includes a concrete manual verification matrix for the new v2.1 branches (`specs/design.md:351-360`).

Recommendation: None.

## Newly Identified Issues

### Issue 1
Severity: High

Description: The new code-stage verify path is internally inconsistent. It is described as a "review-only verification pass" and a fully fresh review (`specs/design.md:169-191`), but the workflow still invokes `run-review-bg.sh code-fix verify` (`specs/design.md:173-176`) and the only proposed `code-fix.md` change is brainstorming suppression (`specs/design.md:331-338`). The underlying prompt still tells Codex to "Read the review, fix code issues, and write a response" (`review-loop/prompts/code-fix.md:1-13`). Combined with the verify-mode prompt assembly that omits `Current Claude Review`, the final pass would have neither the review it is supposed to answer nor a prompt that instructs it to behave as a read-only auditor. In the worst case, Codex can make fresh code edits after Claude's last review, and the design forbids any additional review iteration.

Recommendation: Introduce a dedicated read-only `code-verify` mode/prompt, or keep the final verify step Claude-only and remove the `code-fix verify` path. Do not reuse a code-editing prompt for a no-more-edits verification step.

### Issue 2
Severity: High

Description: `specs/brainstorm.md` is not scoped to the current session. The design says to use the file whenever it exists (`specs/design.md:139-147`) and to commit it at the stage transition (`specs/design.md:196-204`). That means a brainstorm artifact from an earlier task can silently bleed into a later review-loop session, especially in the "brainstorming absent" path where the matrix assumes there is no brainstorm file (`specs/design.md:355-356`). Because the path is fixed and persisted, skipping brainstorming does not guarantee the design stage is working from the task description alone.

Recommendation: Make brainstorm usage session-scoped. Record whether the current session generated brainstorm output and only include `specs/brainstorm.md` when that flag is true, or move brainstorming output to a session-specific path and materialize/commit it only for the active session.

### Issue 3
Severity: High

Description: The design does not account for the required automated test updates. Existing tests currently assert the opposite verify behavior by checking that `design-review verify` still includes prior review context (`tests/review-loop.test.sh:406-417`), and they also assert that `cancel-review.md` remains cleanup-only (`tests/review-loop.test.sh:264-277`). Several new contracts introduced here also need explicit coverage, including `start_branch` persistence, `specs/brainstorm.md` exclusions, and the new verify orchestration. Without updating the test plan and file-change list, this work is likely to break the current test suite or ship with the new branches effectively unverified.

Recommendation: Add `tests/review-loop.test.sh` to the affected files and extend it for the v2.1 contracts: verify prompts with no prior context, brainstorming present vs absent, session-scoped brainstorm handling, `start_branch` state, and both cancellation entrypoints.

### Issue 4
Severity: Medium

Description: The new brainstorming artifact introduces an avoidable data-exposure path. The brainstorming step is interactive (`specs/design.md:118-135`) and may collect raw requirements, examples, or sensitive operational details that would never belong in the final design. The design then requires saving that output verbatim to a tracked repo file and committing it at the stage transition (`specs/design.md:196-204`). Unlike the transient state file, this artifact is preserved. There is no redaction rule, no "do not include secrets" constraint, and no explicit confirmation before persisting the brainstorm output.

Recommendation: Either make `specs/brainstorm.md` ephemeral by default, or add explicit redaction and secret-handling guidance plus a confirmation step before it is committed to the branch.
