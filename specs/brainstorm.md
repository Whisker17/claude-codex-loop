# Review Loop v2.1 Brainstorm

## Task

Implement review-loop v2.1 changes as described in `specs/2026-03-21-review-loop-v2.1-design.md`.

## Context

Two production issues discovered with v2:

1. **Attention narrowing**: Review rounds progressively narrow scope to previously found issues. The final "APPROVED" means "those specific issues are fixed" rather than "the document is clean."
2. **Superpowers conflict**: The `superpowers:brainstorming` skill intercepts the design-writing step and breaks the review-loop pipeline.

## Approach

Incremental, backwards-compatible changes to four files:

### 1. `review-loop/prompts/design-review.md`
- Add explicit full-audit mandate: "Every round is a full audit. Review the entire document as if seeing it for the first time."
- Add new audit criteria: interface consistency, completeness of new additions
- Require output format separating "previously identified" from "newly identified" issues
- Add constraints about not modifying files

### 2. `review-loop/scripts/common.sh` — `build_prompt()`
- For verify rounds (`round == "verify"`): prepend "FULL INDEPENDENT REVIEW" header and omit all prior review context
- For regular rounds (1-5): keep existing behavior (include previous round context)
- Apply to both design-review and code-fix modes

### 3. `review-loop/commands/review-loop.md`
- Add optional brainstorming stage (Stage 0) before state/branch creation
- Detection: check if `superpowers:brainstorming` is in available skills
- If available: invoke skill, save to `specs/brainstorm.md`, wait for confirmation, suppress for rest of workflow
- If not available: skip to design stage
- Design stage uses `specs/brainstorm.md` as primary input if it exists
- Add fresh-review instructions for code stage reviews
- Update stage transition to include `specs/brainstorm.md` in git add
- State file phase starts at `brainstorm` or `design` accordingly

### 4. `review-loop/AGENTS.md`
- Document three-stage workflow (brainstorm → design → code)
- Note brainstorming is optional

## Key Constraints

- No structural changes to scripts, state file format, or file layout
- Existing v2 sessions unaffected
- Prompt content changes only apply to newly launched rounds
- `verify` round value already supported by `validate_round()` in common.sh
