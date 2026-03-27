#!/usr/bin/env bash
#
# run-prompt-test.sh — test a single prompt against fixture inputs
#
# Usage: run-prompt-test.sh --prompt <prompt-file> --fixture-dir <dir> [--output-dir <dir>] [--run-id <id>]
#
# For each sample-design-*.md in the fixture dir, runs codex exec with the
# prompt, collects the review output, and scores it against known-issues-*.json.
#
# Each codex exec call takes ~1-3 minutes.
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
  echo "Usage: run-prompt-test.sh --prompt <file> --fixture-dir <dir>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/autooptimize-review-loop/prompt-runs}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"

# Resolve all paths to absolute before we cd anywhere
PROMPT_FILE="$(cd "$(dirname "$PROMPT_FILE")" && pwd)/$(basename "$PROMPT_FILE")"
FIXTURE_DIR="$(cd "$FIXTURE_DIR" && pwd)"
PROMPT_NAME="$(basename "$PROMPT_FILE" .md)"

command -v codex >/dev/null 2>&1 || { echo "Error: codex CLI not found" >&2; exit 1; }

RUN_OUTPUT_DIR="${OUTPUT_DIR}/${PROMPT_NAME}/${RUN_ID}"
mkdir -p "$RUN_OUTPUT_DIR"

echo "=== prompt test ==="
echo "Prompt:  $PROMPT_FILE"
echo "Fixture: $FIXTURE_DIR"
echo "Run ID:  $RUN_ID"
echo "Output:  $RUN_OUTPUT_DIR"
echo "==================="

TOTAL_FOUND=0
TOTAL_KNOWN=0
TOTAL_FIXTURES=0

for SAMPLE in "$FIXTURE_DIR"/sample-design-*.md; do
  [[ -f "$SAMPLE" ]] || continue

  NUM="$(basename "$SAMPLE" | sed 's/sample-design-\(.*\)\.md/\1/')"
  KNOWN_FILE="${FIXTURE_DIR}/known-issues-${NUM}.json"
  FIXTURE_NAME="$(basename "$SAMPLE" .md)"

  if [[ ! -f "$KNOWN_FILE" ]]; then
    echo "WARNING: no known-issues file for $SAMPLE, skipping"
    continue
  fi

  TOTAL_FIXTURES=$((TOTAL_FIXTURES + 1))
  echo ""
  echo "--- Fixture: $FIXTURE_NAME ---"

  # Build the full prompt: template + design content
  PROMPT_TEMPLATE="$(<"$PROMPT_FILE")"
  DESIGN_CONTENT="$(<"$SAMPLE")"

  FULL_PROMPT="${PROMPT_TEMPLATE}

## Design Document
\`\`\`md
${DESIGN_CONTENT}
\`\`\`

## Required Output Path
review-output.md"

  # Create a temp workspace
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/prompt-test-XXXXXX")"

  # Copy the design into the workspace so codex can read it
  mkdir -p "$TEMP_DIR/specs"
  cp "$SAMPLE" "$TEMP_DIR/specs/design.md"
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
  elif [[ -f "$TEMP_DIR/specs/reviews/design/round-1-codex-review.md" ]]; then
    cp "$TEMP_DIR/specs/reviews/design/round-1-codex-review.md" "$REVIEW_OUTPUT"
  else
    # Try to find any .md file created by codex
    FOUND_MD="$(find "$TEMP_DIR" -name '*.md' -newer "$TEMP_DIR/specs/design.md" -type f 2>/dev/null | head -1)"
    if [[ -n "$FOUND_MD" ]]; then
      cp "$FOUND_MD" "$REVIEW_OUTPUT"
    else
      echo "  WARNING: no review output found"
      echo "(no review output)" > "$REVIEW_OUTPUT"
    fi
  fi

  rm -rf "$TEMP_DIR"

  # Score: how many known issues were found?
  REVIEW_TEXT="$(<"$REVIEW_OUTPUT")"
  KNOWN_COUNT="$(jq '.known_issues | length' "$KNOWN_FILE")"
  FOUND=0

  while IFS= read -r issue_id; do
    ISSUE_DESC="$(jq -r ".known_issues[] | select(.id == \"$issue_id\") | .description" "$KNOWN_FILE")"

    # Use claude to judge if the review found this issue
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

  # Save per-fixture result
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

# --- Summary ---
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
echo "==================="
echo "Total: ${TOTAL_FOUND}/${TOTAL_KNOWN} (${PASS_RATE}%)"
echo "Results: ${RUN_OUTPUT_DIR}/"
echo "==================="
