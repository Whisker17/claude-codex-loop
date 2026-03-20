#!/usr/bin/env bash

set -euo pipefail

review_loop::script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

review_loop::plugin_root() {
  cd "$(review_loop::script_dir)/.." && pwd
}

review_loop::project_root() {
  local dir

  if [[ -n "${REVIEW_LOOP_PROJECT_ROOT:-}" ]]; then
    cd "$REVIEW_LOOP_PROJECT_ROOT" && pwd -P
    return
  fi

  dir="$(pwd -P)"
  while true; do
    if [[ -f "$dir/.claude/review-loop.local.md" ]]; then
      printf '%s\n' "$dir"
      return
    fi
    if [[ "$dir" == "/" ]]; then
      break
    fi
    dir="$(dirname "$dir")"
  done

  printf '%s\n' "$(pwd -P)"
}

review_loop::state_file() {
  printf '%s/.claude/review-loop.local.md\n' "$(review_loop::project_root)"
}

review_loop::ensure_runtime_dir() {
  mkdir -p "$(review_loop::project_root)/.claude"
}

review_loop::log_file() {
  printf '%s/.claude/review-loop.log\n' "$(review_loop::project_root)"
}

review_loop::session_pid_file() {
  local session_id="$1"
  printf '%s/.claude/review-loop-%s.pid\n' "$(review_loop::project_root)" "$session_id"
}

review_loop::session_sentinel_file() {
  local session_id="$1"
  printf '%s/.claude/review-loop-%s.sentinel\n' "$(review_loop::project_root)" "$session_id"
}

review_loop::session_output_log() {
  local session_id="$1"
  printf '%s/.claude/review-loop-%s-codex-output.log\n' "$(review_loop::project_root)" "$session_id"
}

review_loop::session_prompt_file() {
  local session_id="$1"
  printf '%s/.claude/review-loop-%s-prompt.md\n' "$(review_loop::project_root)" "$session_id"
}

review_loop::trim_value() {
  local value="$1"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  printf '%s\n' "$value"
}

review_loop::read_state_field() {
  local key="$1"
  local state_file
  local value=""
  local found=0
  state_file="$(review_loop::state_file)"

  if [[ ! -f "$state_file" ]]; then
    return 1
  fi

  while IFS= read -r value || [[ -n "$value" ]]; do
    found=1
    break
  done < <(
    awk -v key="$key" '
      $0 ~ ("^" key ":[[:space:]]*") {
        sub(/^[^:]+:[[:space:]]*/, "", $0)
        print
        exit
      }
    ' "$state_file"
  )

  ((found)) || return 1
  review_loop::trim_value "$value"
}

review_loop::require_state_field() {
  local key="$1"
  local value

  value="$(review_loop::read_state_field "$key")" || {
    printf 'Missing [%s] in %s\n' "$key" "$(review_loop::state_file)" >&2
    exit 1
  }

  printf '%s\n' "$value"
}

review_loop::log() {
  review_loop::ensure_runtime_dir
  printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >> "$(review_loop::log_file)"
}

review_loop::validate_mode() {
  local mode="$1"
  case "$mode" in
    design-review|code-implement|code-fix)
      ;;
    *)
      printf 'Unsupported mode: %s\n' "$mode" >&2
      exit 1
      ;;
  esac
}

review_loop::validate_round() {
  local round="$1"
  if review_loop::is_integer "$round"; then
    if (( round >= 1 && round <= 5 )); then
      return 0
    fi
  fi

  if [[ "$round" == "verify" ]]; then
    return 0
  fi

  printf 'Unsupported round: %s\n' "$round" >&2
  exit 1
}

review_loop::template_path() {
  local mode="$1"
  printf '%s/prompts/%s.md\n' "$(review_loop::plugin_root)" "$mode"
}

review_loop::read_template() {
  local mode="$1"
  local round="$2"
  local template

  template="$(<"$(review_loop::template_path "$mode")")"
  template="${template//'{{ROUND}}'/$round}"
  printf '%s\n' "$template"
}

review_loop::is_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

