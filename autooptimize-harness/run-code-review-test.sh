#!/usr/bin/env bash
#
# run-code-review-test.sh — test a code review prompt against fixture inputs
#
# Usage: run-code-review-test.sh --prompt <prompt-file> --fixture-dir <dir> [--output-dir <dir>] [--run-id <id>]
#
# For each sample-code-*.py + sample-spec-*.md pair in the fixture dir,
# runs codex exec with the prompt, collects the review output, and scores
# it against known-issues-*.json.
#
set -euo pipefail

PROMPT_FILE=""
FIXTURE_DIR=""
OUTPUT_DIR=""
RUN_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt)      PROMPT_FILE="$2"; shift 2 ;;
    --fixture-dir) FIXTURE_DIR="$2"; shift 2 ;;
    --output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
    --run-id)      RUN_ID="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PROMPT_FILE" || -z "$FIXTURE_DIR" ]]; then
  echo "Usage: run-code-review-test.sh --prompt <file> --fixture-dir <dir>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/autooptimize-review-loop/prompt-runs}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"

# Resolve to absolute paths
PROMPT_FILE="$(cd "$(dirname "$PROMPT_FILE")" && pwd)/$(basename "$PROMPT_FILE")"
FIXTURE_DIR="$(cd "$FIXTURE_DIR" && pwd)"
PROMPT_NAME="$(basename "$PROMPT_FILE" .md)"

command -v codex >/dev/null 2>&1 || { echo "Error: codex CLI not found" >&2; exit 1; }

RUN_OUTPUT_DIR="${OUTPUT_DIR}/${PROMPT_NAME}/${RUN_ID}"
mkdir -p "$RUN_OUTPUT_DIR"

echo "=== code review prompt test ==="
echo "Prompt:  $PROMPT_FILE"
echo "Fixture: $FIXTURE_DIR"
echo "Run ID:  $RUN_ID"
echo "Output:  $RUN_OUTPUT_DIR"
echo "================================"

TOTAL_FOUND=0
TOTAL_KNOWN=0
TOTAL_FIXTURES=0

for CODE_FILE in "$FIXTURE_DIR"/sample-code-*.py; do
  [[ -f "$CODE_FILE" ]] || continue

  NUM="$(basename "$CODE_FILE" | sed 's/sample-code-\(.*\)\.py/\1/')"
  SPEC_FILE="${FIXTURE_DIR}/sample-spec-${NUM}.md"
  KNOWN_FILE="${FIXTURE_DIR}/known-issues-${NUM}.json"
  FIXTURE_NAME="sample-code-${NUM}"

  if [[ ! -f "$SPEC_FILE" ]]; then
    echo "WARNING: no spec file for $CODE_FILE, skipping"
    continue
  fi
  if [[ ! -f "$KNOWN_FILE" ]]; then
    echo "WARNING: no known-issues file for $CODE_FILE, skipping"
    continue
  fi

  TOTAL_FIXTURES=$((TOTAL_FIXTURES + 1))
  echo ""
  echo "--- Fixture: $FIXTURE_NAME ---"

  # Read files
  PROMPT_TEMPLATE="$(<"$PROMPT_FILE")"
  SPEC_CONTENT="$(<"$SPEC_FILE")"
  CODE_CONTENT="$(<"$CODE_FILE")"

  FULL_PROMPT="${PROMPT_TEMPLATE}

