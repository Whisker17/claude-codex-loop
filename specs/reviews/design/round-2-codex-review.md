# Design Audit

## Previously Identified Issues

### Previous Issue 1
Status: Fixed
Severity: Critical

Description: The design now gives validation rounds and validation fix rounds their own composite identities (`c<cycle>` and `c<cycle>f<fix-round>`) plus dedicated validation output paths, so the round-1 namespace collision is resolved.

References: [specs/design.md:17](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L17), [specs/design.md:28](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L28), [specs/design.md:261](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L261), [specs/design.md:528](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L528)

Recommendation: None for the collision itself. Keep all validation artifacts in the validation namespace.

### Previous Issue 2
Status: Fixed
Severity: High

Description: The design-stage fix loop now has an explicit implementation path. The new `validation-design-fix` mode and prompt-builder case give Codex a defined way to receive validation findings during follow-up design audits.

References: [specs/design.md:168](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L168), [specs/design.md:316](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L316), [specs/design.md:389](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L389), [specs/design.md:605](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L605)

Recommendation: None.

### Previous Issue 3
Status: Fixed
Severity: High

Description: The ordering conflict is resolved. Independent validation is now explicitly positioned before the terminal verify round, so the existing "no more edits" semantics no longer directly contradict the validation loop.

References: [specs/design.md:30](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L30), [specs/design.md:50](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L50), [specs/design.md:367](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L367), [specs/design.md:408](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L408)

Recommendation: None on ordering. A separate verify-trigger ambiguity remains and is listed below as a new issue.

### Previous Issue 4
Status: Still open
Severity: High

Description: The design now documents the isolation limitation, but it still does not enforce "zero shared review history." The validator continues to run in the full workspace via `codex exec -C "$project_root" --full-auto`, so prior review files remain technically reachable. Because the design relies only on prompt instructions, accidental workspace reads or prompt-injection from the artifact under review can still defeat the isolation guarantee.