review_loop::expected_output_path() {
  local mode="$1"
  local round="$2"

  case "$mode" in
    design-review)
      printf 'specs/reviews/design/round-%s-codex-review.md\n' "$round"
      ;;
    code-fix)
      printf 'specs/reviews/code/round-%s-codex-response.md\n' "$round"
      ;;
    code-implement)
      return 1
      ;;
  esac
}

review_loop::append_file_section() {
  local title="$1"
  local path="$2"
  local relative_path="$path"
  local project_root
  local absolute_dir
  local absolute_path

  [[ -f "$path" ]] || return 0

  project_root="$(review_loop::project_root)"
  absolute_dir="$(cd "$(dirname "$path")" && pwd -P)"
  absolute_path="$absolute_dir/$(basename "$path")"
  if [[ "$absolute_path" == "$project_root/"* ]]; then
    relative_path="${absolute_path#"$project_root/"}"
  fi

  printf '\n## %s\n' "$title"
  printf 'Path: %s\n' "$relative_path"
  printf '```md\n'
  cat "$path"
  printf '\n```\n'
}

review_loop::latest_completed_round() {
  local stage="$1"
  local suffix="$2"
  local file
  local best=""
  local best_num=0

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    file="${file##*/}"
    file="${file#round-}"
    file="${file%-$suffix.md}"
    if review_loop::is_integer "$file" && (( file > best_num )); then
      best="$file"
      best_num="$file"
    fi
  done < <(find "$(review_loop::project_root)/specs/reviews/$stage" -maxdepth 1 -type f -name "round-*-$suffix.md" -print 2>/dev/null)

  [[ -n "$best" ]] || return 1
  printf '%s\n' "$best"
}

review_loop::previous_round_for_pair() {
  local round="$1"
  local stage="$2"
  local suffix="$3"

  if review_loop::is_integer "$round"; then
    if (( round > 1 )); then
      printf '%s\n' "$((round - 1))"
      return 0
    fi
    return 1
  fi

  if [[ "$round" == "verify" ]]; then
    review_loop::latest_completed_round "$stage" "$suffix"
    return $?
  fi

  return 1
}

review_loop::build_prompt() {
  local mode="$1"
  local round="$2"
  local project_root
  local session_id
  local phase
  local task
  local output_path=""
  local previous_round=""

  project_root="$(review_loop::project_root)"
  session_id="$(review_loop::require_state_field "session_id")"
  phase="$(review_loop::require_state_field "phase")"
  task="$(review_loop::read_state_field "task" || true)"

  printf '%s\n' "$(review_loop::read_template "$mode" "$round")"
  printf '\n## Runtime Metadata\n'
  printf -- '- Session ID: %s\n' "$session_id"
  printf -- '- Phase: %s\n' "$phase"
  printf -- '- Mode: %s\n' "$mode"
  printf -- '- Round: %s\n' "$round"
  if [[ -n "$task" ]]; then
    printf -- '- Task: %s\n' "$task"
  fi

  review_loop::append_file_section "Design Document" "$project_root/specs/design.md"

  case "$mode" in
    design-review)
      previous_round="$(review_loop::previous_round_for_pair "$round" "design" "codex-review" || true)"
      if [[ -n "$previous_round" ]]; then
        review_loop::append_file_section "Previous Codex Review" "$project_root/specs/reviews/design/round-$previous_round-codex-review.md"
        review_loop::append_file_section "Previous Claude Response" "$project_root/specs/reviews/design/round-$previous_round-claude-response.md"
      fi
      ;;
    code-implement)
      ;;
    code-fix)
      review_loop::append_file_section "Current Claude Review" "$project_root/specs/reviews/code/round-$round-claude-review.md"
      previous_round="$(review_loop::previous_round_for_pair "$round" "code" "codex-response" || true)"
      if [[ -n "$previous_round" ]]; then
        review_loop::append_file_section "Previous Codex Response" "$project_root/specs/reviews/code/round-$previous_round-codex-response.md"
      fi
      ;;
  esac

  if output_path="$(review_loop::expected_output_path "$mode" "$round" 2>/dev/null)"; then
    printf '\n## Required Output Path\n'
    printf '%s\n' "$output_path"
  fi
}

review_loop::shell_quote() {
  printf '%q' "$1"
}
