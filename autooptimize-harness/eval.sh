#!/usr/bin/env bash
#
# eval.sh — score experiment outputs against binary eval criteria
#
# Usage: eval.sh <experiment-output-dir> <experiment-id>
#
# Uses claude -p (subscription auth) for LLM-as-judge evals.
# Writes results to eval-results.json in the experiment directory.
#
set -euo pipefail

EXPERIMENT_DIR="${1:-}"
EXPERIMENT_ID="${2:-0}"

if [[ -z "$EXPERIMENT_DIR" || ! -d "$EXPERIMENT_DIR" ]]; then
  echo "Usage: eval.sh <experiment-output-dir> <experiment-id>" >&2
  exit 1
fi

RESULTS_FILE="${EXPERIMENT_DIR}/eval-results.json"

# --- Helper: call claude as judge ---
judge() {
  local prompt="$1"
  local result
  result="$(claude -p "$prompt" 2>/dev/null || echo "FAIL")"
  if echo "$result" | grep -qi "PASS"; then
    echo 1
  else
    echo 0
  fi
}

# --- Eval functions (binary: 0 = fail, 1 = pass) ---

eval_requirements_coverage() {
  local run_dir="$1"
  local design="$run_dir/design.md"

  if [[ ! -f "$design" ]]; then
    echo 0; return
  fi

  local size
  size="$(wc -c < "$design")"
  if (( size < 100 )); then
    echo 0; return
  fi

  local task
  task="$(jq -r '.task' "$run_dir/metadata.json" 2>/dev/null || echo "")"

  judge "You are an eval judge. Answer ONLY 'PASS' or 'FAIL', nothing else.

Task description:
${task}

Design document:
$(cat "$design")

Question: Does this design document address ALL explicit requirements stated in the task description? Every requirement must be traceable to a specific section. Answer PASS only if ALL are covered."
}

eval_code_correctness() {
  local run_dir="$1"
  local diff="$run_dir/code-diff.patch"
  local changed="$run_dir/changed-files.txt"

  if [[ ! -f "$diff" ]] || [[ ! -s "$diff" ]]; then
    echo 0; return
  fi

  if [[ -f "$changed" ]]; then
    local code_files
    code_files="$(grep -cE '\.(js|ts|py|go|rs|sh|java|rb|c|cpp|h)$' "$changed" 2>/dev/null || echo 0)"
    if (( code_files == 0 )); then
      echo 0; return
    fi
  fi

  echo 1
}

eval_spec_conformance() {
  local run_dir="$1"
  local design="$run_dir/design.md"
  local diff="$run_dir/code-diff.patch"

  if [[ ! -f "$design" ]] || [[ ! -f "$diff" ]] || [[ ! -s "$diff" ]]; then
    echo 0; return
  fi

  judge "You are an eval judge. Answer ONLY 'PASS' or 'FAIL', nothing else.

Design document:
$(cat "$design")

Code diff:
$(head -500 "$diff")

Question: Does the code implementation conform to the architecture described in the design document? Check that module boundaries, naming conventions, and major interfaces match. Minor deviations are acceptable. Answer PASS if the code broadly follows the spec."
}

eval_review_effectiveness() {
  local run_dir="$1"
  local reviews_dir="$run_dir/reviews"

  if [[ ! -d "$reviews_dir" ]]; then
    echo 0; return
  fi

  local review_count
  review_count="$(find "$reviews_dir" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')"
  if (( review_count < 2 )); then
    echo 0; return
  fi

  # Check if any review mentions substantive issues
  if grep -rqi -E '(critical|high|significant|major)' "$reviews_dir" 2>/dev/null; then
    echo 1
  elif (( review_count >= 3 )); then
    echo 1
  else
    echo 0
  fi
}

