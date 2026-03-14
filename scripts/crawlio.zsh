#!/usr/bin/env zsh
# ╔═══════════════════════════════════════════════════════════════════════╗
# ║  crawlio — Crawlio Intelligence Runtime                              ║
# ║  Standalone pipeline orchestrator for Crawlio Loops and Sequences.   ║
# ║  Calls claude directly — no ralph dependency.                        ║
# ║  Source this file from ~/.zshrc                                      ║
# ╚═══════════════════════════════════════════════════════════════════════╝

# ─── Configuration ────────────────────────────────────────────────────
CRAWLIO_DIR="${HOME}/.crawlio"
CRAWLIO_SEQ_DIR=".ralph/sequences"  # Compatible with ralph-seq
CRAWLIO_STEP_TIMEOUT="${CRAWLIO_STEP_TIMEOUT:-1800}"
CRAWLIO_CB_MAX="${CRAWLIO_CB_MAX:-3}"
CRAWLIO_MAX_ITERATIONS="${CRAWLIO_MAX_ITERATIONS:-12}"
CRAWLIO_COMPLETION_KW="${CRAWLIO_COMPLETION_KW:-LOOP_COMPLETE}"

# ─── Load libraries ──────────────────────────────────────────────────
[[ -f "${CRAWLIO_DIR}/lib/seq-utils.sh" ]] && source "${CRAWLIO_DIR}/lib/seq-utils.sh"
[[ -f "${CRAWLIO_DIR}/lib/seq-mentu.sh" ]] && source "${CRAWLIO_DIR}/lib/seq-mentu.sh"

# ─── Banner ───────────────────────────────────────────────────────────
_crawlio_banner() {
  echo ""
  echo " ██████╗ ██████╗   █████╗  ██╗    ██╗ ██╗      ██╗  ██████╗"
  echo "██╔════╝ ██╔══██╗ ██╔══██╗ ██║    ██║ ██║      ██║ ██╔═══██╗"
  echo "██║      ██████╔╝ ███████║ ██║ █╗ ██║ ██║      ██║ ██║   ██║"
  echo "██║      ██╔══██╗ ██╔══██║ ██║███╗██║ ██║      ██║ ██║   ██║"
  echo "╚██████╗ ██║  ██║ ██║  ██║ ╚███╔███╔╝ ███████╗ ██║ ╚██████╔╝"
  echo " ╚═════╝ ╚═╝  ╚═╝ ╚═╝  ╚═╝  ╚══╝╚══╝  ╚══════╝ ╚═╝  ╚═════╝"
  echo ""
}

# ─── Token Resolution ─────────────────────────────────────────────────
_crawlio_get_token() {
  local profile="$1"
  local token_file="${HOME}/.claude/${profile}-token"
  [[ -f "$token_file" ]] && { cat "$token_file" | tr -d '\n'; return 0; }
  return 1
}

# ─── Memory Injection ─────────────────────────────────────────────────
_crawlio_inject_memories() {
  local workspace="$1" prompt_file="$2"
  local mem_file=""
  for c in "$workspace/.crawlio/agent/memories.md" "$workspace/.ralph/agent/memories.md"; do
    [[ -f "$c" ]] && { mem_file="$c"; break; }
  done
  if [[ -z "$mem_file" ]]; then echo "$prompt_file"; return; fi
  local mem_count=$(grep -c "^### mem-" "$mem_file" 2>/dev/null || echo 0)
  [[ $mem_count -eq 0 ]] && { echo "$prompt_file"; return; }
  echo "  Memories: $mem_count loaded ($(wc -c < "$mem_file" | tr -d ' ') chars)" >&2
  local tmp=$(mktemp /tmp/crawlio-prompt-XXXXXX.md)
  { echo "<!-- Crawlio: $mem_count memories injected -->"; echo ""; cat "$mem_file"; echo ""; echo "---"; echo ""; cat "$prompt_file"; } > "$tmp"
  echo "$tmp"
}

