#!/usr/bin/env bash
# invoke-impl.sh — Run Claude Code to implement an approved design spec.
# Writes a .claude/commands/<name>.md task, launches Claude Code in tmux, waits.
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

cd "$REPO_PATH"
git checkout "$BRANCH"
git pull origin "$BRANCH" --rebase

ISSUE_TITLE=$(gh issue view "$ISSUE_NUMBER" --repo "$GITHUB_REPO" --json title --jq '.title' 2>/dev/null || echo "Issue #$ISSUE_NUMBER")
CMD_NAME="impl-issue-${ISSUE_NUMBER}"
CMD_FILE="$REPO_PATH/.claude/commands/${CMD_NAME}.md"

mkdir -p "$REPO_PATH/.claude/commands"
cat > "$CMD_FILE" <<CMDEOF
# Implement issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}

Branch: ${BRANCH}
Issue: #${ISSUE_NUMBER} — ${ISSUE_TITLE}
Repo root: ${REPO_PATH}

Read the approved design specification from: ${PROPOSAL_FILE}

Implementation rules:
1. Read AGENTS.md (if present) and existing code patterns before writing anything
2. Run impact analysis before modifying any existing symbol
3. Implement ALL acceptance criteria from the spec
4. After implementation, run the repo's quality gates (tests, linter, build) and fix ALL errors
5. Commit with message: feat: implement ${ISSUE_TITLE} (issue #${ISSUE_NUMBER})
6. Do NOT push — the calling script handles push
CMDEOF

log "Task file written to $CMD_FILE"
slack_dm "🚀 *Implementation started* for #${ISSUE_NUMBER}: ${ISSUE_TITLE}
Branch: \`${BRANCH}\`"

SESSION="cc-impl-${ISSUE_NUMBER}"
tmux new-session -d -s "$SESSION" -x 220 -y 50
tmux send-keys -t "$SESSION" "cd $REPO_PATH && claude" Enter
sleep 7
# Shift+Tab 3x: plan → normal → accept-edits
tmux send-keys -t "$SESSION" BTab; sleep 0.4
tmux send-keys -t "$SESSION" BTab; sleep 0.4
tmux send-keys -t "$SESSION" BTab; sleep 0.5
tmux send-keys -t "$SESSION" "/${CMD_NAME}" Enter

log "Claude Code running in tmux session '$SESSION'"
log "Monitor with: tmux capture-pane -t $SESSION -p -S -40"

# Wait up to 60 min; auto-approve any command_substitution prompts
ELAPSED=0
while tmux has-session -t "$SESSION" 2>/dev/null && [[ $ELAPSED -lt 3600 ]]; do
    sleep 30; ELAPSED=$((ELAPSED + 30))
    PANE=$(tmux capture-pane -t "$SESSION" -p -S -5 2>/dev/null || echo "")
    echo "$PANE" | grep -q "Do you want to proceed" && tmux send-keys -t "$SESSION" Enter
done
tmux kill-session -t "$SESSION" 2>/dev/null || true

LAST_COMMIT=$(git -C "$REPO_PATH" log -1 --format="%s" 2>/dev/null)
log "Last commit: $LAST_COMMIT"
slack_dm "✅ *Implementation complete* for #${ISSUE_NUMBER}
Branch: \`${BRANCH}\`
Commit: $LAST_COMMIT"
