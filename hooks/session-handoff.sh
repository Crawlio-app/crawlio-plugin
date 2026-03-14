#!/usr/bin/env bash
# session-handoff.sh — Stop hook
# Writes a handoff summary when a Crawlio session ends.
# Captures git state, recent changes, and session context.
#
# Hook contract: receives JSON on stdin. Exit 0 = allow stop.

set -euo pipefail

# Only write handoff if we're in a project with .crawlio/ or .ralph/
AGENT_DIR=""
if [[ -d ".crawlio/agent" ]]; then
  AGENT_DIR=".crawlio/agent"
elif [[ -d ".ralph/agent" ]]; then
  AGENT_DIR=".ralph/agent"
else
  exit 0
fi

HANDOFF_FILE="${AGENT_DIR}/handoff.md"
SUMMARY_FILE="${AGENT_DIR}/summary.md"

# Write handoff
{
  echo "# Session Handoff"
  echo ""
  echo "_Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)_"
  echo ""
  echo "## Git Context"
  echo ""
  echo "- **Branch:** $(git branch --show-current 2>/dev/null || echo 'unknown')"
  echo "- **HEAD:** $(git log --oneline -1 2>/dev/null || echo 'unknown')"
  echo ""
  echo "## Recent Changes"
  echo ""
  echo '```'
  git diff --stat HEAD~1 2>/dev/null || echo "(no recent changes)"
  echo '```'
} > "$HANDOFF_FILE" 2>/dev/null

# Write summary
{
  echo "# Session Summary"
  echo ""
  echo "- **Ended:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- **Branch:** $(git branch --show-current 2>/dev/null || echo 'unknown')"
  echo "- **Commits this session:** $(git log --oneline --since='1 hour ago' 2>/dev/null | wc -l | tr -d ' ')"
} > "$SUMMARY_FILE" 2>/dev/null

exit 0