# ─── Task Injection ───────────────────────────────────────────────────
_crawlio_inject_tasks() {
  local workspace="$1" prompt_tmp="$2"
  local task_file=""
  for c in "$workspace/.crawlio/agent/tasks.jsonl" "$workspace/.ralph/agent/tasks.jsonl"; do
    [[ -f "$c" ]] && { task_file="$c"; break; }
  done
  [[ -z "$task_file" ]] && return
  local ready=$(grep -c '"status":"ready"' "$task_file" 2>/dev/null || echo 0)
  local open=$(grep -c '"status":"open"' "$task_file" 2>/dev/null || echo 0)
  local closed=$(grep -c '"status":"closed"' "$task_file" 2>/dev/null || echo 0)
  [[ $((ready + open)) -gt 0 ]] && echo "  Tasks: $ready ready, $open open, $closed closed" >&2
}

# ─── Backpressure ─────────────────────────────────────────────────────
_crawlio_backpressure() {
  local workspace="$1"
  local config=""
  for c in "$workspace/crawlio.yml" "$workspace/ralph.yml"; do
    [[ -f "$c" ]] && { config="$c"; break; }
  done
  [[ -z "$config" ]] && return 0
  # Check if yq is available
  command -v yq &>/dev/null || return 0
  local bp_count=$(yq '.backpressure | length // 0' "$config" 2>/dev/null || echo 0)
  [[ "$bp_count" == "0" || "$bp_count" == "null" ]] && return 0
  for ((i=0; i<bp_count; i++)); do
    local bp_name=$(yq -r ".backpressure[$i].name // \"gate-$i\"" "$config")
    local bp_cmd=$(yq -r ".backpressure[$i].command" "$config")
    local bp_fail=$(yq -r ".backpressure[$i].on_fail // \"reject\"" "$config")
    if [[ -n "$bp_cmd" && "$bp_cmd" != "null" ]]; then
      if ! (cd "$workspace" && eval "$bp_cmd" >/dev/null 2>&1); then
        echo "  Gate BLOCKED: $bp_name" >&2
        [[ "$bp_fail" == "reject" ]] && return 1
      fi
    fi
  done
  return 0
}

# ─── Protocol State ───────────────────────────────────────────────────
_crawlio_set_protocol_state() {
  local step_dir="$1" label="$2" seq_name="$3" step_json="$4"
  local proto_file="$step_dir/.claude/protocol-state.json"
  mkdir -p "$(dirname "$proto_file")" 2>/dev/null
  local protocols=$(echo "$step_json" | jq -c '.protocols // []')
  local auto_review=$(echo "$step_json" | jq -r '.auto_review // false')
  local recon=$(echo "$step_json" | jq -r '.recon_artifact // ""')
  jq -n --argjson p "$protocols" --arg l "$label" --arg s "$seq_name" \
    --argjson ar "$auto_review" --arg ra "$recon" \
    '{active_protocols:$p, step_label:$l, sequence_name:$s, auto_review:$ar, recon_artifact:$ra}' > "$proto_file"
}

# ─── Handoff Generation ──────────────────────────────────────────────
_crawlio_write_handoff() {
  local step_dir="$1" label="$2"
  local agent_dir="$step_dir/.crawlio/agent"
  mkdir -p "$agent_dir" 2>/dev/null
  {
    echo "# Session Handoff"
    echo ""
    echo "_Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)_"
    echo ""
    echo "## Git Context"
    echo ""
    echo "- **Branch:** $(cd "$step_dir" && git branch --show-current 2>/dev/null || echo 'unknown')"
    echo "- **HEAD:** $(cd "$step_dir" && git log --oneline -1 2>/dev/null || echo 'unknown')"
    echo ""
    echo "## Step: $label"
    echo ""
  } > "$agent_dir/handoff.md"
}

