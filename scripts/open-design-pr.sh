#!/usr/bin/env bash
# open-design-pr.sh — Commit approved proposal, open PR, post Slack, write pending_reviews.json.
#
# Usage: open-design-pr.sh <issue-number> <branch> <proposal-file>

set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TOOLS_DIR/config.sh"

ISSUE_NUMBER="${1:?issue number required}"
BRANCH="${2:?branch required}"
PROPOSAL_FILE="${3:?proposal file required}"
STATE_FILE="$HOME/.hermes/pending_reviews.json"

[[ -f "$PROPOSAL_FILE" ]] || { log "Proposal not found: $PROPOSAL_FILE"; exit 1; }

cd "$OTTOFLOW_REPO"
git checkout "$BRANCH"
git add "$PROPOSAL_FILE" docs/dev/IMPLEMENTATION_PLAN.md 2>/dev/null || git add "$PROPOSAL_FILE"
git diff --cached --quiet || git commit -m "docs: design proposal for issue #${ISSUE_NUMBER} (adversarially reviewed)"
git push origin "$BRANCH"

ISSUE_TITLE=$(gh issue view "$ISSUE_NUMBER" --repo "$GITHUB_REPO" --json title --jq '.title' 2>/dev/null || echo "Issue #$ISSUE_NUMBER")
REVIEWER_GH="${GITHUB_PR_REVIEWER:-patelrit}"
ASSIGNEE="${GITHUB_PR_ASSIGNEE:-AIWithShrey}"

PR_URL=$(gh pr create \
    --title "Design: $ISSUE_TITLE (issue #$ISSUE_NUMBER)" \
    --body "Closes #${ISSUE_NUMBER}

Design proposal — adversarially reviewed and approved.

**Proposal**: \`$(basename "$PROPOSAL_FILE")\`

> Approve this PR to trigger implementation." \
    --repo "$GITHUB_REPO" \
    --head "$BRANCH" \
    --reviewer "$REVIEWER_GH" \
    --assignee "$ASSIGNEE" 2>/dev/null)

PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')
log "Opened PR #$PR_NUMBER: $PR_URL"

MENTION="${SLACK_REVIEWER_SLACK_ID:+<@${SLACK_REVIEWER_SLACK_ID}>}"
slack_dev "📋 *Design review requested* for #${ISSUE_NUMBER}: ${ISSUE_TITLE}
<${PR_URL}|PR #${PR_NUMBER}> — please review and approve. ${MENTION}"

# Write state for poll-approval.sh
mkdir -p "$(dirname "$STATE_FILE")"
python3 - <<PYEOF
import json
state = {
    "pr_number": $PR_NUMBER,
    "pr_url": "$PR_URL",
    "branch": "$BRANCH",
    "issue": $ISSUE_NUMBER,
    "design_doc_path": "$PROPOSAL_FILE",
    "channel": "${SLACK_DEV_CHANNEL:-}",
    "approval_status": "pending"
}
with open("$STATE_FILE", "w") as f:
    json.dump(state, f, indent=2)
PYEOF

log "State written to $STATE_FILE"
