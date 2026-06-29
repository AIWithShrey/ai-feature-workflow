#!/usr/bin/env bash
# review-design.sh — Adversarially reviews a PROPOSAL_*.md up to N times.
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

# Load Obsidian knowledge base (optional — review still works without it)
KB_CONTEXT=""
load_note() {
    local file="${OTTOFLOW_KB_DIR}/$1"
    [[ -f "$file" ]] || return 0
    KB_CONTEXT+=$'\n\n'"=== KB: $1 ==="$'\n'
    KB_CONTEXT+=$(cat "$file")
    log "Loaded KB: $1"
}
if [[ -n "$OTTOFLOW_KB_DIR" && -d "$OTTOFLOW_KB_DIR" ]]; then
    load_note "_Index.md"; load_note "Architecture.md"; load_note "Types.md"; load_note "Flows.md"
    for f in "$OTTOFLOW_KB_DIR/packages/"*.md; do [[ -f "$f" ]] && load_note "packages/$(basename "$f")"; done
    [[ ${#KB_CONTEXT} -gt 40000 ]] && KB_CONTEXT="${KB_CONTEXT:0:40000}"$'\n[...truncated at 40KB...]'
fi

ITER=0
while [[ $ITER -lt $MAX_ITER ]]; do
    ITER=$((ITER + 1))
    log "Review iteration $ITER/$MAX_ITER"
    slack_dm "🔍 *Design review* iteration $ITER/$MAX_ITER for $(basename "$PROPOSAL_FILE")"

    PROPOSAL_CONTENT=$(cat "$PROPOSAL_FILE")

    PROMPT="You are a senior Go/Kubernetes engineer doing an adversarial review of an OttoFlow design proposal.

RULES:
- Ground every issue in the knowledge base or proposal. No speculation.
- SUBSTANTIVE issues only: architecture, API consistency, integration risks, missing edge cases, feasibility.
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
Exact text change needed for each issue above.
(write 'None.' if APPROVED)"

    REVIEW=$(hermes chat -q "$PROMPT" 2>/dev/null)
    VERDICT=$(echo "$REVIEW" | grep -A1 "^## Verdict" | tail -1 | tr -d ' ')

    log "Verdict: $VERDICT"

    if [[ "$VERDICT" == "APPROVED" ]]; then
        slack_dm "✅ *Design APPROVED* after $ITER iteration(s): $(basename "$PROPOSAL_FILE")"
        exit 0
    fi

    # Apply fixes to the proposal in-place
    FIX_PROMPT="The following review identified issues in a design proposal. Apply ALL fixes directly to the proposal file at $PROPOSAL_FILE. Edit the file using write_file or patch. Do not explain — just apply.

$REVIEW

Current proposal:
$PROPOSAL_CONTENT"

    hermes chat -q "$FIX_PROMPT" 2>/dev/null
    log "Fixes applied, re-reviewing..."
done

slack_dm "⚠️ *Design review exhausted* $MAX_ITER iterations without APPROVED: $(basename "$PROPOSAL_FILE")"
log "Max iterations reached without APPROVED verdict"
exit 1
