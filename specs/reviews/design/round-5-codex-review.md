# Design Audit

## Previously Identified Issues

### Previous Issue 1
Status: Still open  
Severity: Medium

Description: The document-level contradiction around code-stage verification is resolved, but the unsupported `code-fix verify` combination is still exposed through the shared helper interface. The design explicitly keeps `validate_round()` generic and says restricting `code-fix verify` is out of scope (`specs/design.md:61-86`, `specs/design.md:162`, `specs/design.md:393-394`). The current helpers likewise accept `verify` for any mode and derive a `round-verify-codex-response.md` path for `code-fix` (`review-loop/scripts/common.sh:134-184`, `review-loop/scripts/run-review-bg.sh:9-18`, `review-loop/scripts/check-review.sh:13-19`). That leaves the documented workflow and the callable interface out of sync.

Recommendation: Add mode-and-round validation in the shared helpers so unsupported combinations fail fast, or introduce a distinct review-only mode if code verification ever needs to be callable through the shell interface.

### Previous Issue 2
Status: Fixed  
Severity: High

Description: The design now explicitly sets `brainstorm_done: true` after writing `specs/brainstorm.md`, and later gates design-time use of brainstorm output on that field (`specs/design.md:107-113`, `specs/design.md:124-133`, `specs/design.md:220`, `specs/design.md:403`).

Recommendation: None.

### Previous Issue 3
Status: Still open  
Severity: Medium

Description: Persisting brainstorming output is still a security risk. The design now adds a "do not include secrets" instruction, but it still commits the interactive brainstorm artifact at stage transition and explicitly says no additional redaction step is needed beyond user judgment (`specs/design.md:107-110`, `specs/design.md:183-185`, `specs/design.md:396-397`). That is a weak control for a tracked repository artifact.

Recommendation: Add an explicit review/redaction confirmation before commit, or keep brainstorming output ephemeral and session-local unless the user deliberately promotes it into the repo.

### Previous Issue 4
Status: Still open  
Severity: Medium

Description: Detached-HEAD cancellation is still not correctly specified. The design proposes storing `git rev-parse --abbrev-ref HEAD`, which becomes the literal string `HEAD` when the session starts detached, and then restoring with `git checkout <start_branch> || git checkout --detach <start_branch>` (`specs/design.md:218`, `specs/design.md:255-260`). Once the session branch has advanced, both commands resolve against the current session tip rather than the original detached commit, so the workflow cannot reliably return the user to the starting revision.

Recommendation: Persist an immutable starting commit SHA in addition to any starting branch name, and restore detached sessions from that SHA rather than from the symbolic name `HEAD`.

### Previous Issue 5
Status: Fixed  
Severity: Medium

Description: The test plan now correctly separates shell-harness assertions from markdown-orchestrated behavior that requires manual verification, which avoids overstating automated coverage (`specs/design.md:373-382`, `specs/design.md:399-410`).

Recommendation: None.

## Newly Identified Issues

### Issue 1
Severity: High

Description: The explicit cancellation flow still does not work "at any point" because it ignores uncommitted session changes. The workflow creates working-tree changes before cancellation in every stage: `specs/brainstorm.md` during brainstorming, `specs/design.md` and review artifacts during design, and source/test edits during code (`specs/design.md:98-147`, `specs/design.md:178-204`, `specs/design.md:225-260`). `kill-review.sh` only removes runtime files and the state file (`review-loop/scripts/kill-review.sh:23-40`). It does not clean, stash, or archive the session worktree. As a result, `git checkout <start_branch>` can fail because local changes would be overwritten, or it can carry cancelled session changes onto the starting branch, after which `git branch -D review-loop/<session-id>` may still fail or discard the wrong state.

Recommendation: Define cancellation semantics for in-progress session changes and encode them in the workflow. If cancellation means "discard session work", add an explicit destructive cleanup step before branch restoration. If it means "preserve work", stash or archive it first, then restore the starting branch and decide whether to keep or delete the session branch. Add a manual verification case that exercises cancellation with uncommitted design and code changes.

### Issue 2
Severity: High

Description: Session scoping for `specs/brainstorm.md` is still incomplete. The design correctly says a stale brainstorm file must be ignored as design input when `brainstorm_done: false` (`specs/design.md:124-133`, `specs/design.md:403-405`), but the stage-transition commit later stages the file whenever it merely exists (`specs/design.md:183-184`). In the stale-file scenario the design itself calls out, that rule reintroduces the old brainstorm artifact into the new session branch even though brainstorming was skipped for the current session.

Recommendation: Gate all brainstorm-file handling on the current session flag, not just design-time reading. Only stage and preserve `specs/brainstorm.md` when `brainstorm_done: true` for the active session, or move brainstorming output to a session-specific path and materialize the shared file only for the session that created it.
