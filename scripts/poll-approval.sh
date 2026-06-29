#!/usr/bin/env bash
# poll-approval.sh — Check pending_reviews.json for GitHub PR approval.
# On approval, fires invoke-impl.sh. Designed to run as a cron every 30 minutes.
#
# Usage: poll-approval.sh (no arguments)

set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"

STATE_FILE="$HOME/.hermes/pending_reviews.json"
[[ -f "$STATE_FILE" ]] || exit 0

STATUS=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('approval_status',''))" 2>/dev/null)
[[ "$STATUS" == "pending" ]] || exit 0

read_field() { python3 -c "import json; print(json.load(open('$STATE_FILE'))['$1'])"; }

PR_NUMBER=$(read_field pr_number)
BRANCH=$(read_field branch)
ISSUE=$(read_field issue)
DESIGN_DOC=$(read_field design_doc_path)
PR_URL=$(read_field pr_url)
GITHUB_REPO=$(read_field github_repo)

echo "[poll-approval] Checking PR #$PR_NUMBER on $GITHUB_REPO..." >&2

GH_DECISION=$(gh pr view "$PR_NUMBER" --repo "$GITHUB_REPO" --json reviewDecision --jq '.reviewDecision' 2>/dev/null || echo "")

if [[ "$GH_DECISION" == "APPROVED" ]]; then
    echo "[poll-approval] PR #$PR_NUMBER approved — firing invoke-impl.sh" >&2
    python3 -c "
import json
with open('$STATE_FILE') as f: d = json.load(f)
d['approval_status'] = 'approved'
with open('$STATE_FILE', 'w') as f: json.dump(d, f, indent=2)
"
    # Source config from state-file values so invoke-impl gets the right env
    export REPO_PATH=$(read_field repo)
    export GITHUB_REPO
    source "$TOOLS_DIR/config.sh"
    bash "$TOOLS_DIR/invoke-impl.sh" "$ISSUE" "$BRANCH" "$DESIGN_DOC" "$PR_URL"
else
    echo "[poll-approval] Not yet approved (decision: ${GH_DECISION:-none}) — will check again later" >&2
fi
