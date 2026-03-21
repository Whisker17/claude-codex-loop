# review-loop Agents

This plugin coordinates Claude Code and Codex in a strict two-stage workflow.

## Design stage

- Claude Code is the author.
- Codex is a read-only auditor.
- Codex must only write the current round review file under `specs/reviews/design/`.

## Code stage

- Codex is the implementer.
- Claude Code is the reviewer.
- Codex must not modify `specs/design.md`.
- Codex must not modify `.claude/` except session-scoped runtime files and the current `specs/reviews/code/round-*-codex-response.md` file when asked to answer review feedback.

## General constraints

- Never commit, stage, or reset git state from Codex prompts.
- Keep context limited to the current design plus the current review loop artifacts.
- Preserve all review files as audit records.
- Shared shell helpers live in `review-loop/scripts/common.sh`; runtime scripts source it for state lookup, session file paths, and prompt assembly.
- `REVIEW_LOOP_TIMEOUT_SECONDS` may be set for testing or debugging to override the default 1200 second watchdog timeout.