# ─── CONTEXT Document Generation ──────────────────────────────────────
_crawlio_generate_context() {
  local project_root="$1" seq_name="$2" seq_file="$3" status_dir="$4"
  local total=$(jq '.steps | length' "$seq_file")
  local context_file="$project_root/docs/CONTEXT-${seq_name}.md"
  [[ -f "$context_file" ]] && return  # Don't overwrite existing

  mkdir -p "$(dirname "$context_file")"
  {
    echo "# CONTEXT: ${seq_name}"
    echo ""
    echo "_Generated: $(date +%Y-%m-%d)_"
    echo ""
    echo "## Steps"
    echo ""
    echo "| # | Label | Status | Duration |"
    echo "|---|-------|--------|----------|"
    for ((si=0; si<total; si++)); do
      local si_label=$(jq -r ".steps[$si].label" "$seq_file")
      local si_sf="$status_dir/${si_label}.json"
      if [[ -f "$si_sf" ]]; then
        local si_ok=$(jq -r '.success' "$si_sf")
        local si_dur=$(jq -r '.duration' "$si_sf")
        printf "| %d | %s | %s | %ss |\n" "$((si+1))" "$si_label" \
          "$([[ "$si_ok" == "true" ]] && echo "OK" || echo "WARN")" "$si_dur"
      else
        printf "| %d | %s | pending | — |\n" "$((si+1))" "$si_label"
      fi
    done
    echo ""
    echo "## Step Results"
    echo ""
    for ((si=0; si<total; si++)); do
      local si_label=$(jq -r ".steps[$si].label" "$seq_file")
      local si_result=$(ls -t "${CRAWLIO_SEQ_DIR}/step-results/${si_label}-"*.md 2>/dev/null | head -1)
      if [[ -n "$si_result" ]]; then
        echo "### ${si_label}"
        echo ""
        head -30 "$si_result"
        echo ""
        echo "---"
        echo ""
      fi
    done
  } > "$context_file"
}

# ─── Step Result Capture ──────────────────────────────────────────────
_crawlio_capture_result() {
  local label="$1" step_dir="$2" result_dir="$3"
  mkdir -p "$result_dir" 2>/dev/null
  local ts=$(date +%Y%m%dT%H%M%S)
  # Check for step-result files the agent may have written
  local agent_result=""
  for c in "$step_dir/.crawlio/step-result.md" "$step_dir/.ralph/step-result.md"; do
    [[ -f "$c" ]] && { agent_result="$c"; break; }
  done
  if [[ -n "$agent_result" ]]; then
    cp "$agent_result" "$result_dir/${label}-${ts}.md"
    rm -f "$agent_result"
  fi
}

# ─── Single Claude Session ────────────────────────────────────────────
_crawlio_run_claude() {
  local auth="$1"; shift
  local token=$(_crawlio_get_token "$auth")
  if [[ -z "$token" ]]; then
    echo "  Error: no token for '$auth' (~/.claude/${auth}-token)" >&2
    return 1
  fi
  (
    unset ANTHROPIC_API_KEY
    export CLAUDE_CODE_OAUTH_TOKEN="$token"
    export MAX_THINKING_TOKENS=63999
    claude "$@" --dangerously-skip-permissions
  )
}

