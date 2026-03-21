# Design Audit

## Previously Identified Issues

### Previous Issue 1
Status: Still open
Severity: High

Description: The design still contains mutually exclusive instructions for code-stage verification. Section 2 says `build_prompt()` should add a `code-fix` verify branch and even shows the exact prompt text (`specs/design.md:84-103`), but section 3.D later says code-stage verification is Claude-only and the `code-fix verify` path should be removed (`specs/design.md:166-178`, `specs/design.md:400-401`). That contradiction means implementers can legitimately preserve or reintroduce the unsupported path, and the current helper interfaces still expose `code-fix verify` as a valid combination (`review-loop/scripts/common.sh:122-184`, `review-loop/scripts/run-review-bg.sh:12-18`, `review-loop/scripts/check-review.sh:13-19`).

Recommendation: Delete the `code-fix` verify branch from section 2 entirely and make supported mode/round combinations explicit in the helper interface so only `design-review verify` is callable.

### Previous Issue 2
Status: Fixed
Severity: High

Description: Brainstorm usage is now session-scoped through `brainstorm_done`, and stale `specs/brainstorm.md` is explicitly ignored when that flag is false (`specs/design.md:137-149`, `specs/design.md:402`).

Recommendation: None.

### Previous Issue 3
Status: Fixed
Severity: High

Description: The design now includes `tests/review-loop.test.sh` in the file-change list and enumerates the required v2.1 test updates (`specs/design.md:374-389`).

Recommendation: None.

### Previous Issue 4
Status: Still open
Severity: Medium

Description: The security concern around persisting brainstorming output is unchanged. The workflow still instructs Claude to save interactive brainstorming content to `specs/brainstorm.md` and commit it at the design-stage transition (`specs/design.md:125-127`, `specs/design.md:196-201`), while the only mitigation is that the user "controls what goes into it" (`specs/design.md:403`). User supervision does not prevent accidental inclusion of secrets or sensitive examples in a tracked repo artifact.

Recommendation: Add an explicit "no secrets/raw credentials" rule plus a confirmation or redaction step before commit, or make `specs/brainstorm.md` ephemeral/session-local instead of a preserved tracked file.

## Newly Identified Issues

### Issue 1
Severity: High

Description: The design never specifies when `brainstorm_done` is set to `true`. The new brainstorming section only says to invoke the skill, save `specs/brainstorm.md`, and wait for user confirmation (`specs/design.md:118-133`). The state schema later introduces `brainstorm_done` and the rest of the design relies on that flag to decide whether the brainstorm may be used (`specs/design.md:142-149`, `specs/design.md:224-236`, `specs/design.md:409-411`). Without an explicit state-update step after brainstorming completes, the most likely implementation is that the flag stays `false` and the freshly generated brainstorm is ignored.

Recommendation: Add an explicit step immediately after brainstorming completion to persist `brainstorm_done: true` to `.claude/review-loop.local.md`, and keep it `false` only on the skipped path.

### Issue 2
Severity: Medium

Description: The cancellation contract is still only specified for the happy-path "explicit cancel command on a named branch". The new steps restore `start_branch` only in `review-loop.md` and `cancel-review.md` (`specs/design.md:243-269`, `specs/design.md:359-372`), but the design explicitly leaves `hooks.json` and `kill-review.sh` unchanged (`specs/design.md:393-395`). The installed Stop hook still calls `kill-review.sh --from-hook` (`review-loop/hooks/hooks.json:3-9`), and that script deletes the state file immediately (`review-loop/scripts/kill-review.sh:16-39`), so hook-driven cancellation can still lose `start_branch` before any restoration happens. The schema also assumes the starting point is always a branch (`start_branch: main` at `specs/design.md:233-235`), while the startup checks never require the session to start from a local branch (`review-loop/commands/review-loop.md:20-37`). A detached-HEAD or tag-based start is therefore undefined.

Recommendation: Define a single cancellation helper that reads restore information before cleanup and is used by both explicit cancellation and the Stop hook. Either require startup from a local branch with a clear error, or store a more general `start_ref` plus detached-state metadata so restoration works for all valid Git starting states.

### Issue 3
Severity: Medium

Description: Several proposed tests do not map to executable behavior in the current architecture. The new cases `test_brainstorm_done_flag_gates_brainstorm_usage`, `test_brainstorm_done_flag_enables_brainstorm_usage`, `test_start_branch_persisted_in_state`, and `test_cancellation_restores_start_branch` are described as behavioral verification (`specs/design.md:383-389`), but the relevant logic lives in markdown command instructions for Claude rather than in shell helpers or scripts (`review-loop/commands/review-loop.md:31-127`, `review-loop/commands/cancel-review.md:7-12`). The current shell harness can execute scripts and grep prompt files (`tests/review-loop.test.sh:253-277`, `tests/review-loop.test.sh:380-418`), but it cannot prove that Claude actually obeys these workflow instructions. As written, the test plan risks giving a false sense of coverage.

Recommendation: Move critical state and branch operations into executable helpers that the test suite can call directly, or explicitly downgrade these cases to prompt-content assertions and keep end-to-end verification in the manual matrix.
