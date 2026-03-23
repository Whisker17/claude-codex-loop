# Design Audit

## Previously Identified Issues

None. No prior review context was provided for this round-1 audit.

## Newly Identified Issues

### Issue 1
Severity: Critical

Description: The design reuses `round-<fix-round>` identifiers for validation fix loops, which breaks artifact identity and, in the code stage, points `validation-fix` at the wrong validation review. Design-stage fix rounds are specified as `design-review <fix-round>` with independent numbering starting from 1, but they still write `specs/reviews/design/round-<fix-round>-codex-review.md`, which collides with the already-used main design-review artifacts. Code-stage fix rounds have the same problem in the validation namespace: `validation-fix <fix-round>` reads `code-round-$round-review.md` and writes `code-round-$round-codex-response.md`, so validation cycle 2 / fix round 1 would read cycle 1's review and overwrite cycle 1's response.

References: [specs/design.md:121](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L121), [specs/design.md:167](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L167), [specs/design.md:205](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L205), [specs/design.md:242](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L242), [specs/design.md:248](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L248), [specs/design.md:252](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L252), [specs/design.md:285](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L285), [specs/design.md:292](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L292), [specs/design.md:298](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L298), [specs/design.md:415](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L415)

Recommendation: Introduce a distinct validation-fix identity that includes both validation cycle and fix round in filenames and prompt lookup, or persist the active validation cycle in state and derive artifact paths from that state. Do not reuse the main `round-N` namespace for post-validation fix loops.

### Issue 2
Severity: High

Description: The design-stage validation fix loop has no implementable path for getting `## Validation Findings` into Codex's prompt. The spec says `run-review-bg.sh design-review <fix-round>` should include an additional `## Validation Findings` section, but also says this is handled by Claude orchestration without changes to `build_prompt()`. The current prompt builder only assembles prompts from the mode, round, state, and predefined file sections; there is no API for Claude to inject ad hoc content into a background Codex invocation.

References: [specs/design.md:244](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L244), [specs/design.md:245](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L245), [specs/design.md:426](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L426), [common.sh:253](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/scripts/common.sh#L253), [common.sh:292](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/scripts/common.sh#L292), [run-review-bg.sh:26](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/scripts/run-review-bg.sh#L26)

Recommendation: Add an explicit mechanism for validation findings to enter prompt assembly, such as a dedicated `validation-design-fix-review` mode, or a state/file input that `build_prompt()` reads and renders for the fix loop.

### Issue 3
Severity: High

Description: The new validation sub-phases are inserted after the existing verify steps, but the design does not reconcile that with the current workflow's "verify is final" rules. In the current design stage, the verify pass says "Do NOT make further design edits regardless of findings." In the current code stage, the final verification says "This is the final artifact. Do NOT invoke Codex or perform additional iterations." The proposed validation phase immediately requires new design edits and new Codex fix iterations after those same verify steps.

References: [specs/design.md:223](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L223), [specs/design.md:240](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L240), [specs/design.md:266](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L266), [specs/design.md:287](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L287), [review-loop.md:122](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/commands/review-loop.md#L122), [review-loop.md:130](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/commands/review-loop.md#L130), [review-loop.md:175](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/commands/review-loop.md#L175), [review-loop.md:177](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/commands/review-loop.md#L177)

Recommendation: Rewrite the existing verify-step semantics in the same change. Either move independent validation before verify, or redefine verify as the terminal pass after validation has converged.

### Issue 4
Severity: High

Description: The core requirement of "zero shared review history" is not actually enforced by the proposed architecture. The validator runs in the full project workspace via `codex exec -C "$project_root" --full-auto`, and the design only prevents review-history leakage at the prompt-assembly layer. That means the independent validator can still inspect `specs/reviews/` or `.claude/` directly, which defeats the document's stated context-isolation guarantee.

References: [specs/design.md:13](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L13), [specs/design.md:15](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L15), [specs/design.md:192](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L192), [specs/design.md:197](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L197), [specs/design.md:331](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L331), [run-review-bg.sh:62](/Users/whisker/Work/src/personal/claude-codex-loop/review-loop/scripts/run-review-bg.sh#L62)

Recommendation: Run independent validation in an isolated scratch worktree or temporary directory containing only the allowed artifact(s) and task context, or add a hard access-control layer that prevents reads from prior review/history paths.

### Issue 5
Severity: Medium

Description: Validation failure handling is underspecified and can leave the workflow in an undefined state. The spec says to retry once on `TIMEOUT` or `FAILED` and "skip on second failure", but the very next step still assumes the review file exists and should be read. The stage-transition change also unconditionally adds `specs/reviews/validation/`, but `git add specs/reviews/validation/` fails with exit code 128 when that path does not exist. If both validation attempts fail before producing any file, the design does not say whether the stage should abort, continue, or complete with unresolved validation failure.

References: [specs/design.md:236](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L236), [specs/design.md:237](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L237), [specs/design.md:279](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L279), [specs/design.md:280](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L280), [specs/design.md:316](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L316), [specs/design.md:441](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L441)

Recommendation: Specify the control flow after a second validation failure: whether to abort the stage, mark validation as unresolved, or continue to the next cycle. Make stage-transition staging conditional on validation artifacts actually existing.

### Issue 6
Severity: Medium

Description: The `validation-fix` interface is internally inconsistent about what Codex should act on and what context it receives. The prompt says to address issues "marked as substantive", but the independent validation review schema does not define any substantive marker. The design has Claude write `code-round-<cycle>-claude-review.md` to summarize what needs fixing, but the `validation-fix` prompt builder does not include that file, so Codex never sees Claude's triage or any remaining feedback from a prior fix attempt.

References: [specs/design.md:109](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L109), [specs/design.md:121](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L121), [specs/design.md:205](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L205), [specs/design.md:209](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L209), [specs/design.md:283](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L283), [specs/design.md:294](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L294)

Recommendation: Define a formal triage contract for validation findings and pass it into `validation-fix`. At minimum, include the current Claude validation review and the previous Codex response in the prompt, the same way regular `code-fix` carries round-specific review context.

### Issue 7
Severity: Medium

Description: The test plan does not cover the highest-risk paths introduced by this design. The added tests exercise prompt isolation and round-1 plumbing, but they do not verify cycle-2 behavior, fix-loop artifact identity, multi-round `validation-fix` context carry-forward, or the "skip on second failure" control flow. Those are the areas most likely to regress because they depend on cross-round naming and orchestration, not just prompt text.

References: [specs/design.md:347](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L347), [specs/design.md:368](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L368), [specs/design.md:381](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L381), [specs/design.md:386](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L386), [specs/design.md:430](/Users/whisker/Work/src/personal/claude-codex-loop/specs/design.md#L430)

Recommendation: Add tests for at least: validation cycle 2 with a distinct fix round, failure/skip behavior when no validation artifact is created, and a second `validation-fix` round that must see the latest Claude review rather than only the original validation review.
