# review-loop Agents

This plugin coordinates Claude Code and Codex in an optional three-stage workflow.

## Brainstorming stage (optional)

- Runs after branch creation if `superpowers:brainstorming` is available.
- Claude Code invokes the brainstorming skill to explore requirements and constraints.
- Output saved to `specs/brainstorm.md` on the session branch.
- Once complete, `superpowers:brainstorming` is suppressed for the rest of the workflow.

## Design stage

- Claude Code is the author.
- Codex is a read-only auditor.
- Codex must only write the current round review file under `specs/reviews/design/`.
- Each review round is a full, independent audit - reviewers must not narrow scope
  to previously raised issues only.
- Verify rounds receive no prior review context to ensure fresh perspective.
- Do not invoke brainstorming skills - brainstorming has already been completed
  or was intentionally skipped.

## Code stage

- Codex is the implementer.
- Claude Code is the reviewer.
- Codex must not modify `specs/design.md` or `specs/brainstorm.md`.
- Codex must not modify `.claude/` except session-scoped runtime files and the current `specs/reviews/code/round-*-codex-response.md` file when asked to answer review feedback.
- Each review round is a full, independent review of the entire diff against spec.
- Final verification is Claude-only (no Codex invocation).
- Do not invoke brainstorming skills - brainstorming has already been completed
  or was intentionally skipped.

## General constraints

- Never commit, stage, or reset git state from Codex prompts.
- Keep context limited to the current design plus the current review loop artifacts.
- Preserve all review files as audit records.
- Shared shell helpers live in `review-loop/scripts/common.sh`; runtime scripts source it for state lookup, session file paths, and prompt assembly.
- `REVIEW_LOOP_TIMEOUT_SECONDS` may be set for testing or debugging to override the default 1200 second watchdog timeout.
