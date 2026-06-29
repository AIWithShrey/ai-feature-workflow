#!/usr/bin/env bash
# config.sh — Sourced by every script. Set these in your shell rc or a .env file.
#
# Required:
#   export REPO_PATH=/path/to/your/repo
#   export GITHUB_REPO=org/repo-name
#
# Optional — Slack notifications:
#   export SLACK_DM_CHANNEL=DXXXXXXXXX    # your personal DM channel ID
#   export SLACK_TEAM_CHANNEL=CXXXXXXXXX  # shared team channel ID
#   export SLACK_REVIEWER_ID=UXXXXXXXXX   # reviewer's Slack user ID for @mention
#
# Optional — KB-grounded review (Obsidian):
#   export KB_VAULT=/path/to/obsidian/vault
#
# Optional — PR config:
#   export GITHUB_PR_REVIEWER=github-handle   # who to request review from
#   export GITHUB_PR_ASSIGNEE=github-handle   # who to assign the PR to

REPO_PATH="${REPO_PATH:?Set REPO_PATH to the repo root, e.g. /home/you/code/myrepo}"
GITHUB_REPO="${GITHUB_REPO:?Set GITHUB_REPO to the GitHub repo, e.g. org/repo}"

SLACK_DM_CHANNEL="${SLACK_DM_CHANNEL:-}"
SLACK_TEAM_CHANNEL="${SLACK_TEAM_CHANNEL:-}"
SLACK_REVIEWER_ID="${SLACK_REVIEWER_ID:-}"
KB_VAULT="${KB_VAULT:-}"
KB_DIR="${KB_VAULT:+${KB_VAULT}/Codebases/$(basename "$REPO_PATH")}"
GITHUB_PR_REVIEWER="${GITHUB_PR_REVIEWER:-}"
GITHUB_PR_ASSIGNEE="${GITHUB_PR_ASSIGNEE:-}"

slack_dm() {
    [[ -n "$SLACK_DM_CHANNEL" ]] && hermes send -t "slack:${SLACK_DM_CHANNEL}" "$1" || true
}

slack_team() {
    [[ -n "$SLACK_TEAM_CHANNEL" ]] && hermes send -t "slack:${SLACK_TEAM_CHANNEL}" "$1" || true
}

log() { echo "[$(basename "$0")] $*" >&2; }
