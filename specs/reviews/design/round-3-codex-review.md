# Design Audit

## Previously Identified Issues

### Now Fixed

#### Previous Issue 1
Status: Fixed
Severity: Critical

Description: The validation artifact namespace is now consistently keyed by `c<cycle>` and `c<cycle>f<fix-round>`, which resolves the round-name collision called out in round 2.

References: [specs/design.md:19](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L19), [specs/design.md:24](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L24), [specs/design.md:30](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L30), [specs/design.md:523](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L523)

Recommendation: None.

#### Previous Issue 2
Status: Fixed
Severity: High

Description: The design-stage follow-up path now exists. `validation-design-fix` has both a prompt template and a `build_prompt()` case, so validation findings can be fed back into a defined design-fix review loop.

References: [specs/design.md:186](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L186), [specs/design.md:222](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L222), [specs/design.md:360](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L360), [specs/design.md:552](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L552)

Recommendation: None.

#### Previous Issue 5
Status: Fixed
Severity: Medium

Description: The outer validation-cycle failure path is now explicitly specified. The design defines retry-once, skip-on-second-failure behavior and surfaces skipped validation in the terminal user-facing messages instead of treating it as a clean pass.

References: [specs/design.md:44](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L44), [specs/design.md:59](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L59), [specs/design.md:391](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L391), [specs/design.md:426](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L426), [specs/design.md:556](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L556)

Recommendation: None.

#### Previous Issue 6
Status: Fixed
Severity: Medium

Description: The spec now gives `validation-fix c<cycle>f2` an explicit path to Claude's prior fix review and Codex's prior response, so the second fix round is no longer forced to rely on stale cycle-level triage alone.

References: [specs/design.md:24](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L24), [specs/design.md:340](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L340), [specs/design.md:349](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L349), [specs/design.md:442](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L442), [specs/design.md:554](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L554)

Recommendation: None.

### Still Open

#### Previous Issue 3
Status: Still open
Severity: High

Description: The top-level algorithm is clearer, but the implementation section still does not tell the author to replace the existing verify/output steps in `review-loop/commands/review-loop.md`. It only says to insert validation sub-phases before verify and to tweak stage transition staging. The current command doc still hard-codes the old verify predicates and terminal output strings, so an implementation that follows the file-change instructions literally will leave contradictory behavior in the command contract.

References: [specs/design.md:36](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L36), [specs/design.md:51](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L51), [specs/design.md:376](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L376), [specs/design.md:413](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L413), [review-loop/commands/review-loop.md:122](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/commands/review-loop.md#L122), [review-loop/commands/review-loop.md:132](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/commands/review-loop.md#L132), [review-loop/commands/review-loop.md:175](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/commands/review-loop.md#L175), [review-loop/commands/review-loop.md:179](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/commands/review-loop.md#L179)

Recommendation: Replace the affected design-stage and code-stage blocks end-to-end in the file-change plan. The spec should explicitly rewrite design step 3-4 and code step 6-7, not just insert validation sections ahead of the old logic.

#### Previous Issue 4
Status: Still open
Severity: High

Description: "Zero shared review history" is still not enforced. The spec now documents the limitation, but the validator still runs via `codex exec -C "$project_root" --full-auto` inside the full workspace, which leaves prior review files technically reachable and vulnerable to accidental reads or prompt-injection-style instructions from the artifact under review.

References: [specs/design.md:13](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L13), [specs/design.md:539](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L539), [specs/design.md:545](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L545), [review-loop/scripts/run-review-bg.sh:74](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/scripts/run-review-bg.sh#L74)

Recommendation: Enforce isolation at the filesystem boundary by running independent validation in a scratch worktree or temporary directory that only contains the allowed artifacts.

#### Previous Issue 7
Status: Still open
Severity: Medium

Description: The test plan is better than round 2, but it still misses several high-risk validation paths. The added cases cover `c2` artifact naming, denylist leakage, and untracked-file diffs, but there is still no explicit `validation-fix c2f1` coverage, no end-to-end `independent-code-review` coverage, no runtime coverage for `validation-design-fix`, and no `check-review.sh` status test that exercises composite validation tokens.

References: [specs/design.md:487](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L487), [specs/design.md:492](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L492), [specs/design.md:493](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L493), [specs/design.md:496](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L496), [specs/design.md:499](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L499), [specs/design.md:504](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L504)

Recommendation: Add prompt-level and end-to-end tests for `validation-fix c2f1`, `validation-design-fix c1f1/c2f1`, `independent-code-review`, and `check-review.sh` with validation-mode rounds.

## Newly Identified Issues

### Issue 1
Severity: Medium

Description: The design-stage validation response artifact is written but never consumed. The spec introduces `design-c<cycle>-response.md` and explicitly says Claude writes it before entering the fix loop, but `validation-design-fix` prompt assembly only injects the original validation findings and, on round 2, the previous Codex review. That means the design-stage fix loop has no channel for Claude to explain why a finding was only partially accepted, intentionally rejected, or addressed in a different way. This is weaker than the regular design-review loop, which always carries forward Claude's response.

References: [specs/design.md:22](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L22), [specs/design.md:195](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L195), [specs/design.md:221](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L221), [specs/design.md:360](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L360), [specs/design.md:399](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L399), [specs/design.md:525](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L525), [specs/design.md:567](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L567)

Recommendation: Include Claude's validation response in `validation-design-fix` prompts. If multiple fix rounds are allowed, also define whether Claude writes per-fix-round responses or overwrites a single response artifact that the next audit round consumes.

### Issue 2
Severity: High

Description: The inner validation fix loops have no failure contract. The outer validation cycles define retry-once, skip-on-second-failure behavior, but both inner fix loops omit equivalent handling for `TIMEOUT`, `FAILED`, or missing artifacts. A failed `validation-design-fix` or `validation-fix` invocation therefore has no specified retry behavior, no logging rule, and no defined effect on the final stage outcome.

References: [specs/design.md:391](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L391), [specs/design.md:400](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L400), [specs/design.md:406](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L406), [specs/design.md:426](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L426), [specs/design.md:434](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L434), [specs/design.md:441](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L441)

Recommendation: Mirror the outer-loop retry/skip/logging rules inside both fix loops. The spec should define what happens on first failure, second failure, missing review/response artifacts, and how those failures affect the terminal "unresolved validation findings" state.

### Issue 3
Severity: Medium

Description: The `validation-fix` round-2 contract is still ambiguous about which Claude artifact is authoritative. The prompt template tells Codex to address issues from "Claude's triage review," but the round-2 prompt assembly additionally injects a previous Claude fix review and previous Codex response. The spec never states whether the latest Claude fix review supersedes the original triage, or how newly discovered issues from round 1 should be handled in round 2. That leaves `c<cycle>f2` vulnerable to conflicting instructions.

References: [specs/design.md:169](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L169), [specs/design.md:170](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L170), [specs/design.md:341](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L341), [specs/design.md:349](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L349), [specs/design.md:442](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L442), [specs/design.md:553](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L553)

Recommendation: Make the latest Claude fix review authoritative for subsequent fix rounds and treat the initial triage as background context only. Add a test that asserts the `c1f2` prompt communicates that precedence explicitly.