## Design Specification
\`\`\`md
${SPEC_CONTENT}
\`\`\`

## Code to Review
\`\`\`python
${CODE_CONTENT}
\`\`\`

## Required Output Path
review-output.md"

  # Create temp workspace with code and spec
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/code-review-test-XXXXXX")"
  mkdir -p "$TEMP_DIR/specs"
  cp "$SPEC_FILE" "$TEMP_DIR/specs/design.md"
  cp "$CODE_FILE" "$TEMP_DIR/$(basename "$CODE_FILE")"
  cd "$TEMP_DIR"
  git init -q
  git config user.name test
  git config user.email test@test
  git add .
  git commit -q -m "init"

  # Run codex
  REVIEW_OUTPUT="${RUN_OUTPUT_DIR}/${FIXTURE_NAME}-review.md"
  echo "  Running codex exec..."
  START_TIME=$(date +%s)

  set +e
  codex exec --full-auto "$FULL_PROMPT" -C "$TEMP_DIR" > "${RUN_OUTPUT_DIR}/${FIXTURE_NAME}-codex-stdout.log" 2>&1
  CODEX_EXIT=$?
  set -e

  END_TIME=$(date +%s)
  ELAPSED=$((END_TIME - START_TIME))
  echo "  codex exec finished in ${ELAPSED}s (exit: $CODEX_EXIT)"

  # Collect review output
  if [[ -f "$TEMP_DIR/review-output.md" ]]; then
    cp "$TEMP_DIR/review-output.md" "$REVIEW_OUTPUT"
  else
    FOUND_MD="$(find "$TEMP_DIR" -name '*.md' -newer "$TEMP_DIR/specs/design.md" -not -path '*/specs/*' -type f 2>/dev/null | head -1)"
    if [[ -n "$FOUND_MD" ]]; then
      cp "$FOUND_MD" "$REVIEW_OUTPUT"
    else
      # Fall back to codex stdout
      cp "${RUN_OUTPUT_DIR}/${FIXTURE_NAME}-codex-stdout.log" "$REVIEW_OUTPUT"
      echo "  NOTE: using codex stdout as review output"
    fi
  fi

  rm -rf "$TEMP_DIR"

  # Score
  REVIEW_TEXT="$(<"$REVIEW_OUTPUT")"
  KNOWN_COUNT="$(jq '.known_issues | length' "$KNOWN_FILE")"
  FOUND=0

  while IFS= read -r issue_id; do
    ISSUE_DESC="$(jq -r ".known_issues[] | select(.id == \"$issue_id\") | .description" "$KNOWN_FILE")"

    JUDGE_RESULT="$(claude -p "You are an eval judge. Answer ONLY 'FOUND' or 'NOT_FOUND', nothing else.

Known issue to look for:
ID: ${issue_id}
Description: ${ISSUE_DESC}

Review output:
${REVIEW_TEXT}

Question: Did the review output identify or discuss this specific issue (even if using different wording)? Answer FOUND if the core concern is addressed anywhere in the review." 2>/dev/null || echo "NOT_FOUND")"

    if echo "$JUDGE_RESULT" | grep -qi "FOUND"; then
      echo "    [FOUND]     $issue_id"
      FOUND=$((FOUND + 1))
    else
      echo "    [NOT_FOUND] $issue_id"
    fi
  done < <(jq -r '.known_issues[].id' "$KNOWN_FILE")

  echo "  Score: ${FOUND}/${KNOWN_COUNT} known issues found"
  TOTAL_FOUND=$((TOTAL_FOUND + FOUND))
  TOTAL_KNOWN=$((TOTAL_KNOWN + KNOWN_COUNT))

  cat > "${RUN_OUTPUT_DIR}/${FIXTURE_NAME}-result.json" <<RESULT
{
  "fixture": "$FIXTURE_NAME",
  "found": $FOUND,
  "total": $KNOWN_COUNT,
  "elapsed_seconds": $ELAPSED,
  "codex_exit": $CODEX_EXIT
}
RESULT

done

# Summary
if (( TOTAL_KNOWN > 0 )); then
  PASS_RATE="$(awk "BEGIN {printf \"%.1f\", ($TOTAL_FOUND / $TOTAL_KNOWN) * 100}")"
else
  PASS_RATE="0.0"
fi

cat > "${RUN_OUTPUT_DIR}/summary.json" <<SUMMARY
{
  "prompt": "$PROMPT_NAME",
  "run_id": "$RUN_ID",
  "fixtures": $TOTAL_FIXTURES,
  "total_found": $TOTAL_FOUND,
  "total_known": $TOTAL_KNOWN,
  "pass_rate": $PASS_RATE,
  "timestamp": "$(date -u +%FT%TZ)"
}
SUMMARY

echo ""
echo "================================"
echo "Total: ${TOTAL_FOUND}/${TOTAL_KNOWN} (${PASS_RATE}%)"
echo "Results: ${RUN_OUTPUT_DIR}/"
echo "================================"
