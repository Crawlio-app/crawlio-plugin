#!/bin/bash
# seq-utils.sh — Shared utility functions for ralph-seq and hooks
# Source this file: source ~/.ralph/lib/seq-utils.sh

# Write structured step status JSON after a step completes.
# Usage: seq_write_step_status <label> <exit_code> <duration> [loop_complete]
seq_write_step_status() {
  local label="$1"
  local exit_code="$2"
  local duration="$3"
  local loop_complete="${4:-false}"
  local status_dir=".ralph/sequences/step-status"
  mkdir -p "$status_dir" 2>/dev/null

  local success="false"
  if [[ "$exit_code" == "0" ]] || [[ "$loop_complete" == "true" ]]; then
    success="true"
  fi

  cat > "$status_dir/${label}.json" <<JSON
{"label":"$label","exit_code":$exit_code,"duration":$duration,"success":$success,"loop_complete":$loop_complete,"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
JSON
}

# Extract build command from CLAUDE.md (looks for ```bash block under ## Commands).
# Returns the command string, or "echo build ok" as fallback.
seq_read_build_cmd() {
  local claude_md="${1:-CLAUDE.md}"
  if [[ ! -f "$claude_md" ]]; then
    echo "echo build ok"
    return
  fi
  # Extract first command from ```bash block under ## Commands
  local cmd
  cmd=$(awk '/^## Commands/{found=1} found && /^```bash/{getline; print; exit}' "$claude_md")
  if [[ -n "$cmd" ]]; then
    echo "$cmd"
  else
    echo "echo build ok"
  fi
}

# Resolve protocols array from a step JSON object (passed via stdin or as arg).
# Usage: echo "$step_json" | seq_resolve_protocols
#    or: seq_resolve_protocols "$step_json"
seq_resolve_protocols() {
  local step_json="${1:-$(cat)}"
  echo "$step_json" | jq -r '.protocols // [] | .[]' 2>/dev/null
}
