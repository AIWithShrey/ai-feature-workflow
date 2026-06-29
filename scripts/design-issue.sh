#!/usr/bin/env bash
# design-issue.sh — Draft a design proposal for a GitHub issue, then run adversarial review.
#
# Usage: design-issue.sh <issue-number>

set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TOOLS_DIR/config.sh"

ISSUE_NUMBER="${1:?Usage: design-issue.sh <issue-number>}"

command -v gh &>/dev/null || { log "gh CLI not found (brew install gh)"; exit 1; }

ISSUE_TITLE=$(gh issue view "$ISSUE_NUMBER" --repo "$GITHUB_REPO" --json title --jq '.title' 2>/dev/null)
[[ -n "$ISSUE_TITLE" ]] || { log "Could not fetch issue #$ISSUE_NUMBER from $GITHUB_REPO"; exit 1; }

log "Drafting design for issue #$ISSUE_NUMBER: $ISSUE_TITLE"

hermes --profile design-docs chat -q \
  "Design doc task for issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}

Repo path: $REPO_PATH
GitHub repo: $GITHUB_REPO

Steps:
1. Read the full issue: gh issue view ${ISSUE_NUMBER} --repo $GITHUB_REPO --comments
2. Read AGENTS.md and any existing design/architecture docs in the repo
3. Analyse codebase files relevant to this issue
4. Create branch docs/issue-${ISSUE_NUMBER}-<slug> off main
5. Write the proposal doc and update any implementation plan
6. DO NOT commit or push
7. Print on the last line: RESULT branch=<branch> proposal=<absolute-path>"

# Detect branch + proposal from git/filesystem
BRANCH=$(git -C "$REPO_PATH" branch --list "docs/issue-${ISSUE_NUMBER}-*" | tr -d ' *' | head -1)
PROPOSAL=$(find "$REPO_PATH/docs" -name "PROPOSAL_*.md" -newer "$REPO_PATH/docs" 2>/dev/null | head -1)

[[ -n "$BRANCH" && -n "$PROPOSAL" ]] || {
    log "Could not detect branch or proposal from design-docs output. Check output above."
    exit 1
}

log "Proposal ready: $PROPOSAL on $BRANCH"
log "Starting adversarial review..."

exec bash "$TOOLS_DIR/review-design.sh" "$PROPOSAL" 3 "$ISSUE_NUMBER" "$BRANCH"
