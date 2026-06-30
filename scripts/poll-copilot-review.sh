#!/usr/bin/env bash
# poll-copilot-review.sh — Check all open PRs for unresolved Copilot review threads.
# When found, fires address-copilot-comments.sh automatically.
# Designed to run on a cron schedule (e.g. every 15 minutes).
#
# Usage: poll-copilot-review.sh (no arguments)

set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TOOLS_DIR/config.sh"

log "Polling open PRs for unresolved Copilot review threads..."

# Get all open PRs
OPEN_PRS=$(gh pr list --repo "$GITHUB_REPO" --state open --json number,headRefName \
    --jq '.[] | "\(.number) \(.headRefName)"' 2>/dev/null || echo "")

if [[ -z "$OPEN_PRS" ]]; then
    log "No open PRs found"
    exit 0
fi

while IFS=" " read -r PR_NUMBER BRANCH; do
    [[ -z "$PR_NUMBER" ]] && continue

    # Check for unresolved Copilot threads on this PR
    UNRESOLVED=$(gh api graphql -f query="{
      repository(owner: \"${GITHUB_REPO%%/*}\", name: \"${GITHUB_REPO##*/}\") {
        pullRequest(number: $PR_NUMBER) {
          reviewThreads(first: 50) {
            nodes {
              isResolved
              comments(first: 1) { nodes { author { login } } }
            }
          }
        }
      }
    }" --jq '[.data.repository.pullRequest.reviewThreads.nodes[]
              | select(.isResolved == false
                 and .comments.nodes[0].author.login == "Copilot")]
             | length' 2>/dev/null || echo "0")

    if [[ "$UNRESOLVED" -gt 0 ]]; then
        log "PR #$PR_NUMBER ($BRANCH): $UNRESOLVED unresolved Copilot thread(s) — firing address script"
        bash "$TOOLS_DIR/address-copilot-comments.sh" "$PR_NUMBER" "$BRANCH"
    else
        log "PR #$PR_NUMBER: no unresolved Copilot threads"
    fi
done <<< "$OPEN_PRS"

log "Poll complete"
