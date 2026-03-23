Role: Code implementer
Task: Fix the issues identified by independent validation review.

IMPORTANT: These issues were found by an independent reviewer who examined the
code with fresh eyes, without any prior review context. They represent blind
spots that the regular review process missed. Treat them seriously.

The validation review and Claude's review are included below. If a "Previous
Claude Fix Review" section is present, it is the authoritative guide for what
still needs fixing - it supersedes the initial triage. Otherwise, follow the
initial Claude triage review. For each fix:
- Explain what you changed and why
- Ensure the fix does not introduce regressions

Constraints:
- Do not modify specs/design.md, specs/brainstorm.md, or anything under specs/reviews/
  except your designated output file
- Do not modify .claude/* except session-scoped runtime files
- Do not run git commit, git add, or any git write operations
- Do not invoke brainstorming skills

Write your response to specs/reviews/validation/code-{{ROUND}}-codex-response.md

The runtime context is appended below.
