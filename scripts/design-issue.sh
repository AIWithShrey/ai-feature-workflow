#!/usr/bin/env bash
# design-issue.sh — Draft a PROPOSAL_*.md for a GitHub issue, then run adversarial review.
#
# Usage: design-issue.sh <issue-number>
# Requires: OTTOFLOW_REPO set, gh CLI, hermes with design-docs profile

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

Repo path: $OTTOFLOW_REPO
GitHub repo: $GITHUB_REPO

Steps:
1. Read the full issue: gh issue view ${ISSUE_NUMBER} --repo $GITHUB_REPO --comments
2. Read AGENTS.md, docs/dev/DESIGN.md, docs/dev/IMPLEMENTATION_PLAN.md
3. Analyse codebase files relevant to this issue (search_files, read_file)
4. Create branch docs/issue-${ISSUE_NUMBER}-<slug> off main
5. Write docs/dev/PROPOSAL_<SLUG>.md and update docs/dev/IMPLEMENTATION_PLAN.md
6. DO NOT commit or push
7. Print on the last line: RESULT branch=<branch> proposal=<absolute-path>"

# Detect branch + proposal from git/filesystem
BRANCH=$(git -C "$OTTOFLOW_REPO" branch --list "docs/issue-${ISSUE_NUMBER}-*" | tr -d ' *' | head -1)
PROPOSAL=$(find "$OTTOFLOW_REPO/docs/dev" -name "PROPOSAL_*.md" -newer "$OTTOFLOW_REPO/docs/dev/IMPLEMENTATION_PLAN.md" 2>/dev/null | head -1)

[[ -n "$BRANCH" && -n "$PROPOSAL" ]] || { log "Could not detect branch or proposal — check design-docs output"; exit 1; }

log "Proposal ready: $PROPOSAL"
log "Branch: $BRANCH"
log "Starting adversarial review..."

exec bash "$TOOLS_DIR/review-design.sh" "$PROPOSAL" 3 "$ISSUE_NUMBER" "$BRANCH"
