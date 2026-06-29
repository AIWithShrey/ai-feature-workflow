#!/usr/bin/env bash
# apply-code-fixes.sh — Claude Code applies fixes from a REVIEW_CODE_*.md file.
# Called automatically by the post-commit hook on REVIEW_CODE_* commits.
#
# Usage: apply-code-fixes.sh <review-file> <branch>

set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TOOLS_DIR/config.sh"

REVIEW_FILE="${1:?review file required}"
BRANCH="${2:?branch required}"

[[ -f "$REVIEW_FILE" ]] || { log "Review file not found: $REVIEW_FILE"; exit 1; }

REVIEW_BASENAME=$(basename "$REVIEW_FILE")
CMD_NAME="fix-$(echo "$REVIEW_BASENAME" | sed 's/REVIEW_CODE_//;s/\.md//')"
CMD_FILE="$REPO_PATH/.claude/commands/${CMD_NAME}.md"

mkdir -p "$REPO_PATH/.claude/commands"
cat > "$CMD_FILE" <<CMDEOF
# Fix code review issues: ${REVIEW_BASENAME}

Fix EVERY CRITICAL and HIGH issue. Fix MEDIUM issues unless there is a clear reason not to. LOW is discretionary.

After fixing:
1. Run the repo's test and lint commands — all must pass
2. Commit: fix: address code review issues from ${REVIEW_BASENAME}
3. Do NOT push — the post-commit hook re-triggers review automatically

--- REVIEW ---
$(cat "$REVIEW_FILE")
--- END REVIEW ---
CMDEOF

SESSION="cc-fix-$(date +%s)"
tmux new-session -d -s "$SESSION" -x 220 -y 50
tmux send-keys -t "$SESSION" "cd $REPO_PATH && claude" Enter
sleep 7
tmux send-keys -t "$SESSION" BTab; sleep 0.4
tmux send-keys -t "$SESSION" BTab; sleep 0.4
tmux send-keys -t "$SESSION" BTab; sleep 0.5
tmux send-keys -t "$SESSION" "/${CMD_NAME}" Enter

ELAPSED=0
while tmux has-session -t "$SESSION" 2>/dev/null && [[ $ELAPSED -lt 1800 ]]; do
    sleep 30; ELAPSED=$((ELAPSED + 30))
    PANE=$(tmux capture-pane -t "$SESSION" -p -S -5 2>/dev/null || echo "")
    echo "$PANE" | grep -q "Do you want to proceed" && tmux send-keys -t "$SESSION" Enter
done
tmux kill-session -t "$SESSION" 2>/dev/null || true

slack_dm "🔧 *Fix cycle complete* for \`$BRANCH\` — re-review will trigger on next commit"
log "Fix cycle complete"
