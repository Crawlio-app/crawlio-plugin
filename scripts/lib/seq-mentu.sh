#!/usr/bin/env bash
# seq-mentu.sh — Shell helpers for mentu-local-daemon interaction
# Used by ralph-seq.zsh for commitment lifecycle instrumentation.
# All functions are fail-safe (return empty string on failure).
#
# NOTE: This file is sourced from zsh. All JSON must be constructed via
# jq (not string interpolation) and passed to Python via stdin to avoid
# zsh double-quote escaping issues.

MENTU_SOCKET="${HOME}/.mentu/mentu-local.sock"
MENTU_CLIENT_PY=""  # Set dynamically

# Direct Unix socket RPC call via socat (no Python dependency)
# Usage: mentu_rpc <method> [json_params]
# Returns: typed exit codes for ControlError categories
#   0 = success, 1 = invalid state, 2 = not found, 3 = conflict,
#   4 = circuit breaker open, 6 = timeout
mentu_rpc() {
    local method="$1"
    local params
    if [[ -n "$2" ]]; then params="$2"; else params="{}"; fi
    local request
    request=$(jq -cn --arg m "$method" --argjson p "$params" \
        '{"jsonrpc":"2.0","method":$m,"params":$p,"id":1}' 2>/dev/null) || return 1
    local response
    response=$(printf '%s\n' "$request" | socat -t2 - UNIX-CONNECT:"${MENTU_SOCKET}" 2>/dev/null)

    local error_code
    error_code=$(echo "$response" | jq -r '.error.code // empty' 2>/dev/null)

    if [[ -n "$error_code" ]]; then
        case "$error_code" in
            -32001) echo "ERROR: Invalid state transition" >&2; return 1 ;;
            -32002) echo "ERROR: Resource not found" >&2; return 2 ;;
            -32003) echo "ERROR: Resource conflict" >&2; return 3 ;;
            -32004) echo "ERROR: Circuit breaker open — sync suspended" >&2; return 4 ;;
            -32006) echo "ERROR: Operation timeout" >&2; return 6 ;;
            *) echo "ERROR: RPC error $error_code" >&2; return 1 ;;
        esac
    fi

    echo "$response" | jq -r '.result // empty' 2>/dev/null
}

# Handle circuit breaker trip events — log and pause (auto-recovers in half-open)
mentu_handle_circuit_trip() {
    echo "⚠ Circuit breaker tripped: sync suspended" >&2
    echo "  Waiting for cooldown (60s)..." >&2
}

# Find the Python client
_mentu_find_client() {
    local candidates=(
        "${PROJECT_ROOT:-.}/.claude/hooks/mentu_local_client.py"
        "$HOME/Desktop/Subtrace/.claude/hooks/mentu_local_client.py"
    )
    for c in "${candidates[@]}"; do
        if [[ -f "$c" ]]; then
            MENTU_CLIENT_PY="$(dirname "$c")"
            return 0
        fi
    done
    return 1
}

# Check if daemon is available
mentu_available() {
    [[ -S "$MENTU_SOCKET" ]] && _mentu_find_client
}

# Generic RPC call via Python client
# Usage: _mentu_rpc <method> <json_params>
# Returns: JSON result on stdout, empty on failure
# Params are passed via stdin to avoid zsh escaping issues.
_mentu_rpc() {
    local method="$1"
    local params="$2"
    [[ -z "$params" ]] && params="{}"
    printf '%s' "$params" | python3 -c "
import sys, json
sys.path.insert(0, '${MENTU_CLIENT_PY}')
from mentu_local_client import MentuLocalClient
params = json.loads(sys.stdin.read())
result = MentuLocalClient.call('${method}', params)
if result:
    print(json.dumps(result))
" 2>/dev/null
}

# Capture a memory. Prints mem_id.
mentu_capture() {
    local content="$1"
    local kind="${2:-note}"
    local refs="${3:-}"
    local params
    if [[ -n "$refs" ]]; then
        params=$(jq -n --arg t "$kind" --arg c "$content" --arg r "$refs" \
            '{type:$t, content:$c, commitmentId:$r}' 2>/dev/null)
    else
        params=$(jq -n --arg t "$kind" --arg c "$content" \
            '{type:$t, content:$c}' 2>/dev/null)
    fi
    _mentu_rpc "capture" "$params" | jq -r '.id // empty' 2>/dev/null
}

# Create a commitment. Prints cmt_id.
mentu_commit() {
    local title="$1"
    local source="${2:-}"
    local tags="${3:-}"
    local params
    params=$(jq -n --arg t "$title" --arg a "agent:ralph-seq" '{title:$t, actor:$a}' 2>/dev/null)
    if [[ -n "$source" ]]; then
        params=$(echo "$params" | jq --arg s "$source" '. + {sourceMemoryId:$s}' 2>/dev/null)
    fi
    if [[ -n "$tags" ]]; then
        params=$(echo "$params" | jq --arg t "$tags" '. + {tags: ($t | split(","))}' 2>/dev/null)
    fi
    _mentu_rpc "commit" "$params" | jq -r '.id // empty' 2>/dev/null
}

# Claim a commitment. Returns 0 on success.
mentu_claim() {
    local cmt_id="$1"
    local params=$(jq -n --arg id "$cmt_id" '{commitmentId:$id}' 2>/dev/null)
    _mentu_rpc "claim" "$params" >/dev/null 2>&1
}

# Link two entities. Prints lnk_id.
mentu_link() {
    local source_id="$1"
    local target_id="$2"
    local kind="${3:-related}"
    local params=$(jq -n --arg s "$source_id" --arg t "$target_id" --arg k "$kind" \
        '{sourceId:$s, targetId:$t, kind:$k}' 2>/dev/null)
    _mentu_rpc "link" "$params" | jq -r '.id // empty' 2>/dev/null
}

# Annotate a commitment.
mentu_annotate() {
    local cmt_id="$1"
    local note="$2"
    local params=$(jq -n --arg id "$cmt_id" --arg n "$note" '{commitmentId:$id, note:$n}' 2>/dev/null)
    _mentu_rpc "annotate" "$params" >/dev/null 2>&1
}

# Close a commitment with evidence.
mentu_close() {
    local cmt_id="$1"
    local evidence="${2:-}"
    local verdict="pass"
    if [[ -n "$evidence" ]]; then
        verdict="pass (evidence: ${evidence})"
    fi
    local params=$(jq -n --arg id "$cmt_id" --arg v "$verdict" '{commitmentId:$id, verdict:$v}' 2>/dev/null)
    _mentu_rpc "close" "$params" >/dev/null 2>&1
}

# Submit a commitment.
mentu_submit() {
    local cmt_id="$1"
    local params=$(jq -n --arg id "$cmt_id" '{commitmentId:$id}' 2>/dev/null)
    _mentu_rpc "submit" "$params" >/dev/null 2>&1
}
