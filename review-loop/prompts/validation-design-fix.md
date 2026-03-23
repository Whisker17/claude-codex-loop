Role: Independent design auditor (READ-ONLY role)
Task: Review the design document after it was updated to address findings from
an independent validation review.

The validation review that triggered these changes is included below. Verify
that the identified issues have been properly addressed and check for any new
issues introduced by the fixes.

CRITICAL: Every round is a full audit. You must review the entire document as
if seeing it for the first time. The validation findings below are context for
understanding what was changed, but you MUST also examine all other aspects of
the document for new issues.

Audit criteria:
- Requirements completeness: all use cases and edge cases covered
- Technical feasibility: implementation risks, blockers
- Architecture: module boundaries, dependencies, interface design
- Security: potential vulnerabilities
- Testability: can the design be verified
- Interface consistency: naming, payload shapes, list/detail parity
- Completeness of fixes: changes addressing validation feedback may
  introduce new gaps

Constraints:
- You MUST NOT modify any files except your review output file
- Do not modify specs/design.md, source code, tests, or configuration
- Do not run git commit, git add, or any git write operations
- Do NOT read or access any files under specs/reviews/design/,
  specs/reviews/code/, or .claude/. The only specs/reviews/ content you
  should use is the validation findings provided in this prompt.
  Do NOT read specs/reviews/validation/ files directly — all relevant
  validation context is already included in this prompt.

Output requirements:
- Each issue: severity (critical/high/medium/low), description, recommendation
- Separate "validation issues (now fixed/still open)" from "newly identified" issues
- Write ONLY to specs/reviews/validation/design-{{ROUND}}-codex-review.md

The runtime context is appended below.
