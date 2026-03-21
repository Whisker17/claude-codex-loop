# Design Audit

## Findings

### Issue 1
Severity: High

Description: The cancellation flow still does not reliably restore Git state when the index contains staged session changes. The proposed cleanup sequence is `git checkout -- . && git clean -fd` (`specs/design.md:239-243`, `specs/design.md:255-261`, `specs/design.md:370-374`). That resets tracked working-tree content and removes untracked files, but it does not unstage staged modifications or staged new files. The workflow can still reach cancellation with staged entries, for example after a failed stage-transition commit or any interruption between `git add` and `git reset`. In that state, `git checkout <start_branch>` can fail or carry cancelled session changes onto the restored branch.

Recommendation: Define cancellation cleanup to clear the index as well as the working tree, for example `git reset -- . && git checkout -- . && git clean -fd`, or an equivalent fully destructive sequence if that is the intended semantics. Add a verification scenario that covers both staged tracked changes and staged new files.

### Issue 2
Severity: High

Description: The final design verify pass is missing the rollback and retry guardrails that protect normal Codex review rounds. The verify step launches another `design-review` background run, but the documented flow only says to execute it, poll, read the review, avoid further design edits, and write the Claude response (`specs/design.md:138-147`). It does not say to snapshot pre/post state, constrain the allowed output file, revert unauthorized deltas, log reversions, or retry on `TIMEOUT`/`FAILED`. That leaves the last supposedly read-only Codex audit pass under-specified and potentially unguarded.

Recommendation: State explicitly that verify uses the same snapshot, allowed-file, rollback, logging, and retry procedure as regular `design-review` rounds, with the allowed output file changed to `specs/reviews/design/round-verify-codex-review.md`. Add verification coverage for unauthorized-file rollback during the verify pass.

### Issue 3
Severity: Medium

Description: The new brainstorming stage is labeled optional, but the flow does not actually provide a user-controlled skip or reject path. The only branch is skill availability: if `superpowers:brainstorming` is available, the workflow must invoke it, write `specs/brainstorm.md`, and set `brainstorm_done: true` before waiting for user confirmation (`specs/design.md:103-116`). That makes the stage effectively mandatory whenever the skill exists, and it records the brainstorm as approved before the user has actually accepted it. If the session is resumed after that point, the design stage will treat the brainstorm artifact as valid session input even if the user wanted to discard it.

Recommendation: Add an explicit user opt-in/skip decision before invoking brainstorming, and only set `brainstorm_done: true` after the user confirms the artifact should be kept. If partial output needs to be tracked, introduce a separate pending state so unapproved brainstorms are ignored and never staged or committed.

### Issue 4
Severity: Medium

Description: The design is internally inconsistent about whether `code-fix verify` still exists in the shared helper interface. Section 2 and the implementation notes say the `code-fix` case in `build_prompt()` remains unchanged and that `code-fix verify` is still technically callable but out of scope (`specs/design.md:63-86`, `specs/design.md:402-408`). Section 3.D then says to remove the `code-fix verify` path from `build_prompt()` because it is dead code (`specs/design.md:150-163`). Those instructions lead to different implementations of `common.sh` and keep the callable shell surface and documented workflow out of sync.

Recommendation: Choose one model and document it consistently. Either keep helper behavior unchanged and explicitly tolerate unsupported shell-only combinations, or add mode-and-round validation so `code-fix verify` fails fast everywhere and remove the dead path from helpers, tests, and documentation together.

### Issue 5
Severity: Medium

Description: `specs/brainstorm.md` is still committed to the repository without a dedicated review or redaction checkpoint. The design writes the brainstorming output to a tracked path, then stages and commits it at the design-stage transition whenever `brainstorm_done: true` and the file exists (`specs/design.md:107-110`, `specs/design.md:183-188`, `specs/design.md:410-411`). The only safeguard is a prompt instruction not to include secrets plus general user supervision. For a repository artifact, that is a weak control against accidentally recording sensitive notes, copied credentials, or private context generated during the interactive brainstorming session.

Recommendation: Add an explicit pre-commit review/redaction step for `specs/brainstorm.md`, or keep brainstorm output session-local by default and require an affirmative promotion step before it is staged into the repo.
