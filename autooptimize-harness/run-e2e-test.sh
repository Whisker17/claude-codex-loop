#!/usr/bin/env bash
#
# run-e2e-test.sh — run full review-loop pipeline, then execute produced code
#
# Usage: run-e2e-test.sh <scenario-file> [--run-id <id>]
#
# Runs the complete review-loop via claude -p, collects all artifacts,
# then actually runs the produced code and tests to verify correctness.
#
set -euo pipefail

SCENARIO_FILE=""
RUN_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id) RUN_ID="$2"; shift 2 ;;
    -*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *)  SCENARIO_FILE="$1"; shift ;;
  esac
done

if [[ -z "$SCENARIO_FILE" ]]; then
  echo "Usage: run-e2e-test.sh <scenario-file> [--run-id <id>]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_DIR="${PROJECT_ROOT}/review-loop"
COMMAND_FILE="${PLUGIN_DIR}/commands/review-loop.md"
SCENARIO_FILE="$(cd "$(dirname "$SCENARIO_FILE")" && pwd)/$(basename "$SCENARIO_FILE")"
SCENARIO_NAME="$(basename "$SCENARIO_FILE" .txt)"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
TASK="$(<"$SCENARIO_FILE")"

OUTPUT_DIR="${PROJECT_ROOT}/autooptimize-review-loop/e2e/${SCENARIO_NAME}/${RUN_ID}"
mkdir -p "$OUTPUT_DIR"

echo "=== E2E pipeline test ==="
echo "Scenario: $SCENARIO_NAME"
echo "Run ID:   $RUN_ID"
echo "Task:     $TASK"
echo "Output:   $OUTPUT_DIR"
echo "========================="

# --- 1. Create isolated project ---
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/e2e-test-XXXXXX")"
PROJECT_DIR="${TEMP_DIR}/project"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

git init -q
git config user.name "e2e-test"
git config user.email "e2e@test.local"
echo "# Test Project" > README.md
git add README.md
git commit -q -m "initial commit"

echo "[$(date -u +%FT%TZ)] Created project at $PROJECT_DIR"

# --- 2. Run review-loop ---
echo "[$(date -u +%FT%TZ)] Starting review-loop..."
PIPELINE_START=$(date +%s)

set +e
claude -p "Task: ${TASK}" \
  --system-prompt-file "$COMMAND_FILE" \
  --append-system-prompt "CRITICAL AUTOMATION RULES: This is an automated test. 1) Skip brainstorming — proceed directly to design. 2) Auto-confirm all gates — proceed to code stage immediately after design completes. 3) Complete the full pipeline without stopping." \
  --dangerously-skip-permissions \
  2>&1 | tee "$OUTPUT_DIR/claude-output.log"
PIPELINE_EXIT=${PIPESTATUS[0]}
set -e

PIPELINE_END=$(date +%s)
PIPELINE_DURATION=$((PIPELINE_END - PIPELINE_START))
echo "[$(date -u +%FT%TZ)] Pipeline finished in ${PIPELINE_DURATION}s (exit: $PIPELINE_EXIT)"

# --- 3. Collect artifacts ---
[[ -f specs/design.md ]] && cp specs/design.md "$OUTPUT_DIR/design.md"
[[ -d specs/reviews ]] && cp -r specs/reviews "$OUTPUT_DIR/reviews"

BRANCH="$(git branch --show-current 2>/dev/null || echo "unknown")"
BASELINE_SHA="$(git log --format=%H --reverse | head -1)"

