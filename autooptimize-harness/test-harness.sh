#!/usr/bin/env bash
#
# test-harness.sh — runs a single review-loop session in an isolated temp dir
#
# Usage: test-harness.sh <scenario-file> [--plugin-dir <path>] [--output-dir <path>] [--run-id <id>]
#
# Uses the host's authenticated claude and codex CLIs (subscription auth).
# Creates a temp git repo, runs the review-loop via --system-prompt-file,
# collects outputs, cleans up.
#
set -euo pipefail

SCENARIO_FILE=""
PLUGIN_DIR=""
OUTPUT_DIR=""
RUN_ID=""

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin-dir)  PLUGIN_DIR="$2"; shift 2 ;;
    --output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
    --run-id)      RUN_ID="$2"; shift 2 ;;
    -*)            echo "Unknown flag: $1" >&2; exit 1 ;;
    *)             SCENARIO_FILE="$1"; shift ;;
  esac
done

if [[ -z "$SCENARIO_FILE" ]]; then
  echo "Usage: test-harness.sh <scenario-file> [--plugin-dir <path>] [--output-dir <path>]" >&2
  exit 1
fi

if [[ ! -f "$SCENARIO_FILE" ]]; then
  echo "Scenario file not found: $SCENARIO_FILE" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_DIR="${PLUGIN_DIR:-${PROJECT_ROOT}/review-loop}"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/autooptimize-review-loop/runs}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)-$$}"
TASK="$(<"$SCENARIO_FILE")"
SCENARIO_NAME="$(basename "$SCENARIO_FILE" .txt)"

# The review-loop command file (used as system prompt)
COMMAND_FILE="${PLUGIN_DIR}/commands/review-loop.md"
if [[ ! -f "$COMMAND_FILE" ]]; then
  echo "Error: review-loop command not found at $COMMAND_FILE" >&2
  exit 1
fi

# --- Verify prerequisites ---
command -v claude >/dev/null 2>&1 || { echo "Error: claude CLI not found" >&2; exit 1; }
command -v codex >/dev/null 2>&1 || { echo "Error: codex CLI not found" >&2; exit 1; }
command -v git >/dev/null 2>&1   || { echo "Error: git not found" >&2; exit 1; }

RUN_OUTPUT_DIR="${OUTPUT_DIR}/${SCENARIO_NAME}/${RUN_ID}"
mkdir -p "$RUN_OUTPUT_DIR"

echo "=== autooptimize test harness ==="
echo "Run ID:    $RUN_ID"
echo "Scenario:  $SCENARIO_NAME"
echo "Task:      $TASK"
echo "Plugin:    $PLUGIN_DIR"
echo "Output:    $RUN_OUTPUT_DIR"
echo "================================="

# --- 1. Create an isolated temp project ---
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/autooptimize-XXXXXX")"
trap 'echo "[$(date -u +%FT%TZ)] Cleaning up $TEMP_DIR"; rm -rf "$TEMP_DIR"' EXIT

PROJECT_DIR="${TEMP_DIR}/project"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

git init -q
git config user.name "autooptimize-test"
git config user.email "autooptimize@test.local"
echo "# Test Project" > README.md
git add README.md
git commit -q -m "initial commit"

echo "[$(date -u +%FT%TZ)] Created test project at $PROJECT_DIR"

# --- 2. Run review-loop ---
# Use --system-prompt-file to inject the review-loop command (--plugin-dir
# does not reliably load slash commands in -p mode).
# Use --append-system-prompt to auto-approve all interactive gates.
echo "[$(date -u +%FT%TZ)] Starting review-loop..."

set +e
claude -p "Task: ${TASK}" \
  --system-prompt-file "$COMMAND_FILE" \
  --append-system-prompt "CRITICAL AUTOMATION RULES: This is a fully automated test run. 1) Skip brainstorming — proceed directly to design stage. 2) When design stage completes, immediately confirm and proceed to code stage without waiting for user. 3) Complete the full pipeline end-to-end without stopping at any gate. 4) Treat every confirmation prompt as approved." \
  --dangerously-skip-permissions \
  2>&1 | tee "$RUN_OUTPUT_DIR/claude-output.log"
EXIT_CODE=${PIPESTATUS[0]}
set -e

echo "[$(date -u +%FT%TZ)] claude exited with code $EXIT_CODE"

# --- 3. Collect outputs ---
if [[ -f specs/design.md ]]; then
  cp specs/design.md "$RUN_OUTPUT_DIR/design.md"
fi

if [[ -d specs/reviews ]]; then
  cp -r specs/reviews "$RUN_OUTPUT_DIR/reviews"
fi

if [[ -f .claude/review-loop.log ]]; then
  cp .claude/review-loop.log "$RUN_OUTPUT_DIR/review-loop.log"
fi

# Branch and diff info
BRANCH="$(git branch --show-current 2>/dev/null || echo "unknown")"
echo "$BRANCH" > "$RUN_OUTPUT_DIR/branch.txt"

BASELINE_SHA="$(git log --format=%H --reverse | head -1)"
git diff "$BASELINE_SHA" -- ':!specs/' ':!.claude/' > "$RUN_OUTPUT_DIR/code-diff.patch" 2>/dev/null || true

git ls-files --others --exclude-standard > "$RUN_OUTPUT_DIR/new-files.txt" 2>/dev/null || true
git diff --name-only "$BASELINE_SHA" -- ':!specs/' ':!.claude/' > "$RUN_OUTPUT_DIR/changed-files.txt" 2>/dev/null || true

# Copy all source files produced by Codex
if [[ -s "$RUN_OUTPUT_DIR/changed-files.txt" ]] || [[ -s "$RUN_OUTPUT_DIR/new-files.txt" ]]; then
  mkdir -p "$RUN_OUTPUT_DIR/source"
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    mkdir -p "$RUN_OUTPUT_DIR/source/$(dirname "$f")"
    cp "$f" "$RUN_OUTPUT_DIR/source/$f"
  done < <(cat "$RUN_OUTPUT_DIR/changed-files.txt" "$RUN_OUTPUT_DIR/new-files.txt" 2>/dev/null | sort -u)
fi

# Write run metadata
cat > "$RUN_OUTPUT_DIR/metadata.json" <<META
{
  "run_id": "$RUN_ID",
  "scenario": "$SCENARIO_NAME",
  "task": $(printf '%s' "$TASK" | jq -Rs .),
  "exit_code": $EXIT_CODE,
  "branch": "$BRANCH",
  "baseline_sha": "$BASELINE_SHA",
  "project_dir": "$PROJECT_DIR",
  "timestamp": "$(date -u +%FT%TZ)"
}
META

echo "[$(date -u +%FT%TZ)] Outputs collected to $RUN_OUTPUT_DIR"
echo "=== harness complete ==="
