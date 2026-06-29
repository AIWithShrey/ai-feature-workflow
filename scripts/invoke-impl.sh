#!/usr/bin/env bash
# invoke-impl.sh — Runs Claude Code to implement an approved design spec.
# Writes a .claude/commands/<name>.md task file, launches Claude Code via tmux,
# waits for completion, then commits.
#
# Usage: invoke-impl.sh <issue-number> <branch> <proposal-file> <pr-url>

set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TOOLS_DIR/config.sh"

ISSUE_NUMBER="${1:?issue number required}"
BRANCH="${2:?branch required}"
PROPOSAL_FILE="${3:?proposal file required}"
PR_URL="${4:?pr url required}"

[[ -f "$PROPOSAL_FILE" ]] || { log "Proposal not found: $PROPOSAL_FILE"; exit 1; }

cd "$OTTOFLOW_REPO"
git checkout "$BRANCH"
git pull origin "$BRANCH" --rebase

ISSUE_TITLE=$(gh issue view "$ISSUE_NUMBER" --repo "$GITHUB_REPO" --json title --jq '.title' 2>/dev/null || echo "Issue #$ISSUE_NUMBER")
SLUG=$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-40)
CMD_NAME="impl-issue-${ISSUE_NUMBER}"
CMD_FILE="$OTTOFLOW_REPO/.claude/commands/${CMD_NAME}.md"

mkdir -p "$OTTOFLOW_REPO/.claude/commands"

log "Writing implementation task to $CMD_FILE"
cat > "$CMD_FILE" <<CMDEOF
# Implement issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}

Branch: ${BRANCH}
Issue: #${ISSUE_NUMBER} — ${ISSUE_TITLE}
Repo root: ${OTTOFLOW_REPO}

Read the approved design specification from: ${PROPOSAL_FILE}

Implementation rules:
1. Read AGENTS.md and existing code patterns before writing anything
2. Run gitnexus impact analysis before modifying any existing symbol
3. Implement ALL acceptance criteria from the spec
4. After implementation run in order and fix ALL errors:
   - make generate manifests
   - go build ./...
   - go test ./...
   - make lint
5. Commit with message: feat: implement ${ISSUE_TITLE} (issue #${ISSUE_NUMBER})
6. Do NOT push — the calling script handles push.
CMDEOF

slack_dm "🚀 *Implementation started* for #${ISSUE_NUMBER}: ${ISSUE_TITLE}
Branch: \`${BRANCH}\`"

log "Launching Claude Code via tmux"
SESSION="cc-impl-${ISSUE_NUMBER}"
tmux new-session -d -s "$SESSION" -x 220 -y 50
tmux send-keys -t "$SESSION" "cd $OTTOFLOW_REPO && claude" Enter
sleep 7

# Cycle to accept-edits mode (shift+tab 3 times: plan → normal → accept-edits)
tmux send-keys -t "$SESSION" BTab
sleep 0.4
tmux send-keys -t "$SESSION" BTab
sleep 0.4
tmux send-keys -t "$SESSION" BTab
sleep 0.5

tmux send-keys -t "$SESSION" "/${CMD_NAME}" Enter

log "Claude Code running in tmux session '$SESSION' — waiting for completion"
log "Monitor with: tmux capture-pane -t $SESSION -p -S -40"

# Poll until the session ends (Claude Code exits when task is done) or timeout (60 min)
TIMEOUT=3600
ELAPSED=0
while tmux has-session -t "$SESSION" 2>/dev/null && [[ $ELAPSED -lt $TIMEOUT ]]; do
    sleep 30
    ELAPSED=$((ELAPSED + 30))
    # Approve any command_substitution prompts automatically
    PANE=$(tmux capture-pane -t "$SESSION" -p -S -5 2>/dev/null || echo "")
    if echo "$PANE" | grep -q "Do you want to proceed"; then
        tmux send-keys -t "$SESSION" Enter
    fi
done

tmux kill-session -t "$SESSION" 2>/dev/null || true

# Verify commit landed
COMMIT=$(git -C "$OTTOFLOW_REPO" log -1 --format="%s" 2>/dev/null)
log "Last commit: $COMMIT"

slack_dm "✅ *Implementation complete* for #${ISSUE_NUMBER}
Branch: \`${BRANCH}\`
Last commit: $COMMIT"

log "Done. Push with: git push origin $BRANCH"
