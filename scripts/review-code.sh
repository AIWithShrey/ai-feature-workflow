#!/usr/bin/env bash
# review-code.sh — Gemini reviews a git commit diff, grounded by the Obsidian KB.
# On APPROVED: pushes to remote + Slack.
# On NEEDS REVISION: commits REVIEW_CODE_<sha>.md → fires apply-code-fixes.sh.
#
# Called by the post-commit hook automatically. Can also be run manually.
# Usage: review-code.sh <commit-sha> <branch>

set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TOOLS_DIR/config.sh"

COMMIT_SHA="${1:?commit sha required}"
BRANCH="${2:?branch required}"
SHORT_SHA="${COMMIT_SHA:0:7}"
COMMIT_MSG=$(git -C "$OTTOFLOW_REPO" log -1 --format="%s" "$COMMIT_SHA")
REVIEW_FILE="$OTTOFLOW_REPO/docs/dev/REVIEW_CODE_${SHORT_SHA}.md"

log "Code review for $SHORT_SHA: $COMMIT_MSG"
slack_dm "🔍 *Code review started* for \`$SHORT_SHA\` on \`$BRANCH\`
> $COMMIT_MSG"

# Load KB
KB_CONTEXT=""
load_note() {
    local file="${OTTOFLOW_KB_DIR}/$1"
    [[ -f "$file" ]] || return 0
    KB_CONTEXT+=$'\n\n'"=== KB: $1 ==="$'\n'
    KB_CONTEXT+=$(cat "$file")
}
if [[ -n "$OTTOFLOW_KB_DIR" && -d "$OTTOFLOW_KB_DIR" ]]; then
    load_note "_Index.md"; load_note "Architecture.md"; load_note "Types.md"; load_note "Flows.md"
    TOUCHED_PKGS=$(git -C "$OTTOFLOW_REPO" show "$COMMIT_SHA" --name-only \
        | grep '\.go$' | sed 's|/[^/]*\.go$||' | sort -u)
    while IFS= read -r pkg; do
        load_note "packages/$(basename "$pkg").md"
    done <<< "$TOUCHED_PKGS"
    [[ ${#KB_CONTEXT} -gt 40000 ]] && KB_CONTEXT="${KB_CONTEXT:0:40000}"$'\n[...truncated at 40KB...]'
    KB_SECTION="Ground every review comment in this knowledge base:
$KB_CONTEXT"
else
    KB_SECTION="No knowledge base available. Flag this and be conservative — only raise issues visible in the diff."
fi

# Build diff (Go + Helm + YAML, skip generated files)
DIFF=$(git -C "$OTTOFLOW_REPO" show "$COMMIT_SHA" \
    -- '*.go' '*.yaml' '*.yml' 'charts/**' 'samples/**' \
    ':(exclude)api/v1alpha1/zz_generated.deepcopy.go' \
    ':(exclude)config/crd/bases/*.yaml' \
    ':(exclude)charts/*/crds/*.yaml' \
    2>/dev/null | head -c 60000)

[[ -n "$DIFF" ]] || { log "No reviewable files in this commit — skipping"; exit 0; }

PROMPT="You are a senior Go/Kubernetes engineer reviewing an OttoFlow (nirmata/ottoflow, kubebuilder) commit.

$KB_SECTION

--- DIFF ---
$DIFF
--- END DIFF ---

Output MUST be exactly one of:

APPROVED
(one-line reason)

or

NEEDS REVISION
:red_circle: CRITICAL|HIGH — file:line — description
:large_yellow_circle: MEDIUM — file:line — description
:white_check_mark: APPROVED — what's correct and why

Rules:
- Ground every finding in the KB or the diff. No speculation.
- Substantive issues only: security, correctness, race conditions, missing tests, API consistency.
- Do NOT raise style or naming issues.
- If unsure, mark LOW and move on."

REVIEW=$(hermes chat -q "$PROMPT" 2>/dev/null)
VERDICT=$(echo "$REVIEW" | head -1 | tr -d ' ')

if [[ "$VERDICT" == "APPROVED" ]]; then
    log "APPROVED — pushing $BRANCH"
    git -C "$OTTOFLOW_REPO" push origin "$BRANCH"
    slack_dm "✅ *Code review APPROVED* — \`$SHORT_SHA\` pushed to \`$BRANCH\`
> $COMMIT_MSG"
else
    log "NEEDS REVISION — writing review file"
    echo "$REVIEW" > "$REVIEW_FILE"
    git -C "$OTTOFLOW_REPO" add "$REVIEW_FILE"
    git -C "$OTTOFLOW_REPO" commit -m "review: code review for $SHORT_SHA"
    slack_dm "🔄 *Code review requested changes* for \`$SHORT_SHA\` on \`$BRANCH\`
Review: \`$(basename "$REVIEW_FILE")\` — apply-code-fixes will run automatically via post-commit hook"
fi
