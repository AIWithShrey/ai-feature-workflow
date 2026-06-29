#!/usr/bin/env bash
# review-code.sh — Gemini reviews a git commit diff, optionally grounded by an Obsidian KB.
# On APPROVED: pushes to remote + Slack notification.
# On NEEDS REVISION: commits REVIEW_CODE_<sha>.md → apply-code-fixes.sh handles it.
#
# Usage: review-code.sh <commit-sha> <branch>

set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TOOLS_DIR/config.sh"

COMMIT_SHA="${1:?commit sha required}"
BRANCH="${2:?branch required}"
SHORT_SHA="${COMMIT_SHA:0:7}"
COMMIT_MSG=$(git -C "$REPO_PATH" log -1 --format="%s" "$COMMIT_SHA")
REVIEW_FILE="$REPO_PATH/docs/dev/REVIEW_CODE_${SHORT_SHA}.md"

log "Reviewing $SHORT_SHA: $COMMIT_MSG"
slack_dm "🔍 *Code review started* for \`$SHORT_SHA\` on \`$BRANCH\`
> $COMMIT_MSG"

# Load KB notes if configured
KB_SECTION="No knowledge base configured — review proceeds without KB grounding."
if [[ -n "$KB_DIR" && -d "$KB_DIR" ]]; then
    KB_CONTEXT=""
    load_note() {
        local file="$KB_DIR/$1"
        [[ -f "$file" ]] || return 0
        KB_CONTEXT+=$'\n\n'"=== KB: $1 ==="$'\n'$(cat "$file")"
    }
    load_note "_Index.md"; load_note "Architecture.md"; load_note "Types.md"; load_note "Flows.md"
    TOUCHED_PKGS=$(git -C "$REPO_PATH" show "$COMMIT_SHA" --name-only \
        | grep '\.go$' | sed 's|/[^/]*\.go$||' | sort -u 2>/dev/null || true)
    while IFS= read -r pkg; do
        load_note "packages/$(basename "$pkg").md"
    done <<< "$TOUCHED_PKGS"
    [[ ${#KB_CONTEXT} -gt 40000 ]] && KB_CONTEXT="${KB_CONTEXT:0:40000}"$'\n[...truncated at 40KB...]'
    KB_SECTION="Ground every review comment in this knowledge base:
$KB_CONTEXT"
fi

# Build diff — exclude generated files
DIFF=$(git -C "$REPO_PATH" show "$COMMIT_SHA" \
    -- '*.go' '*.yaml' '*.yml' '*.json' '*.ts' '*.py' \
    ':(exclude)*zz_generated*' \
    ':(exclude)*.pb.go' \
    2>/dev/null | head -c 60000)

[[ -n "$DIFF" ]] || { log "No reviewable files in this commit — skipping"; exit 0; }

PROMPT="You are a senior engineer reviewing a commit on the $GITHUB_REPO repository.

$KB_SECTION

--- DIFF ---
$DIFF
--- END DIFF ---

Output MUST start with exactly one of these two lines:
  APPROVED
  NEEDS REVISION

Then for NEEDS REVISION, list findings:
  :red_circle: CRITICAL|HIGH — file:line — description
  :large_yellow_circle: MEDIUM — file:line — description

Rules:
- Ground every finding in the KB or the diff. No speculation.
- Substantive issues only: security, correctness, race conditions, API consistency.
- Do NOT raise style or naming issues."

REVIEW=$(hermes chat -q "$PROMPT" 2>/dev/null)
VERDICT=$(echo "$REVIEW" | head -1 | tr -d ' ')

if [[ "$VERDICT" == "APPROVED" ]]; then
    log "APPROVED — pushing $BRANCH"
    git -C "$REPO_PATH" push origin "$BRANCH"
    slack_dm "✅ *Code review APPROVED* — \`$SHORT_SHA\` pushed to \`$BRANCH\`
> $COMMIT_MSG"
else
    log "NEEDS REVISION — writing $REVIEW_FILE"
    mkdir -p "$(dirname "$REVIEW_FILE")"
    echo "$REVIEW" > "$REVIEW_FILE"
    git -C "$REPO_PATH" add "$REVIEW_FILE"
    git -C "$REPO_PATH" commit -m "review: code review for $SHORT_SHA"
    slack_dm "🔄 *Code review requested changes* for \`$SHORT_SHA\` on \`$BRANCH\`
Fixes will be applied automatically via post-commit hook."
fi
