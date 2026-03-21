# Design Audit

## Previously Identified Issues

None. This is round 1.

## Newly Identified Issues

### Issue 1
Severity: High

Description: `specs/design.md` says the stage transition should run `git add specs/brainstorm.md specs/design.md specs/reviews/design/ .claude/review-loop.log` and that `specs/brainstorm.md` is "silently skipped" when absent (`specs/design.md:155-158`). That is not how `git add` behaves for a missing literal pathspec. In the no-brainstorm path, this step would fail before the design-stage commit, so one of the two intended flows cannot complete.

Recommendation: Make adding `specs/brainstorm.md` conditional on the file existing, or restructure the command so the optional artifact is added separately only when created.

### Issue 2
Severity: High

Description: The brainstorming stage is defined before session state and branch creation, and it writes directly to `specs/brainstorm.md` (`specs/design.md:115-123`, `188-191`). That dirties the caller's current branch immediately after the clean-worktree check and leaves no session-scoped cleanup if the user stops, branch creation fails, or cancellation happens before `.claude/review-loop.local.md` exists. The design therefore breaks the branch-isolation guarantee that the rest of the workflow assumes.

Recommendation: Create the session and `review-loop/<session-id>` branch before writing any repo artifacts, or store brainstorming output in a session-scoped temp file and materialize `specs/brainstorm.md` only after the branch exists and the user continues. Also define cleanup behavior for failure or cancellation before branch creation.

### Issue 3
Severity: High

Description: The proposed verify behavior for `code-fix` is not actually independent. The design keeps `Current Claude Review` always included and only omits the previous Codex response in verify mode (`specs/design.md:84-97`). The current implementation already appends `Current Claude Review` unconditionally in `review-loop/scripts/common.sh:290-295`. That means the final pass is still anchored to prior reviewer findings, which contradicts the stated goal that verify rounds be "completely unconstrained" and have "no prior review history" (`specs/design.md:148-149`, `210-211`).

Recommendation: For `code-fix` verify mode, omit both `Current Claude Review` and prior Codex responses, or introduce a dedicated verification mode/prompt that receives only the spec, repository context, and required output path.

### Issue 4
Severity: Medium

Description: The rewritten design-review prompt requires the reviewer to separate "previously identified" from "newly identified" issues (`specs/design.md:40-44`), but the same design intentionally strips prior review context during verify rounds (`specs/design.md:58-59`, `64-77`, `198-200`). In a verify pass, the auditor has no reliable basis for classifying old issues, so the output contract is internally inconsistent and pushes the model toward guesswork.

Recommendation: Make the section split conditional on prior context being present, or define a verify-round-specific output format such as "fresh findings only" plus an explicit note that prior issue status cannot be assessed from the prompt context.

### Issue 5
Severity: Medium

Description: The phase model is under-specified. The design introduces `brainstorm`, `design-verify`, `gate`, `code-verify`, and `done` as valid `phase` values (`specs/design.md:163-166`, `224-230`), but the workflow changes only describe starting at `brainstorm` or `design` and later switching to `code`. Because `common.sh` includes `phase` in runtime metadata, missing transition rules will make verify/gate/cancel paths ambiguous and reduce observability during debugging.

Recommendation: Add an explicit phase-transition table covering initial creation, verify passes, the user gate, cancellation, and final completion, or shrink the enum to the values the command actually persists.

### Issue 6
Severity: Medium

Description: Brainstorm-skill detection is not specified as a deterministic interface. The design relies on `superpowers:brainstorming` being visible in "system-reminder messages at conversation start" (`specs/design.md:117-118`), but does not define what to do if that context is unavailable later in the session or cannot be inspected reliably. That makes the optional-stage decision depend on ephemeral chat context rather than a stable input the workflow can test.

Recommendation: Define a fallback rule such as "if the current session cannot confirm skill availability, skip brainstorming," and consider persisting the detection result in the state file so later steps do not depend on earlier conversation context.

### Issue 7
Severity: Low

Description: The design does not include a concrete verification matrix for the new branches introduced by v2.1. The risky changes here are mostly in prompt assembly and orchestration, so regressions will be subtle without scenario-based checks for both the brainstorming and verify-round paths.

Recommendation: Add explicit tests or manual verification steps for at least: brainstorming present vs absent, round 1 vs later rounds vs verify prompt contents, stage transition when `specs/brainstorm.md` is absent, and cleanup behavior when the workflow stops before branch creation.
