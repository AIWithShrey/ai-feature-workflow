#!/usr/bin/env bash
# explore-repo.sh — Trigger codebase-explorer profile to rebuild the Obsidian KB.
# Called by the post-merge hook when landing on main. Can also be run manually.
#
# Usage: explore-repo.sh <repo-path> [focus-hint]

set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TOOLS_DIR/config.sh"

REPO_PATH="${1:-$OTTOFLOW_REPO}"
FOCUS="${2:-}"

[[ -d "$REPO_PATH/.git" ]] || { log "Not a git repo: $REPO_PATH"; exit 1; }
[[ -n "$OTTOFLOW_KB_VAULT" ]] || { log "OTTOFLOW_KB_VAULT not set — skipping KB build"; exit 0; }

REPO_NAME=$(basename "$REPO_PATH")
NOTES_DIR="$OTTOFLOW_KB_VAULT/Codebases/$REPO_NAME"
SHORT_SHA=$(git -C "$REPO_PATH" rev-parse --short HEAD 2>/dev/null || echo "?")
COMMIT_MSG=$(git -C "$REPO_PATH" log -1 --format="%s" 2>/dev/null || echo "?")

mkdir -p "$NOTES_DIR"
log "Building KB for $REPO_NAME ($SHORT_SHA)"
slack_dm "🗺️ *KB build started* for \`$REPO_NAME\`
Commit: \`$SHORT_SHA\` — $COMMIT_MSG"

PROMPT="Build a complete knowledge graph for the repository at $REPO_PATH.

Obsidian vault: $OTTOFLOW_KB_VAULT
Notes destination: $NOTES_DIR
Repo name: $REPO_NAME
$([ -n "$FOCUS" ] && echo "Focus: $FOCUS" || true)

Follow your SOUL.md instructions. Write every note to $NOTES_DIR/<name>.md using write_file.
Report: how many notes created, total files read, any gaps found."

OUTPUT=$(hermes --profile codebase-explorer chat -q "$PROMPT" 2>&1)
NOTE_COUNT=$(find "$NOTES_DIR" -name "*.md" | wc -l | tr -d ' ')

log "KB build complete — $NOTE_COUNT notes"
slack_dm "✅ *KB build complete* for \`$REPO_NAME\`: $NOTE_COUNT notes"