# ─── Main: crawlio ────────────────────────────────────────────────────
crawlio() {
  local seq_dir="${CRAWLIO_SEQ_DIR}"
  local log_dir="$seq_dir/logs"
  local status_dir="$seq_dir/step-status"
  local result_dir="$seq_dir/step-results"
  local current_file="$seq_dir/.crawlio-current"

  # Pre-parse --seq-dir from any position
  local custom_seq_dir=""
  local filtered_args=()
  local all_args=("$@")
  for ((i=1; i<=${#all_args[@]}; i++)); do
    if [[ "${all_args[$i]}" == "--seq-dir" ]]; then
      custom_seq_dir="${all_args[$((i+1))]}"
      ((i++))
    else
      filtered_args+=("${all_args[$i]}")
    fi
  done
  [[ -n "$custom_seq_dir" ]] && seq_dir="$custom_seq_dir"
  set -- "${filtered_args[@]}"

  case "$1" in
    list)
      _crawlio_banner
      echo "  Available pipelines ($seq_dir):"
      echo ""
      [[ ! -d "$seq_dir" ]] && { echo "  No sequences at $seq_dir" >&2; return 1; }
      for f in "$seq_dir"/*.json(N); do
        local name=$(basename "$f" .json)
        local steps=$(jq '.steps | length' "$f")
        local desc=$(jq -r '.description // ""' "$f")
        printf "  %-30s %d steps  %s\n" "$name" "$steps" "$desc"
      done
      return 0
      ;;
    status)
      _crawlio_banner
      [[ ! -f "$current_file" ]] && { echo "  No pipeline running."; return 0; }
      local cur_pid=$(jq -r '.pid' "$current_file" 2>/dev/null)
      if ! kill -0 "$cur_pid" 2>/dev/null; then
        echo "  Stale lock (PID $cur_pid dead). Cleaning."
        rm -f "$current_file"; return 0
      fi
      jq -r '"  Running: \(.pipeline)\n  Step:    \(.step) — \(.label)\n  PID:     \(.pid)\n  Started: \(.started)"' "$current_file"
      return 0
      ;;
    loop|seq)
      local layer="$1"; shift ;;
    "")
      _crawlio_banner
      echo "  Usage: crawlio [loop|seq] <name> [--from N] [--seq-dir /path]"
      echo ""
      echo "  crawlio loop clone-linear     Run a Crawlio Loop"
      echo "  crawlio seq  monitor-vercel   Run a Crawlio Sequence"
      echo "  crawlio clone-linear          Run a pipeline"
      echo "  crawlio list                  List pipelines"
      echo "  crawlio status                Check running"
      echo ""
      return 1
      ;;
    *)
      local layer="loop" ;;
  esac

  local pipeline_name
  if [[ "${layer:-}" == "loop" || "${layer:-}" == "seq" ]]; then
    pipeline_name="$1"; shift 2>/dev/null
  else
    pipeline_name="$1"; shift 2>/dev/null
  fi
  [[ -z "$pipeline_name" ]] && { echo "  Error: no pipeline name." >&2; return 1; }

  local start_from=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from) start_from="$2"; shift 2 ;;
      *) echo "  Unknown: $1" >&2; return 1 ;;
    esac
  done

  local seq_file="$seq_dir/${pipeline_name}.json"
  [[ ! -f "$seq_file" ]] && { echo "  Not found: $seq_file" >&2; echo "  Run 'crawlio list' to see available pipelines." >&2; return 1; }

  # Lock check
  if [[ -f "$current_file" ]]; then
    local cur_pid=$(jq -r '.pid' "$current_file" 2>/dev/null)
    if kill -0 "$cur_pid" 2>/dev/null; then
      echo "  Error: pipeline running (PID $cur_pid)." >&2; return 1
    fi
    rm -f "$current_file"
  fi

  mkdir -p "$log_dir" "$status_dir" "$result_dir"

  # Mentu integration
  local _mentu_ok=false
  if type crawlio_mentu_available &>/dev/null; then
    crawlio_mentu_available && _mentu_ok=true
  elif type mentu_available &>/dev/null; then
    mentu_available && _mentu_ok=true
  fi

  local total=$(jq '.steps | length' "$seq_file")
  local ts=$(date +%Y%m%d-%H%M%S)
  local logfile="$log_dir/${pipeline_name}-${ts}.log"
  local project_root=$(pwd)
  local layer_label="Crawlio ${layer:-Loop}"

  # Clean status on fresh run
  [[ $start_from -eq 1 ]] && rm -rf "$status_dir" 2>/dev/null && mkdir -p "$status_dir"

  # Mentu: capture + commit
  if [[ $start_from -eq 1 ]] && $_mentu_ok; then
    local def_mem=$(mentu_capture "Pipeline: ${pipeline_name} (${total} steps)" "sequence")
    if [[ -n "$def_mem" ]]; then
      local parent_cmt=$(mentu_commit "Execute ${pipeline_name}" "$def_mem" "pipeline,crawlio")
      [[ -n "$parent_cmt" ]] && mentu_claim "$parent_cmt" || true
    fi
    export CRAWLIO_PARENT_CMT="${parent_cmt:-}"
  fi

  _crawlio_banner
  echo "  $layer_label"
  echo "  Pipeline: $pipeline_name ($total steps)"
  [[ $start_from -gt 1 ]] && echo "  Resuming from step $start_from"
  echo ""

  {
    echo "=== CRAWLIO: $pipeline_name ==="
    echo "=== STARTED: $(date -u +%Y-%m-%dT%H:%M:%S) ==="
    [[ $start_from -gt 1 ]] && echo "=== RESUMING FROM STEP $start_from ==="
    echo ""
  } | tee "$logfile"

  local step_num=$((start_from - 1))
  local ok=0 warn=0 consecutive_fails=0

  while [[ $step_num -lt $total ]]; do
    local step_json=$(jq ".steps[$step_num]" "$seq_file")
    local label=$(echo "$step_json" | jq -r '.label')
    local dir=$(echo "$step_json" | jq -r '.dir // "."')
    local auth=$(echo "$step_json" | jq -r '.auth // "work"')
    local cb_enabled=$(echo "$step_json" | jq -r 'if has("circuit_breaker") then .circuit_breaker else true end')

    local step_dir
    [[ "$dir" == /* ]] && step_dir="$dir" || step_dir="$project_root/$dir"

    local -a step_args=()
    local args_len=$(echo "$step_json" | jq '.args | length // 0' 2>/dev/null)
    for ((i=0; i<args_len; i++)); do
      step_args+=($(echo "$step_json" | jq -r ".args[$i]"))
    done

    local display=$((step_num + 1))
    local step_start=$(date -u +%Y-%m-%dT%H:%M:%S)
    local step_epoch=$(date +%s)

    # Lock
    echo "{\"pipeline\":\"$pipeline_name\",\"pid\":$$,\"step\":$display,\"label\":\"$label\",\"started\":\"$step_start\"}" > "$current_file"

    {
      echo "--- step $display/$total: $label ---"
      echo "dir: $step_dir"
      echo "auth: $auth"
      [[ ${#step_args[@]} -gt 0 ]] && echo "args: ${step_args[*]}"
      echo "started: $step_start"
    } | tee -a "$logfile"

    # Protocol state injection
    _crawlio_set_protocol_state "$step_dir" "$label" "$pipeline_name" "$step_json"

    # Mentu: per-step commitment
    if $_mentu_ok; then
      local step_cmt=$(mentu_commit "Step: ${label}" "${CRAWLIO_PARENT_CMT:-}" "step,pipeline:${pipeline_name}")
      [[ -n "$step_cmt" ]] && mentu_claim "$step_cmt" || true
      export CRAWLIO_STEP_CMT="${step_cmt:-}"
    fi

    # Execute step
    local exit_code
    (
      cd "$step_dir" && _crawlio_run_claude "$auth" --no-tui "${step_args[@]}"
    ) &
    local step_pid=$!
    (sleep "$CRAWLIO_STEP_TIMEOUT" && kill "$step_pid" 2>/dev/null && sleep 2 && kill -9 "$step_pid" 2>/dev/null) &
    local timer_pid=$!

    wait "$step_pid" 2>/dev/null
    exit_code=$?
    kill "$timer_pid" 2>/dev/null 2>&1
    wait "$timer_pid" 2>/dev/null 2>&1

    # Cleanup
    rm -f "$step_dir/.claude/protocol-state.json" 2>/dev/null

    local duration=$(( $(date +%s) - step_epoch ))
    local status_text="OK"

    if [[ $exit_code -ne 0 ]]; then
      status_text="WARN (exit $exit_code)"
      warn=$((warn + 1))
      consecutive_fails=$((consecutive_fails + 1))
    else
      ok=$((ok + 1))
      consecutive_fails=0
    fi

    {
      echo "ended: $(date -u +%Y-%m-%dT%H:%M:%S)"
      echo "exit_code: $exit_code"
      echo "duration: ${duration}s"
      echo "status: $status_text"
      echo ""
    } | tee -a "$logfile"

    # Step status
    local loop_complete="false"
    local latest_result=$(ls -t "$result_dir/${label}-"*.md 2>/dev/null | head -1)
    [[ -n "$latest_result" ]] && grep -q "$CRAWLIO_COMPLETION_KW" "$latest_result" 2>/dev/null && loop_complete="true"

    echo "{\"label\":\"$label\",\"exit_code\":$exit_code,\"duration\":$duration,\"success\":$([ $exit_code -eq 0 ] && echo true || echo false),\"loop_complete\":$loop_complete,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$status_dir/${label}.json"

    # Capture step result
    _crawlio_capture_result "$label" "$step_dir" "$result_dir"

    # Write handoff
    _crawlio_write_handoff "$step_dir" "$label"

    # Mentu: close step
    if $_mentu_ok && [[ -n "${CRAWLIO_STEP_CMT:-}" ]]; then
      if [[ $exit_code -eq 0 ]]; then
        mentu_close "$CRAWLIO_STEP_CMT" || true
      else
        mentu_annotate "$CRAWLIO_STEP_CMT" "Step failed: ${label} (exit ${exit_code})" || true
      fi
    fi

    # Circuit breaker
    if [[ "$cb_enabled" != "false" && $consecutive_fails -ge $CRAWLIO_CB_MAX ]]; then
      echo "CIRCUIT BREAKER: $consecutive_fails consecutive failures" | tee -a "$logfile"
      osascript -e "display notification \"Circuit breaker: $consecutive_fails failures\" with title \"Crawlio HALTED\" subtitle \"$pipeline_name\" sound name \"Sosumi\"" 2>/dev/null
      rm -f "$current_file"
      return 1
    fi

    step_num=$((step_num + 1))
  done

  local ran=$((ok + warn))

  # Generate CONTEXT doc
  _crawlio_generate_context "$project_root" "$pipeline_name" "$seq_file" "$status_dir"

  # Mentu: close pipeline
  if $_mentu_ok && [[ -n "${CRAWLIO_PARENT_CMT:-}" ]]; then
    local summary=$(mentu_capture "Pipeline completed: ${pipeline_name} (${ok}/${ran} ok)" "pipeline_result")
    [[ -n "$summary" ]] && mentu_close "$CRAWLIO_PARENT_CMT" "$summary" || true
  fi

  {
    echo "=== FINISHED: $(date -u +%Y-%m-%dT%H:%M:%S) ==="
    echo "=== RESULT: $ran steps ($ok ok, $warn warned) ==="
  } | tee -a "$logfile"

  rm -f "$current_file"

  echo ""
  _crawlio_banner
  echo "  Pipeline complete: $ran steps ($ok ok, $warn warned)"
  echo ""

  if [[ $warn -gt 0 ]]; then
    osascript -e "display notification \"$ran steps ($warn warnings)\" with title \"Crawlio\" subtitle \"$pipeline_name\" sound name \"Purr\"" 2>/dev/null
  else
    osascript -e "display notification \"All $ran steps passed\" with title \"Crawlio\" subtitle \"$pipeline_name\" sound name \"Glass\"" 2>/dev/null
  fi

  return 0
}
