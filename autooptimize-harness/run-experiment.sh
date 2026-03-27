#!/usr/bin/env bash
#
# run-experiment.sh — orchestrates a single autooptimize experiment
#
# Usage: run-experiment.sh [--experiment-id N] [--scenario <name|all>] [--plugin-dir <path>]
#
# Runs the review-loop plugin in isolated temp directories for each scenario,
# collects outputs, and runs evals. Uses the host's authenticated CLIs.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_DIR="${PROJECT_ROOT}/review-loop"
EXPERIMENT_ID="0"
SCENARIO="all"
OUTPUT_BASE="${PROJECT_ROOT}/autooptimize-review-loop/runs"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --experiment-id) EXPERIMENT_ID="$2"; shift 2 ;;
    --scenario)      SCENARIO="$2"; shift 2 ;;
    --plugin-dir)    PLUGIN_DIR="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# --- Verify prerequisites ---
command -v claude >/dev/null 2>&1 || { echo "Error: claude CLI not found" >&2; exit 1; }
command -v codex >/dev/null 2>&1  || { echo "Error: codex CLI not found" >&2; exit 1; }

# --- Determine scenarios ---
SCENARIO_DIR="${SCRIPT_DIR}/scenarios"
SCENARIO_FILES=()

if [[ "$SCENARIO" == "all" ]]; then
  while IFS= read -r f; do
    SCENARIO_FILES+=("$f")
  done < <(find "$SCENARIO_DIR" -name '*.txt' -type f | sort)
else
  SCENARIO_FILES=("${SCENARIO_DIR}/${SCENARIO}.txt")
fi

if [[ ${#SCENARIO_FILES[@]} -eq 0 ]]; then
  echo "No scenario files found" >&2
  exit 1
fi

# --- Run each scenario ---
EXPERIMENT_OUTPUT="${OUTPUT_BASE}/experiment-${EXPERIMENT_ID}"
mkdir -p "$EXPERIMENT_OUTPUT"

echo "============================================"
echo "Experiment #${EXPERIMENT_ID}"
echo "Scenarios:  ${#SCENARIO_FILES[@]}"
echo "Plugin dir: ${PLUGIN_DIR}"
echo "Output:     ${EXPERIMENT_OUTPUT}"
echo "============================================"

FAILED=0
for SCENARIO_FILE in "${SCENARIO_FILES[@]}"; do
  SCENARIO_NAME="$(basename "$SCENARIO_FILE" .txt)"
  RUN_ID="exp${EXPERIMENT_ID}-${SCENARIO_NAME}-$(date +%H%M%S)"

  echo ""
  echo "--- Running scenario: $SCENARIO_NAME (run: $RUN_ID) ---"

  set +e
  "${SCRIPT_DIR}/test-harness.sh" "$SCENARIO_FILE" \
    --plugin-dir "$PLUGIN_DIR" \
    --output-dir "$EXPERIMENT_OUTPUT" \
    --run-id "$RUN_ID"
  HARNESS_EXIT=$?
  set -e

  if [[ $HARNESS_EXIT -ne 0 ]]; then
    echo "WARNING: harness exited with code $HARNESS_EXIT for $SCENARIO_NAME"
    FAILED=$((FAILED + 1))
  fi

  echo "--- Scenario $SCENARIO_NAME complete ---"
done

echo ""
echo "============================================"
echo "All scenarios complete. (${FAILED} harness failures)"
echo "Outputs: ${EXPERIMENT_OUTPUT}/"
echo "============================================"

# --- Run evals ---
if [[ -x "${SCRIPT_DIR}/eval.sh" ]]; then
  echo ""
  echo "Running evals..."
  "${SCRIPT_DIR}/eval.sh" "$EXPERIMENT_OUTPUT" "$EXPERIMENT_ID"
fi
