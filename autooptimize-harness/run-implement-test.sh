#!/usr/bin/env bash
#
# run-implement-test.sh — test code-implement prompt by giving codex a spec
# and evaluating the produced code quality
#
# Usage: run-implement-test.sh --prompt <prompt-file> --fixture-dir <dir> [--output-dir <dir>] [--run-id <id>]
#
# For each sample-spec-*.md in the fixture dir, runs codex exec with the
# code-implement prompt and evaluates the output code against eval criteria.
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
  echo "Usage: run-implement-test.sh --prompt <file> --fixture-dir <dir>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/autooptimize-review-loop/prompt-runs}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"

PROMPT_FILE="$(cd "$(dirname "$PROMPT_FILE")" && pwd)/$(basename "$PROMPT_FILE")"
FIXTURE_DIR="$(cd "$FIXTURE_DIR" && pwd)"
PROMPT_NAME="$(basename "$PROMPT_FILE" .md)"

command -v codex >/dev/null 2>&1 || { echo "Error: codex CLI not found" >&2; exit 1; }

RUN_OUTPUT_DIR="${OUTPUT_DIR}/${PROMPT_NAME}/${RUN_ID}"
mkdir -p "$RUN_OUTPUT_DIR"

echo "=== implement prompt test ==="
echo "Prompt:  $PROMPT_FILE"
echo "Fixture: $FIXTURE_DIR"
echo "Run ID:  $RUN_ID"
echo "Output:  $RUN_OUTPUT_DIR"
echo "=============================="

TOTAL_SCORE=0
TOTAL_MAX=0
TOTAL_FIXTURES=0

for SPEC_FILE in "$FIXTURE_DIR"/sample-spec-*.md; do
  [[ -f "$SPEC_FILE" ]] || continue

  NUM="$(basename "$SPEC_FILE" | sed 's/sample-spec-\(.*\)\.md/\1/')"
  EVAL_FILE="${FIXTURE_DIR}/eval-criteria-${NUM}.json"
  FIXTURE_NAME="sample-spec-${NUM}"

  if [[ ! -f "$EVAL_FILE" ]]; then
    echo "WARNING: no eval-criteria for $SPEC_FILE, skipping"
    continue
  fi

  TOTAL_FIXTURES=$((TOTAL_FIXTURES + 1))
  echo ""
  echo "--- Fixture: $FIXTURE_NAME ---"

  PROMPT_TEMPLATE="$(<"$PROMPT_FILE")"
  SPEC_CONTENT="$(<"$SPEC_FILE")"

  FULL_PROMPT="${PROMPT_TEMPLATE}

## Design Document
\`\`\`md
${SPEC_CONTENT}
\`\`\`

Implement the code now. Create the source files and test files as described in the spec."

  # Create temp workspace
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/implement-test-XXXXXX")"
  mkdir -p "$TEMP_DIR/specs"
  cp "$SPEC_FILE" "$TEMP_DIR/specs/design.md"
  cd "$TEMP_DIR"
  git init -q
  git config user.name test
  git config user.email test@test
  git add .
  git commit -q -m "init"

  echo "  Running codex exec..."
  START_TIME=$(date +%s)

  set +e
  codex exec --full-auto "$FULL_PROMPT" -C "$TEMP_DIR" > "${RUN_OUTPUT_DIR}/${FIXTURE_NAME}-codex-stdout.log" 2>&1
  CODEX_EXIT=$?
  set -e

  END_TIME=$(date +%s)
  ELAPSED=$((END_TIME - START_TIME))
  echo "  codex exec finished in ${ELAPSED}s (exit: $CODEX_EXIT)"

  # Collect produced code
  CODE_OUTPUT_DIR="${RUN_OUTPUT_DIR}/${FIXTURE_NAME}-code"
  mkdir -p "$CODE_OUTPUT_DIR"
  # Copy all non-git, non-spec files
  find "$TEMP_DIR" -type f \
    -not -path '*/.git/*' \
    -not -path '*/specs/*' \
    -not -name '.gitignore' \
    | while IFS= read -r f; do
      REL="${f#$TEMP_DIR/}"
      mkdir -p "$CODE_OUTPUT_DIR/$(dirname "$REL")"
      cp "$f" "$CODE_OUTPUT_DIR/$REL"
    done

  # Run evals using claude as judge
  EVAL_COUNT="$(jq '.criteria | length' "$EVAL_FILE")"
  PASSED=0

  # Gather all code for the judge
  ALL_CODE=""
  while IFS= read -r f; do
    ALL_CODE+="--- $(basename "$f") ---
$(cat "$f")

"
  done < <(find "$CODE_OUTPUT_DIR" -type f -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.go' 2>/dev/null | sort)

  if [[ -z "$ALL_CODE" ]]; then
    echo "  WARNING: no code files produced"
    ALL_CODE="(no code produced)"
  fi

  for i in $(seq 0 $((EVAL_COUNT - 1))); do
    CRITERIA_NAME="$(jq -r ".criteria[$i].name" "$EVAL_FILE")"
    CRITERIA_QUESTION="$(jq -r ".criteria[$i].question" "$EVAL_FILE")"

    JUDGE_RESULT="$(claude -p "You are an eval judge. Answer ONLY 'PASS' or 'FAIL', nothing else.

Design specification:
${SPEC_CONTENT}

Produced code:
${ALL_CODE}

Question: ${CRITERIA_QUESTION}" 2>/dev/null || echo "FAIL")"

    if echo "$JUDGE_RESULT" | grep -qi "PASS"; then
      echo "    [PASS] $CRITERIA_NAME"
      PASSED=$((PASSED + 1))
    else
      echo "    [FAIL] $CRITERIA_NAME"
    fi
  done

  echo "  Score: ${PASSED}/${EVAL_COUNT}"
  TOTAL_SCORE=$((TOTAL_SCORE + PASSED))
  TOTAL_MAX=$((TOTAL_MAX + EVAL_COUNT))

  cat > "${RUN_OUTPUT_DIR}/${FIXTURE_NAME}-result.json" <<RESULT
{
  "fixture": "$FIXTURE_NAME",
  "passed": $PASSED,
  "total": $EVAL_COUNT,
  "elapsed_seconds": $ELAPSED,
  "codex_exit": $CODEX_EXIT
}
RESULT

  rm -rf "$TEMP_DIR"
done

# Summary
if (( TOTAL_MAX > 0 )); then
  PASS_RATE="$(awk "BEGIN {printf \"%.1f\", ($TOTAL_SCORE / $TOTAL_MAX) * 100}")"
else
  PASS_RATE="0.0"
fi

cat > "${RUN_OUTPUT_DIR}/summary.json" <<SUMMARY
{
  "prompt": "$PROMPT_NAME",
  "run_id": "$RUN_ID",
  "fixtures": $TOTAL_FIXTURES,
  "total_passed": $TOTAL_SCORE,
  "total_max": $TOTAL_MAX,
  "pass_rate": $PASS_RATE,
  "timestamp": "$(date -u +%FT%TZ)"
}
SUMMARY

echo ""
echo "=============================="
echo "Total: ${TOTAL_SCORE}/${TOTAL_MAX} (${PASS_RATE}%)"
echo "Results: ${RUN_OUTPUT_DIR}/"
echo "=============================="