eval_edge_case_handling() {
  local run_dir="$1"
  local design="$run_dir/design.md"
  local diff="$run_dir/code-diff.patch"

  if [[ ! -f "$design" ]]; then
    echo 0; return
  fi

  local code_context=""
  if [[ -f "$diff" ]] && [[ -s "$diff" ]]; then
    code_context="Code diff (first 500 lines):
$(head -500 "$diff")"
  fi

  judge "You are an eval judge. Answer ONLY 'PASS' or 'FAIL', nothing else.

Design document:
$(cat "$design")

${code_context}

Question: Does the design (and code, if present) explicitly address edge cases such as: error inputs, empty/null values, boundary conditions, concurrent access (if relevant), and failure modes? PASS requires at least 3 distinct edge cases to be explicitly handled or discussed."
}

# --- Run all evals on all scenario runs ---

echo "Evaluating experiment #${EXPERIMENT_ID}..."
echo ""

TOTAL_SCORE=0
TOTAL_MAX=0

EVAL_NAMES=("requirements_coverage" "code_correctness" "spec_conformance" "review_effectiveness" "edge_case_handling")
EVAL_PASS_COUNTS=(0 0 0 0 0)
EVAL_TOTAL_COUNTS=(0 0 0 0 0)

# Walk the output directory tree to find runs with metadata.json
while IFS= read -r metadata_file; do
  run_dir="$(dirname "$metadata_file")"

  SCENARIO_NAME="$(jq -r '.scenario' "$metadata_file" 2>/dev/null || echo "unknown")"
  RUN_ID="$(jq -r '.run_id' "$metadata_file" 2>/dev/null || echo "unknown")"
  echo "  Evaluating: $SCENARIO_NAME / $RUN_ID"

  for i in "${!EVAL_NAMES[@]}"; do
    eval_fn="eval_${EVAL_NAMES[$i]}"
    score="$($eval_fn "$run_dir")"
    TOTAL_SCORE=$((TOTAL_SCORE + score))
    TOTAL_MAX=$((TOTAL_MAX + 1))
    EVAL_PASS_COUNTS[$i]=$((EVAL_PASS_COUNTS[$i] + score))
    EVAL_TOTAL_COUNTS[$i]=$((EVAL_TOTAL_COUNTS[$i] + 1))
    echo "    ${EVAL_NAMES[$i]}: $([ "$score" -eq 1 ] && echo 'PASS' || echo 'FAIL')"
  done
done < <(find "$EXPERIMENT_DIR" -name 'metadata.json' -type f 2>/dev/null | sort)

# --- Build eval breakdown JSON ---
EVAL_BREAKDOWN="["
for i in "${!EVAL_NAMES[@]}"; do
  [[ $i -gt 0 ]] && EVAL_BREAKDOWN+=","
  EVAL_BREAKDOWN+="{\"name\":\"${EVAL_NAMES[$i]}\",\"pass_count\":${EVAL_PASS_COUNTS[$i]},\"total\":${EVAL_TOTAL_COUNTS[$i]}}"
done
EVAL_BREAKDOWN+="]"

# --- Calculate pass rate ---
if (( TOTAL_MAX > 0 )); then
  PASS_RATE="$(awk "BEGIN {printf \"%.1f\", ($TOTAL_SCORE / $TOTAL_MAX) * 100}")"
else
  PASS_RATE="0.0"
fi

# --- Write results ---
cat > "$RESULTS_FILE" <<RESULTS
{
  "experiment_id": $EXPERIMENT_ID,
  "score": $TOTAL_SCORE,
  "max_score": $TOTAL_MAX,
  "pass_rate": $PASS_RATE,
  "eval_breakdown": $EVAL_BREAKDOWN,
  "timestamp": "$(date -u +%FT%TZ)"
}
RESULTS

echo ""
echo "============================================"
echo "Experiment #${EXPERIMENT_ID} Results"
echo "Score: ${TOTAL_SCORE}/${TOTAL_MAX} (${PASS_RATE}%)"
echo ""
for i in "${!EVAL_NAMES[@]}"; do
  echo "  ${EVAL_NAMES[$i]}: ${EVAL_PASS_COUNTS[$i]}/${EVAL_TOTAL_COUNTS[$i]}"
done
echo "============================================"
echo "Results written to: $RESULTS_FILE"
