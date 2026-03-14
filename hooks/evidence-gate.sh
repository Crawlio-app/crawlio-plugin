#!/usr/bin/env bash
# evidence-gate.sh — PostToolUse hook
# Warns when files are written directly to .crawlio/evidence/ without using
# wrapEvidence(). Direct writes bypass gap detection and quality derivation.
#
# Hook contract: receives JSON on stdin with tool_name, tool_input, tool_output.
# Exit 0 = allow (with optional warning message).

set -euo pipefail

INPUT=$(cat)

# Extract the file path from the tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)

# Check if writing to evidence directory
if [[ "$FILE_PATH" == *".crawlio/evidence/"* || "$FILE_PATH" == *"evidence/runs/"* ]]; then
  # Check if it's a known safe caller (wrapEvidence writes via writeEvidence)
  TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)

  # Bash tool running writeEvidence/wrapEvidence is OK
  if [[ "$TOOL_NAME" == "Bash" ]]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
    if [[ "$COMMAND" == *"writeEvidence"* || "$COMMAND" == *"wrapEvidence"* ]]; then
      exit 0
    fi
  fi

  # Direct Write/Edit to evidence directory — warn
  echo "WARNING: Direct write to evidence directory detected." >&2
  echo "  File: $FILE_PATH" >&2
  echo "  Use wrapEvidence() + writeEvidence() instead for proper gap detection and quality derivation." >&2
  echo "  Direct writes bypass: detectNullGaps(), deriveQuality(), metadata stamps." >&2
fi

exit 0
