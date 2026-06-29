#!/usr/bin/env bash
# config.sh — Source this file in every script; fills in per-developer values
# from environment variables with documented defaults.
#
# Team members set these in their shell rc or .env:
#   export OTTOFLOW_REPO=/path/to/nirmata/ottoflow
#   export OTTOFLOW_KB_VAULT=/path/to/obsidian/vault  # optional
#   export SLACK_DM_CHANNEL=D0BAUA69H5Z               # your Slack DM channel ID
#   export SLACK_DEV_CHANNEL=C0AFFBS1N73              # #dev-ottoflow channel ID
#   export GITHUB_REPO=nirmata/ottoflow

# --- Required ---
OTTOFLOW_REPO="${OTTOFLOW_REPO:?Set OTTOFLOW_REPO to the repo root, e.g. /home/you/nirmata/ottoflow}"
GITHUB_REPO="${GITHUB_REPO:-nirmata/ottoflow}"

# --- Optional: Slack ---
SLACK_DM_CHANNEL="${SLACK_DM_CHANNEL:-}"       # your personal DM channel for Hermes notifications
SLACK_DEV_CHANNEL="${SLACK_DEV_CHANNEL:-}"     # team channel for PR/design notifications
SLACK_REVIEWER_SLACK_ID="${SLACK_REVIEWER_SLACK_ID:-}"  # reviewer's Slack user ID to @mention

# --- Optional: KB vault (for Gemini-grounded review) ---
OTTOFLOW_KB_VAULT="${OTTOFLOW_KB_VAULT:-}"     # path to Obsidian vault root
OTTOFLOW_KB_DIR="${OTTOFLOW_KB_VAULT:+${OTTOFLOW_KB_VAULT}/Codebases/$(basename "$OTTOFLOW_REPO")}"

# --- Helpers ---
SLACK_CMD="hermes send -t slack:${SLACK_DM_CHANNEL}"

slack_dm() {
    [[ -n "$SLACK_DM_CHANNEL" ]] && hermes send -t "slack:${SLACK_DM_CHANNEL}" "$1" || true
}

slack_dev() {
    [[ -n "$SLACK_DEV_CHANNEL" ]] && hermes send -t "slack:${SLACK_DEV_CHANNEL}" "$1" || true
}

log() { echo "[$(basename "$0")] $*" >&2; }
