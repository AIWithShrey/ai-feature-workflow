#!/usr/bin/env bash
# explore-repo.sh — Trigger the codebase-explorer Hermes profile to rebuild the KB.
# Called by the post-merge hook on main. Can also be run manually.
#
# Usage: explore-repo.sh <repo-path> [focus-hint]

set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TOOLS_DIR/config.sh"

REPO_PATH="${1:-$REPO_PATH}"
FOCUS="${2:-}"

[[ -d "$REPO_PATH/.git" ]] || { log "Not a git repo: $REPO_PATH"; exit 1; }

if [[ -z "$KB_VAULT" ]]; then
    log "KB_VAULT not set — skipping knowledge base rebuild (set KB_VAULT to enable)"
    exit 0
fi

REPO_NAME=$(basename "$REPO_PATH")
NOTES_DIR="$KB_VAULT/Codebases/$REPO_NAME"
SHORT_SHA=$(git -C "$REPO_PATH" rev-parse --short HEAD 2>/dev/null || echo "?")
COMMIT_MSG=$(git -C "$REPO_PATH" log -1 --format="%s" 2>/dev/null || echo "?")

mkdir -p "$NOTES_DIR"
log "Building KB for $REPO_NAME ($SHORT_SHA)"
slack_dm "🗺️ *KB build started* for \`$REPO_NAME\` — commit \`$SHORT_SHA\`: $COMMIT_MSG"

hermes --profile codebase-explorer chat -q \
"Build a complete knowledge graph for the repository at $REPO_PATH.

Obsidian vault: $KB_VAULT
Notes destination: $NOTES_DIR
Repo name: $REPO_NAME
$([ -n "$FOCUS" ] && echo "Focus: $FOCUS" || true)

Follow your instructions. Write every note to $NOTES_DIR/<name>.md using write_file.
Report: how many notes created, total files read, any gaps found." 2>&1

NOTE_COUNT=$(find "$NOTES_DIR" -name "*.md" | wc -l | tr -d ' ')
log "KB build complete — $NOTE_COUNT notes in $NOTES_DIR"
slack_dm "✅ *KB build complete* for \`$REPO_NAME\`: $NOTE_COUNT notes"