# Collect source code
mkdir -p "$OUTPUT_DIR/source"
find . -type f \( -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.go' \) \
  -not -path './.git/*' | while IFS= read -r f; do
  mkdir -p "$OUTPUT_DIR/source/$(dirname "$f")"
  cp "$f" "$OUTPUT_DIR/source/$f"
done

# Count review rounds
DESIGN_ROUNDS=$(find specs/reviews/design -name 'round-*-codex-review.md' -type f 2>/dev/null | wc -l | tr -d ' ')
CODE_ROUNDS=$(find specs/reviews/code -name 'round-*-claude-review.md' -type f 2>/dev/null | wc -l | tr -d ' ')
VALIDATION_FILES=$(find specs/reviews/validation -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')

echo "[$(date -u +%FT%TZ)] Artifacts: design_rounds=$DESIGN_ROUNDS code_rounds=$CODE_ROUNDS validation_files=$VALIDATION_FILES"

# --- 4. Execute produced code ---
echo ""
echo "=== Code execution tests ==="

TESTS_FOUND=false
TESTS_PASSED=false
CODE_RUNS=false
TEST_OUTPUT=""
RUN_OUTPUT=""

# Check if Python code exists
PY_FILES=$(find . -name '*.py' -not -path './.git/*' -not -path './specs/*' | head -20)
if [[ -z "$PY_FILES" ]]; then
  echo "  No Python files found"
else
  echo "  Python files:"
  echo "$PY_FILES" | sed 's/^/    /'

  # Try to run tests
  TEST_FILES=$(find . -name 'test_*.py' -o -name '*_test.py' | grep -v '.git' | head -10)
  if [[ -n "$TEST_FILES" ]]; then
    TESTS_FOUND=true
    echo "  Test files:"
    echo "$TEST_FILES" | sed 's/^/    /'

    # Install dependencies if requirements.txt exists
    if [[ -f requirements.txt ]]; then
      echo "  Installing dependencies..."
      pip install -r requirements.txt -q 2>"$OUTPUT_DIR/pip-stderr.log" || true
    fi

    # Try common test frameworks
    echo "  Running tests..."
    set +e
    if command -v python3 >/dev/null 2>&1; then
      PYTHON=python3
    else
      PYTHON=python
    fi

    # Try pytest first, fall back to unittest
    TEST_OUTPUT=$($PYTHON -m pytest -v --tb=short 2>&1) || \
    TEST_OUTPUT=$($PYTHON -m unittest discover -v 2>&1)
    TEST_EXIT=$?
    set -e

    echo "$TEST_OUTPUT" > "$OUTPUT_DIR/test-output.log"

    if [[ $TEST_EXIT -eq 0 ]]; then
      TESTS_PASSED=true
      echo "  TESTS PASSED"
    else
      echo "  TESTS FAILED (exit: $TEST_EXIT)"
      echo "$TEST_OUTPUT" | tail -20 | sed 's/^/    /'
    fi
  else
    echo "  No test files found"
  fi

  # Try to run main code (syntax check at minimum)
  MAIN_FILE=""
  for candidate in main.py app.py calc.py hello.py server.py cli.py; do
    [[ -f "$candidate" ]] && MAIN_FILE="$candidate" && break
  done
  # Also check for files with if __name__ == "__main__"
  if [[ -z "$MAIN_FILE" ]]; then
    MAIN_FILE=$(grep -rl 'if __name__' . --include='*.py' 2>/dev/null | grep -v test | grep -v '.git' | head -1)
  fi

  if [[ -n "$MAIN_FILE" ]]; then
    echo "  Syntax check: $MAIN_FILE"
    set +e
    RUN_OUTPUT=$($PYTHON -c "import ast; ast.parse(open('$MAIN_FILE').read()); print('SYNTAX OK')" 2>&1)
    RUN_EXIT=$?
    set -e

    echo "$RUN_OUTPUT" > "$OUTPUT_DIR/run-output.log"
    if [[ $RUN_EXIT -eq 0 ]]; then
      CODE_RUNS=true
      echo "  SYNTAX OK"
    else
      echo "  SYNTAX ERROR"
      echo "$RUN_OUTPUT" | sed 's/^/    /'
    fi
  fi
fi

# --- 5. Write results ---
cat > "$OUTPUT_DIR/results.json" <<RESULTS
{
  "scenario": "$SCENARIO_NAME",
  "run_id": "$RUN_ID",
  "pipeline_exit": $PIPELINE_EXIT,
  "pipeline_duration_s": $PIPELINE_DURATION,
  "design_rounds": $DESIGN_ROUNDS,
  "code_rounds": $CODE_ROUNDS,
  "validation_files": $VALIDATION_FILES,
  "branch": "$BRANCH",
  "tests_found": $TESTS_FOUND,
  "tests_passed": $TESTS_PASSED,
  "code_runs": $CODE_RUNS,
  "timestamp": "$(date -u +%FT%TZ)"
}
RESULTS

echo ""
echo "========================="
echo "Results:"
echo "  Pipeline:    exit=$PIPELINE_EXIT duration=${PIPELINE_DURATION}s"
echo "  Rounds:      design=$DESIGN_ROUNDS code=$CODE_ROUNDS validation=$VALIDATION_FILES"
echo "  Code runs:   $CODE_RUNS"
echo "  Tests found: $TESTS_FOUND"
echo "  Tests pass:  $TESTS_PASSED"
echo "========================="
echo "Full output: $OUTPUT_DIR/"

# Cleanup
rm -rf "$TEMP_DIR"
