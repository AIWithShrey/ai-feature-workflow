#!/usr/bin/env bash
# install.sh — Install the OttoFlow workflow tools for a developer.
#
# Usage: bash install.sh [repo-path]
# Default repo-path: ~/Nirmata/ottoflow

set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_PATH="${1:-$HOME/Nirmata/ottoflow}"

echo "=== OttoFlow Workflow Tools — Installer ==="
echo "Tools dir : $TOOLS_DIR"
echo "Repo path : $REPO_PATH"
echo ""

# Validate repo
[[ -d "$REPO_PATH/.git" ]] || {
    echo "ERROR: $REPO_PATH is not a git repo. Clone nirmata/ottoflow there first."
    exit 1
}

# Check required tools
for cmd in hermes claude gh tmux npx; do
    command -v "$cmd" &>/dev/null || echo "  WARN: $cmd not found — install it before running the workflow"
done

# Make all scripts executable
chmod +x "$TOOLS_DIR/scripts/"*.sh
chmod +x "$TOOLS_DIR/hooks/"*
echo "✓ Scripts marked executable"

# Install git hooks (symlink so updates to tools dir propagate automatically)
HOOKS_DIR="$REPO_PATH/.git/hooks"
for hook in post-commit post-merge; do
    TARGET="$HOOKS_DIR/$hook"
    if [[ -f "$TARGET" && ! -L "$TARGET" ]]; then
        echo "  Backing up existing $hook → ${TARGET}.bak"
        mv "$TARGET" "${TARGET}.bak"
    fi
    ln -sf "$TOOLS_DIR/hooks/$hook" "$TARGET"
    echo "✓ Installed hook: $hook → $TARGET"
done

# Write env stub if not present
ENV_FILE="$HOME/.hermes/ottoflow-workflow.env"
if [[ ! -f "$ENV_FILE" ]]; then
    cat > "$ENV_FILE" <<EOF
# OttoFlow workflow tools — fill in your values then source this file in your shell rc
export OTTOFLOW_REPO="$REPO_PATH"
export OTTOFLOW_TOOLS_DIR="$TOOLS_DIR"
export GITHUB_REPO="nirmata/ottoflow"

# Your Slack DM channel ID (for personal notifications from Hermes)
# Find it: in Slack, right-click your name → Copy link → ID is the last segment
export SLACK_DM_CHANNEL=""

# #dev-ottoflow channel (for PR/design notifications to the team)
export SLACK_DEV_CHANNEL=""

# GitHub handle of the PR reviewer
export GITHUB_PR_REVIEWER="patelrit"

# Reviewer's Slack user ID (for @mention in design PR notifications)
export SLACK_REVIEWER_SLACK_ID=""

# Optional: path to your Obsidian vault root (enables KB-grounded review)
export OTTOFLOW_KB_VAULT=""
EOF
    echo "✓ Created $ENV_FILE — fill in your values and add 'source $ENV_FILE' to your shell rc"
else
    echo "  $ENV_FILE already exists — skipping"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit $ENV_FILE and set your Slack channel IDs"
echo "  2. Add to ~/.zshrc or ~/.bashrc:  source $ENV_FILE"
echo "  3. Run: hermes setup  (if Hermes isn't configured yet)"
echo "  4. Run: npm install -g @anthropic-ai/claude-code  (Claude Code)"
echo "  5. Run: npm install -g gitnexus  (impact analysis)"
echo "  6. Verify: cd $REPO_PATH && git log --oneline -1  (hooks are silent)"