References: [specs/design.md:13](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L13), [specs/design.md:592](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L592), [specs/design.md:598](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L598), [run-review-bg.sh:74](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/scripts/run-review-bg.sh#L74)

Recommendation: Enforce isolation at the filesystem boundary by running independent validation in a scratch worktree or temporary directory that contains only the allowed artifacts.

### Previous Issue 5
Status: Fixed
Severity: Medium

Description: Failure handling is now defined. The design specifies the retry/skip behavior, makes missing validation artifacts an explicit branch, and makes validation staging conditional on the directory existing.

References: [specs/design.md:380](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L380), [specs/design.md:383](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L383), [specs/design.md:451](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L451), [specs/design.md:607](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L607)

Recommendation: None on control-flow definition. A separate policy problem remains and is listed below as a new issue.

### Previous Issue 6
Status: Still open
Severity: Medium

Description: `validation-fix` now includes the original validation review, Claude's initial triage, and the previous Codex response, but the design still does not define how Claude's post-fix review for `c<cycle>f1` becomes input to `c<cycle>f2`. As written, the second fix round can still run against stale triage unless Claude silently overwrites `code-c<cycle>-claude-review.md`, and that overwrite contract is nowhere specified.

References: [specs/design.md:331](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L331), [specs/design.md:341](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L341), [specs/design.md:426](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L426), [specs/design.md:438](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L438), [specs/design.md:606](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L606)

Recommendation: Define an explicit per-fix-round Claude review contract for validation fixes. Either create `code-c<cycle>f<fix-round>-claude-review.md` artifacts or explicitly require Claude to overwrite the cycle triage file before each subsequent `validation-fix` round and include that file in tests.

### Previous Issue 7
Status: Still open
Severity: Medium

Description: The test plan improved, but it still does not cover the highest-risk cross-round paths. There is still no explicit cycle-2 (`c2` / `c2f1`) prompt or end-to-end coverage, no test that independent validators are blocked from reading the new `specs/reviews/validation/` namespace, and no test that newly added untracked files appear in validation diffs.

References: [specs/design.md:488](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L488), [specs/design.md:520](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L520), [specs/design.md:528](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L528), [specs/design.md:552](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L552)

Recommendation: Add tests for `c2` and `c2f1` paths, round-2 validation-fix input refresh, denylisting of `specs/reviews/validation/`, and validation diff behavior when the implementation adds new untracked files.

## Newly Identified Issues

### Issue 1
Severity: High

Description: The prompt-level denylist for independent validation does not include the new `specs/reviews/validation/` directory. That means cycle-2 "independent" validators can still read cycle-1 validation reviews, Claude responses, and fix reviews directly from the workspace, even under the design's softer prompt-only isolation model. This is a new gap introduced by the validation namespace itself.

References: [specs/design.md:84](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L84), [specs/design.md:126](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L126), [specs/design.md:475](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L475), [specs/design.md:577](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L577), [specs/design.md:596](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L596)

Recommendation: Extend the independent-validation prompts and `AGENTS.md` to prohibit reads from `specs/reviews/validation/` as well. Preferably, solve this together with hard filesystem isolation so the prohibition is enforced rather than advisory.

### Issue 2
Severity: High

Description: The new `append_diff_section()` helper builds validation code context with plain `git diff "$baseline_sha"`, which excludes untracked files. Regular Claude code review explicitly stages all changes before diffing, so new source or test files are visible there. Independent code validation and `validation-fix` prompts, by contrast, can omit an entire newly added file from the review context.

References: [specs/design.md:294](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L294), [specs/design.md:323](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L323), [specs/design.md:345](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L345), [specs/design.md:604](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L604), [review-loop.md:165](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/commands/review-loop.md#L165), [review-loop.md:166](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/commands/review-loop.md#L166)

Recommendation: Assemble validation diffs with the same semantics as the regular code-review path, using a temporary index or another explicit mechanism that includes newly created files without mutating the real index.

### Issue 3
Severity: High

Description: The verify/output control flow is internally inconsistent. The flow diagram says verify runs only if validation or the regular loop "used all rounds," the inserted stage sections say to proceed to verify "if applicable," the verification scenarios show verify running after every validation outcome, and the existing command contract still gates verify on exhausting all five regular rounds. The user-facing completion strings are equally ambiguous: the new unresolved-validation messages are added without replacing the original standard stage-complete outputs.

References: [specs/design.md:32](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L32), [specs/design.md:38](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L38), [specs/design.md:399](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L399), [specs/design.md:443](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L443), [specs/design.md:612](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L612), [specs/design.md:617](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L617), [review-loop.md:122](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/commands/review-loop.md#L122), [review-loop.md:132](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/commands/review-loop.md#L132), [review-loop.md:175](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/commands/review-loop.md#L175), [review-loop.md:179](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/commands/review-loop.md#L179)

Recommendation: Replace the affected design-stage and code-stage algorithms end-to-end instead of inserting partial sections. Define one exact verify predicate per stage and one final user-visible output path per terminal outcome.

### Issue 4
Severity: High

Description: The design converts infrastructure failure into a false "no issues found" result. After two failed validation attempts, the cycle is skipped and treated as success-equivalent, and the scenarios then describe the workflow continuing normally. That means the system can report a clean validation outcome even when no independent validation ran at all.

References: [specs/design.md:380](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L380), [specs/design.md:383](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L383), [specs/design.md:421](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L421), [specs/design.md:423](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L423), [specs/design.md:608](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L608), [specs/design.md:621](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L621)

Recommendation: Represent double-failure as a distinct `validation_unavailable` or unresolved state, surface it in the final output, and avoid treating it as a successful validation pass.

### Issue 5
Severity: Medium

Description: The artifact naming contract is internally inconsistent. The "Artifact Naming Convention" section says fix artifacts use `design-c<cycle>-fix-<fix-round>-...` and `code-c<cycle>-fix-<fix-round>-...`, but the round tokens, expected output paths, flow examples, tests, and artifact layout all use compact `c<cycle>f<fix-round>` filenames like `design-c1f1-codex-review.md`.

References: [specs/design.md:24](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L24), [specs/design.md:25](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L25), [specs/design.md:281](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L281), [specs/design.md:389](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L389), [specs/design.md:533](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L533), [specs/design.md:580](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L580)

Recommendation: Normalize the spec to a single naming scheme everywhere. If `c<cycle>f<fix-round>` is the real machine contract, update the prose examples to match it exactly.
