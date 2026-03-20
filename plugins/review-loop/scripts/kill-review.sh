#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=plugins/review-loop/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

SESSION_ID="${1:-}"

if [[ -z "$SESSION_ID" ]]; then
  printf 'Usage: %s <session-id|--from-hook>\n' "$0" >&2
  exit 1
fi

if [[ "$SESSION_ID" == "--from-hook" ]]; then
  SESSION_ID="$(review_loop::read_state_field "session_id" || true)"
  if [[ -z "$SESSION_ID" ]]; then
    exit 0
  fi
fi

PID_FILE="$(review_loop::session_pid_file "$SESSION_ID")"
SENTINEL_FILE="$(review_loop::session_sentinel_file "$SESSION_ID")"
OUTPUT_LOG="$(review_loop::session_output_log "$SESSION_ID")"
PROMPT_FILE="$(review_loop::session_prompt_file "$SESSION_ID")"
STATE_FILE="$(review_loop::state_file)"
PID=""

if [[ -f "$PID_FILE" ]]; then
  PID="$(<"$PID_FILE")"
fi

if [[ -n "$PID" ]]; then
  kill -- "-$PID" >/dev/null 2>&1 || true
  kill "$PID" >/dev/null 2>&1 || true
fi

rm -f "$PID_FILE" "$SENTINEL_FILE" "$OUTPUT_LOG" "$PROMPT_FILE" "$STATE_FILE"
review_loop::log "killed session_id=$SESSION_ID"
