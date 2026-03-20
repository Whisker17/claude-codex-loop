#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=plugins/review-loop/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

SESSION_ID="${1:-}"
MODE="${2:-}"
ROUND="${3:-}"

if [[ -z "$SESSION_ID" || -z "$MODE" || -z "$ROUND" ]]; then
  printf 'Usage: %s <session-id> <design-review|code-implement|code-fix> <round|verify>\n' "$0" >&2
  exit 1
fi

review_loop::validate_mode "$MODE"
review_loop::validate_round "$ROUND"

PID_FILE="$(review_loop::session_pid_file "$SESSION_ID")"
SENTINEL_FILE="$(review_loop::session_sentinel_file "$SESSION_ID")"
PID=""

if [[ -f "$PID_FILE" ]]; then
  PID="$(<"$PID_FILE")"
fi

if [[ -f "$SENTINEL_FILE" ]]; then
  SENTINEL_VALUE="$(<"$SENTINEL_FILE")"
  case "$SENTINEL_VALUE" in
    done)
      if EXPECTED_OUTPUT="$(review_loop::expected_output_path "$MODE" "$ROUND" 2>/dev/null)"; then
        if [[ ! -f "$(review_loop::project_root)/$EXPECTED_OUTPUT" ]]; then
          printf 'FAILED\n'
          exit 3
        fi
      fi
      printf 'DONE\n'
      exit 0
      ;;
    timeout)
      printf 'TIMEOUT\n'
      exit 1
      ;;
    failed)
      printf 'FAILED\n'
      exit 3
      ;;
    *)
      printf 'FAILED\n'
      exit 3
      ;;
  esac
fi

if [[ -n "$PID" ]] && kill -0 "$PID" >/dev/null 2>&1; then
  printf 'RUNNING\n'
  exit 2
fi

printf 'FAILED\n'
exit 3
