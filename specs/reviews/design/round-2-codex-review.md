# Design Audit

## Previously Identified Issues

### Previous Issue 1
Status: Fixed
Severity: High

Description: The stage-transition `git add` sequence is now conditional on `specs/brainstorm.md` existing (`specs/design.md:159-169`), which resolves the missing-pathspec failure from round 1.

Recommendation: None.

### Previous Issue 2
Status: Fixed
Severity: High

Description: Brainstorming now runs after session branch creation (`specs/design.md:113-135`), so `specs/brainstorm.md` is created on the session branch instead of dirtying the caller's original branch.

Recommendation: None.

### Previous Issue 3
Status: Fixed
Severity: High

Description: The proposed `code-fix` verify behavior now omits the current Claude review as well as prior Codex responses (`specs/design.md:84-102`), which resolves the specific anchoring problem identified in round 1.

Recommendation: None.

### Previous Issue 4
Status: Fixed
Severity: Medium

Description: The design-review prompt now makes the output split conditional on prior context being present and explicitly tells verify rounds to report findings as fresh (`specs/design.md:40-47`).

Recommendation: None.

### Previous Issue 5
Status: Fixed
Severity: Medium

Description: The phase model has been simplified to the three persisted values actually used by the workflow (`specs/design.md:171-179`, `specs/design.md:243-244`), removing the ambiguous verify/gate phase enum from the earlier draft.

Recommendation: None.

### Previous Issue 6
Status: Fixed
Severity: Medium

Description: The design now defines a fallback rule for missing skill-availability context: skip brainstorming and proceed directly to design (`specs/design.md:130-132`, `specs/design.md:245`).

Recommendation: None.

### Previous Issue 7
Status: Still open
Severity: Low

Description: The design still does not define a concrete verification matrix for the new v2.1 branches. The implementation notes remain high-level (`specs/design.md:238-245`), so prompt-assembly and orchestration regressions are still easy to miss.

Recommendation: Add at least a lightweight scenario matrix or explicit manual checks for brainstorming present vs absent, verify-round prompt assembly, and cancellation during brainstorming.

## Newly Identified Issues

### Issue 1
Severity: High

Description: The design adds verify-specific prompt behavior in `build_prompt()` (`specs/design.md:61-105`), but the proposed `review-loop/commands/review-loop.md` changes (`specs/design.md:107-187`) never define the concrete orchestration step that calls `run-review-bg.sh ... verify`, nor do they specify which verify artifact Claude should read back. The current command contract still only says "perform one final verification pass" in both stages (`review-loop/commands/review-loop.md:72`, `review-loop/commands/review-loop.md:107`). As written, the new `round=="verify"` branches can remain dead code or be implemented ad hoc.

Recommendation: Update the command spec to invoke verify rounds explicitly with the `verify` round token, name the expected `round-verify-*` files, and describe the readback/termination behavior. If code-stage verification is meant to stay Claude-only, remove the unused `code-fix` verify path instead of leaving a dangling interface.

### Issue 2
Severity: High

Description: v2.1 introduces `specs/brainstorm.md` as a tracked design artifact (`specs/design.md:126`, `specs/design.md:164-166`), but the code-stage protection model is not updated. The proposal only adds review instructions (`specs/design.md:145-157`) and explicitly leaves `code-implement.md` and `code-fix.md` unchanged (`specs/design.md:240-241`). In the current orchestrator, protected paths and staging exclusions cover `specs/design.md`, `specs/reviews/**`, and `.claude/**` only (`review-loop/commands/review-loop.md:93-105`). A code-implement or code-fix run can therefore modify or stage `specs/brainstorm.md` without being reverted, which muddies the audit trail and pollutes the code-review diff.

Recommendation: Add `specs/brainstorm.md` to the code-stage protected-path rollback logic and to the staging exclusions, and explicitly forbid modifying it in every implementation/fix prompt.

### Issue 3
Severity: High

Description: The proposed brainstorming-conflict fix is not propagated to the fresh background Codex sessions that do the creative work. The one-time suppression rule exists only in the top-level workflow and AGENTS text (`specs/design.md:122-129`, `specs/design.md:199-205`), while the implementation notes explicitly keep `review-loop/prompts/code-implement.md` and `review-loop/prompts/code-fix.md` unchanged (`specs/design.md:240-241`). Because those sessions start independently via `codex exec` (`review-loop/scripts/run-review-bg.sh:31-75`), they do not inherently inherit the "brainstorming already completed" state, so the original `superpowers:brainstorming` conflict can recur during implementation or fix rounds.

Recommendation: Persist a `brainstorm_done` or `skip_brainstorm` flag in state and inject it into every background prompt that can trigger skills, or update the code-implement and code-fix prompts to say explicitly that brainstorming has already been handled and must not run again.

### Issue 4
Severity: Medium

Description: The cancellation path for the new brainstorming stage is still underspecified. The design promises that cancellation during brainstorming can delete the session branch cleanly (`specs/design.md:135`, `specs/design.md:205`), but it keeps the state schema unchanged (`specs/design.md:243-244`) and does not include any change to the dedicated cancel flow. `review-loop/commands/cancel-review.md:9-11` still only kills the session and removes the local state file, and `review-loop/scripts/kill-review.sh:34-40` only terminates the process group and deletes runtime files. There is no recorded source branch to return to, and no shared cleanup step that can actually delete `review-loop/<session-id>` while it is checked out.

Recommendation: Record the starting branch in state, add a shared cancellation helper that checks out the original branch, and update both `review-loop.md` and `cancel-review.md` to delete the session branch when cancellation occurs before the design-stage commit.

### Issue 5
Severity: Medium

Description: The design stage now treats `specs/brainstorm.md` as the primary input whenever it exists (`specs/design.md:140-142`). That makes a model-generated intermediary artifact more authoritative than the original user task stored in state. If the brainstorm omits a requirement or reframes the request, the resulting design can stay faithful to the brainstorm while drifting from the user's actual intent.

Recommendation: Keep the original task description authoritative and treat `specs/brainstorm.md` as supplementary context. The design stage should synthesize both inputs, with conflicts resolved in favor of the user's task.
