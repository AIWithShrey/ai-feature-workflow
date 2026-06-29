#!/usr/bin/env bash
# install.sh — Set up the AI workflow tools for a repository.
#
# Usage: bash install.sh <repo-path>

set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_PATH="${1:?Usage: bash install.sh /path/to/your/repo}"

echo "=== AI Workflow Tools — Installer ==="
echo "Tools : $TOOLS_DIR"
echo "Repo  : $REPO_PATH"
echo ""

[[ -d "$REPO_PATH/.git" ]] || {
    echo "ERROR: $REPO_PATH is not a git repository."
    exit 1
}

# Check recommended tools
for cmd in hermes claude gh tmux npx python3; do
    if command -v "$cmd" &>/dev/null; then
        echo "  ✓ $cmd found"
    else
        echo "  ✗ $cmd not found — install before using this workflow"
    fi
done
echo ""

# Make scripts executable
chmod +x "$TOOLS_DIR/scripts/"*.sh "$TOOLS_DIR/hooks/"*
echo "✓ Scripts marked executable"

# Install git hooks (symlink so future updates propagate automatically)
HOOKS_DIR="$REPO_PATH/.git/hooks"
for hook in post-commit post-merge; do
    TARGET="$HOOKS_DIR/$hook"
    if [[ -f "$TARGET" && ! -L "$TARGET" ]]; then
        echo "  Backing up existing $hook to ${TARGET}.bak"
        mv "$TARGET" "${TARGET}.bak"
    fi
    ln -sf "$TOOLS_DIR/hooks/$hook" "$TARGET"
    echo "✓ Hook installed: $hook"
done

# Write per-developer env stub
ENV_FILE="$HOME/.hermes/workflow-tools.env"
if [[ ! -f "$ENV_FILE" ]]; then
    cat > "$ENV_FILE" <<EOF
# AI workflow tools — fill in your values and source this file in your shell rc
# (add to ~/.zshrc or ~/.bashrc: source ~/.hermes/workflow-tools.env)

# Required
export REPO_PATH="$REPO_PATH"
export GITHUB_REPO=""           # e.g. org/repo-name
export WORKFLOW_TOOLS_DIR="$TOOLS_DIR/scripts"

# Slack (optional — notifications are skipped if empty)
export SLACK_DM_CHANNEL=""      # your personal DM channel ID
export SLACK_TEAM_CHANNEL=""    # shared team channel ID
export SLACK_REVIEWER_ID=""     # reviewer's Slack user ID for @mention

# PR config (optional)
export GITHUB_PR_REVIEWER=""    # GitHub handle to request review from
export GITHUB_PR_ASSIGNEE=""    # GitHub handle to assign PR to

# Obsidian KB (optional — enables grounded review; skip if you don't use Obsidian)
export KB_VAULT=""              # absolute path to your Obsidian vault root
EOF
    echo "✓ Created $ENV_FILE — fill in your values"
else
    echo "  $ENV_FILE already exists — skipping (edit it manually if needed)"
fi

echo ""
echo "=== Next steps ==="
echo "  1. Edit $ENV_FILE — set GITHUB_REPO and your Slack channel IDs"
echo "  2. Add to your shell rc: source $ENV_FILE"
echo "  3. Verify Hermes is set up: hermes --version"
echo "  4. Verify Claude Code: claude --version"
echo "  5. See WORKFLOW.md for the full feature development workflow"
