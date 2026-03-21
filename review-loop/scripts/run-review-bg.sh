#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=review-loop/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

MODE="${1:-}"
ROUND="${2:-}"

if [[ -z "$MODE" || -z "$ROUND" ]]; then
  printf 'Usage: %s <design-review|code-implement|code-fix> <round|verify>\n' "$0" >&2
  exit 1
fi

review_loop::validate_mode "$MODE"
review_loop::validate_round "$ROUND"
command -v codex >/dev/null 2>&1 || {
  printf 'codex CLI is required on PATH\n' >&2
  exit 1
}

PROJECT_ROOT="$(review_loop::project_root)"
STATE_FILE="$(review_loop::state_file)"
SESSION_ID="$(review_loop::require_state_field "session_id")"
PID_FILE="$(review_loop::session_pid_file "$SESSION_ID")"
SENTINEL_FILE="$(review_loop::session_sentinel_file "$SESSION_ID")"
OUTPUT_LOG="$(review_loop::session_output_log "$SESSION_ID")"
PROMPT_FILE="$(review_loop::session_prompt_file "$SESSION_ID")"
PROMPT="$(review_loop::build_prompt "$MODE" "$ROUND")"
TIMEOUT_SECONDS="${REVIEW_LOOP_TIMEOUT_SECONDS:-1200}"

[[ -f "$STATE_FILE" ]] || {
  printf 'Missing state file: %s\n' "$STATE_FILE" >&2
  exit 1
}

review_loop::ensure_runtime_dir
rm -f "$PID_FILE" "$SENTINEL_FILE"
touch "$OUTPUT_LOG"
printf '%s' "$PROMPT" > "$PROMPT_FILE"

if EXPECTED_OUTPUT="$(review_loop::expected_output_path "$MODE" "$ROUND" 2>/dev/null)"; then
  mkdir -p "$PROJECT_ROOT/$(dirname "$EXPECTED_OUTPUT")"
fi

WRAPPER_SCRIPT=$(cat <<'EOF'
set -euo pipefail

project_root="$REVIEW_LOOP_PROJECT_ROOT"
pid_file="$REVIEW_LOOP_PID_FILE"
sentinel_file="$REVIEW_LOOP_SENTINEL_FILE"
prompt_file="$REVIEW_LOOP_PROMPT_FILE"
timeout_seconds="$REVIEW_LOOP_TIMEOUT_SECONDS"

finalize() {
  local status=$?
  if [[ ! -f "$sentinel_file" ]]; then
    if [[ $status -eq 0 ]]; then
      printf 'done' > "$sentinel_file"
    else
      printf 'failed' > "$sentinel_file"
    fi
  fi
  exit "$status"
}

trap finalize EXIT

printf '%s' "$$" > "$pid_file"
prompt="$(<"$prompt_file")"

codex exec -C "$project_root" --full-auto "$prompt" &
codex_pid=$!

deadline=$((SECONDS + timeout_seconds))
while kill -0 "$codex_pid" 2>/dev/null; do
  if ((SECONDS >= deadline)); then
    printf 'timeout' > "$sentinel_file"
    trap - EXIT
    kill -- "-$$" 2>/dev/null || kill "$codex_pid" 2>/dev/null || true
    exit 124
  fi
  sleep 1
done

wait "$codex_pid"
EOF
)

if command -v setsid >/dev/null 2>&1; then
  env \
    REVIEW_LOOP_PROJECT_ROOT="$PROJECT_ROOT" \
    REVIEW_LOOP_PID_FILE="$PID_FILE" \
    REVIEW_LOOP_SENTINEL_FILE="$SENTINEL_FILE" \
    REVIEW_LOOP_PROMPT_FILE="$PROMPT_FILE" \
    REVIEW_LOOP_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
    setsid bash -s <<< "$WRAPPER_SCRIPT" >> "$OUTPUT_LOG" 2>&1 &
else
  env \
    REVIEW_LOOP_PROJECT_ROOT="$PROJECT_ROOT" \
    REVIEW_LOOP_PID_FILE="$PID_FILE" \
    REVIEW_LOOP_SENTINEL_FILE="$SENTINEL_FILE" \
    REVIEW_LOOP_PROMPT_FILE="$PROMPT_FILE" \
    REVIEW_LOOP_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
    perl -e 'setpgrp(0,0) or die $!; exec @ARGV' bash -s <<< "$WRAPPER_SCRIPT" >> "$OUTPUT_LOG" 2>&1 &
fi

for _ in $(seq 1 50); do
  if [[ -f "$PID_FILE" ]]; then
    break
  fi
  sleep 0.1
done

PGID=""
if [[ -f "$PID_FILE" ]]; then
  PGID="$(<"$PID_FILE")"
else
  printf 'Failed to launch review-loop background wrapper: PID file was not created\n' >&2
  review_loop::log "launch_failed mode=$MODE round=$ROUND session_id=$SESSION_ID reason=missing_pid_file"
  exit 1
fi

review_loop::log "launched mode=$MODE round=$ROUND session_id=$SESSION_ID pid=${PGID:-unknown} timeout_seconds=$TIMEOUT_SECONDS"
