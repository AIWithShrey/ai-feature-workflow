#!/usr/bin/env bash
# review-design.sh — Adversarially reviews a design proposal up to N times.
# Edits the proposal in-place on NEEDS REVISION. Exits 0 on APPROVED.
#
# Usage: review-design.sh <proposal-file> [max-iterations=3] [issue-number] [branch]

set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TOOLS_DIR/config.sh"

PROPOSAL_FILE="${1:?Usage: review-design.sh <proposal-file>}"
MAX_ITER="${2:-3}"
ISSUE_NUMBER="${3:-}"
BRANCH="${4:-}"

[[ -f "$PROPOSAL_FILE" ]] || { log "Proposal not found: $PROPOSAL_FILE"; exit 1; }

# Load Obsidian knowledge base notes if vault is configured
KB_CONTEXT=""
load_note() {
    local file="${KB_DIR}/$1"
    [[ -f "$file" ]] || return 0
    KB_CONTEXT+=$'\n\n'"=== KB: $1 ==="$'\n'$(cat "$file")"
    log "Loaded KB: $1"
}
if [[ -n "$KB_DIR" && -d "$KB_DIR" ]]; then
    load_note "_Index.md"; load_note "Architecture.md"; load_note "Types.md"; load_note "Flows.md"
    for f in "$KB_DIR/packages/"*.md; do [[ -f "$f" ]] && load_note "packages/$(basename "$f")"; done
    [[ ${#KB_CONTEXT} -gt 40000 ]] && KB_CONTEXT="${KB_CONTEXT:0:40000}"$'\n[...truncated at 40KB...]'
fi

ITER=0
while [[ $ITER -lt $MAX_ITER ]]; do
    ITER=$((ITER + 1))
    log "Review iteration $ITER/$MAX_ITER"
    slack_dm "🔍 *Design review* — iteration $ITER/$MAX_ITER for \`$(basename "$PROPOSAL_FILE")\`"

    PROPOSAL_CONTENT=$(cat "$PROPOSAL_FILE")

    PROMPT="You are a senior engineer doing an adversarial review of a design proposal for the $GITHUB_REPO codebase.

RULES:
- Ground every issue in the knowledge base or the proposal itself. No speculation.
- SUBSTANTIVE issues only: architecture, API consistency, integration risks, edge cases, feasibility.
- Do NOT raise style, naming, or wording issues.
- Keep the issues list SHORT — only real blockers and high-confidence risks.

--- KNOWLEDGE BASE ---
${KB_CONTEXT:-No knowledge base available.}
--- END KNOWLEDGE BASE ---

--- PROPOSAL ---
$PROPOSAL_CONTENT
--- END PROPOSAL ---

Output MUST follow this EXACT format:

## Verdict
APPROVED

or

## Verdict
NEEDS REVISION

## Issues
- [CRITICAL|HIGH|MEDIUM] section — description
(write 'None.' if APPROVED)

## Fixes
Exact text change needed for each issue.
(write 'None.' if APPROVED)"

    REVIEW=$(hermes chat -q "$PROMPT" 2>/dev/null)
    VERDICT=$(echo "$REVIEW" | grep -A1 "^## Verdict" | tail -1 | tr -d ' ')
    log "Verdict: $VERDICT"

    if [[ "$VERDICT" == "APPROVED" ]]; then
        slack_dm "✅ *Design APPROVED* after $ITER iteration(s): \`$(basename "$PROPOSAL_FILE")\`"
        exit 0
    fi

    hermes chat -q "Apply ALL fixes below directly to the file at $PROPOSAL_FILE using write_file or patch. Do not explain — just apply.

$REVIEW

Current proposal:
$PROPOSAL_CONTENT" 2>/dev/null
    log "Fixes applied, re-reviewing..."
done

slack_dm "⚠️ *Design review exhausted* $MAX_ITER iterations without APPROVED: \`$(basename "$PROPOSAL_FILE")\`"
log "Max iterations reached without APPROVED"
exit 1
