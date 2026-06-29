#!/usr/bin/env bash
# poll-approval.sh — Check pending_reviews.json for GH PR approval.
# On approval, invokes Claude Code to implement via invoke-impl.sh.
# Designed to run as a cron every 30 minutes.
#
# Usage: poll-approval.sh (no arguments — reads ~/.hermes/pending_reviews.json)

set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TOOLS_DIR/config.sh"

STATE_FILE="$HOME/.hermes/pending_reviews.json"

[[ -f "$STATE_FILE" ]] || exit 0
STATUS=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('approval_status',''))" 2>/dev/null)
[[ "$STATUS" == "pending" ]] || exit 0

PR_NUMBER=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['pr_number'])")
BRANCH=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['branch'])")
ISSUE=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['issue'])")
DESIGN_DOC=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['design_doc_path'])")
PR_URL=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('pr_url',''))")

APPROVED=0
GH_DECISION=$(gh pr view "$PR_NUMBER" --repo "$GITHUB_REPO" --json reviewDecision --jq '.reviewDecision' 2>/dev/null || echo "")
[[ "$GH_DECISION" == "APPROVED" ]] && { log "GitHub PR #$PR_NUMBER approved"; APPROVED=1; }

if [[ $APPROVED -eq 1 ]]; then
    python3 -c "
import json
with open('$STATE_FILE') as f: d = json.load(f)
d['approval_status'] = 'approved'
with open('$STATE_FILE', 'w') as f: json.dump(d, f, indent=2)
"
    log "Firing invoke-impl.sh for issue #$ISSUE"
    bash "$TOOLS_DIR/invoke-impl.sh" "$ISSUE" "$BRANCH" "$DESIGN_DOC" "$PR_URL"
else
    log "PR #$PR_NUMBER not yet approved — will check again later"
fi
