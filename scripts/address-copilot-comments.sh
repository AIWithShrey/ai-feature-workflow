#!/usr/bin/env bash
# address-copilot-comments.sh — Fetch unresolved Copilot PR review threads, have
# Claude Code address every comment, push, resolve threads, and ping the reviewer.
#
# Usage: address-copilot-comments.sh <pr-number> <branch>

set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TOOLS_DIR/config.sh"

PR_NUMBER="${1:?pr number required}"
BRANCH="${2:?branch required}"

OWNER="${GITHUB_REPO%%/*}"
REPO_NAME="${GITHUB_REPO##*/}"

log "Fetching Copilot review comments for PR #$PR_NUMBER..."

# Fetch all unresolved Copilot inline comments (path + line + body)
COMMENTS_JSON=$(gh api "repos/$GITHUB_REPO/pulls/$PR_NUMBER/comments" \
    --jq '[.[] | select(.user.login == "Copilot") | {path: .path, line: .line, body: .body}]' \
    2>/dev/null || echo "[]")

COUNT=$(echo "$COMMENTS_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")

if [[ "$COUNT" == "0" ]]; then
    log "No Copilot comments found on PR #$PR_NUMBER — nothing to do"
    exit 0
fi

log "Found $COUNT Copilot comment(s) — building fix task"
slack_dm "🤖 *Copilot review detected* — $COUNT comment(s) on PR #${PR_NUMBER}
Addressing automatically on \`${BRANCH}\`..."

# Format comments for Claude Code task
FORMATTED=$(echo "$COMMENTS_JSON" | python3 -c "
import json, sys
comments = json.load(sys.stdin)
for i, c in enumerate(comments, 1):
    print(f\"### Comment {i} — {c['path']} line {c['line']}\")
    print(c['body'])
    print()
")

CMD_NAME="fix-copilot-pr${PR_NUMBER}"
CMD_FILE="$REPO_PATH/.claude/commands/${CMD_NAME}.md"

mkdir -p "$REPO_PATH/.claude/commands"
cat > "$CMD_FILE" <<CMDEOF
# Address Copilot review comments on PR #${PR_NUMBER}

Fix ALL of the following Copilot review comments. For each:
- Read the referenced file and line carefully before changing anything.
- Apply the minimal correct fix — do NOT refactor unrelated code.
- If a comment identifies a cross-file inconsistency (e.g. CRD vs Go types vs docs),
  fix ALL affected files, not just the one referenced.

After ALL fixes:
1. Run quality gates:
   make generate manifests
   go build ./...
   go test ./...
   make lint
   All must pass with zero errors.
2. Coherence check — for any renamed or changed API field:
   - Verify CRD YAMLs (config/crd/, charts/ottoflow/crds/) match Go types
   - Grep docs/ and samples/ for the old and new field names and fix any stale references
3. Commit with message: fix: address Copilot review comments on PR #${PR_NUMBER}
4. Do NOT push — the calling script handles push and thread resolution.

---

${FORMATTED}
CMDEOF

log "Command file written: $CMD_FILE"

# Ensure we are on the right branch with latest
cd "$REPO_PATH"
git checkout "$BRANCH"
git pull origin "$BRANCH" --rebase

# Launch Claude Code in accept-edits mode
SESSION="cc-copilot-pr${PR_NUMBER}"
tmux new-session -d -s "$SESSION" -x 220 -y 50
tmux send-keys -t "$SESSION" "cd $REPO_PATH && claude" Enter
sleep 7
tmux send-keys -t "$SESSION" BTab; sleep 0.4
tmux send-keys -t "$SESSION" BTab; sleep 0.4
tmux send-keys -t "$SESSION" BTab; sleep 0.5
tmux send-keys -t "$SESSION" "/${CMD_NAME}" Enter

log "Claude Code running in tmux session '$SESSION'"

# Wait up to 60 min; auto-approve any command_substitution prompts
ELAPSED=0
while tmux has-session -t "$SESSION" 2>/dev/null && [[ $ELAPSED -lt 3600 ]]; do
    sleep 30; ELAPSED=$((ELAPSED + 30))
    PANE=$(tmux capture-pane -t "$SESSION" -p -S -5 2>/dev/null || echo "")
    echo "$PANE" | grep -q "Do you want to proceed" && tmux send-keys -t "$SESSION" Enter
done
tmux kill-session -t "$SESSION" 2>/dev/null || true

LAST_COMMIT=$(git -C "$REPO_PATH" log -1 --format="%s")
log "Last commit: $LAST_COMMIT"

# Push
git -C "$REPO_PATH" push origin "$BRANCH"
log "Pushed $BRANCH"

# Resolve all unresolved Copilot threads via GraphQL
log "Resolving Copilot review threads..."
THREAD_IDS=$(gh api graphql -f query="{
  repository(owner: \"$OWNER\", name: \"$REPO_NAME\") {
    pullRequest(number: $PR_NUMBER) {
      reviewThreads(first: 50) {
        nodes {
          id isResolved
          comments(first: 1) { nodes { author { login } } }
        }
      }
    }
  }
}" --jq '[.data.repository.pullRequest.reviewThreads.nodes[]
          | select(.isResolved == false
             and .comments.nodes[0].author.login == "Copilot")
          | .id][]' 2>/dev/null || true)

RESOLVED=0
while IFS= read -r tid; do
    [[ -z "$tid" ]] && continue
    gh api graphql -f query="mutation {
      resolveReviewThread(input: {threadId: \"$tid\"}) {
        thread { isResolved }
      }
    }" --jq '.data.resolveReviewThread.thread.isResolved' >/dev/null 2>&1 && RESOLVED=$((RESOLVED + 1))
done <<< "$THREAD_IDS"

log "Resolved $RESOLVED thread(s)"

# Ping reviewer on team/code-review channel
PR_URL="https://github.com/$GITHUB_REPO/pull/$PR_NUMBER"
[[ -n "${SLACK_REVIEWER_ID:-}" ]] && MENTION="<@$SLACK_REVIEWER_ID> " || MENTION=""
slack_team "${MENTION}All Copilot review comments on PR #${PR_NUMBER} have been addressed — ${PR_URL}"

slack_dm "✅ *Copilot review addressed* — PR #${PR_NUMBER}
$RESOLVED thread(s) resolved. Reviewer notified."
log "Done"
