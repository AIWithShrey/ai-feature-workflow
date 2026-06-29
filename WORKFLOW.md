# AI-Assisted Feature Development Workflow

An end-to-end workflow for implementing GitHub issues using [Hermes Agent](https://hermes-agent.nousresearch.com) as orchestrator, Claude Code for implementation, and Claude Sonnet 4.6 for adversarial design and code review.

Works with any GitHub repo.

---

## Prerequisites

Install once per developer machine:

```bash
# Hermes Agent (orchestrator + Slack integration)
curl -sSL https://hermes-agent.nousresearch.com/install | sh
hermes setup    # configure API keys (Anthropic)

# Claude Code (autonomous implementation agent)
npm install -g @anthropic-ai/claude-code
claude auth login

# Supporting tools
brew install gh tmux    # GitHub CLI + terminal multiplexer
```

## Setup

```bash
# Clone this tools repo somewhere on your machine
git clone <this-repo-url> ~/workflow-tools

# Run the installer, pointing it at the repo you want to use the workflow on
bash ~/workflow-tools/install.sh /path/to/your/repo
```

The installer:
- Symlinks `post-commit` and `post-merge` git hooks into your repo
- Creates `~/.hermes/workflow-tools.env` with a stub for your personal config

Fill in your values in `~/.hermes/workflow-tools.env` and source it in your shell:

```bash
# Add to ~/.zshrc or ~/.bashrc
source ~/.hermes/workflow-tools.env
```

Required env vars:

| Variable | Description |
|---|---|
| `REPO_PATH` | Absolute path to your repo |
| `GITHUB_REPO` | GitHub repo in `org/name` format |
| `WORKFLOW_TOOLS_DIR` | Path to this repo's `scripts/` directory |

Optional (skip any you don't need):

| Variable | Description |
|---|---|
| `SLACK_DM_CHANNEL` | Your personal Slack DM channel ID (for Hermes notifications) |
| `SLACK_TEAM_CHANNEL` | Team channel ID (for PR/design notifications) |
| `SLACK_REVIEWER_ID` | Reviewer's Slack user ID for @mention in PR posts |
| `GITHUB_PR_REVIEWER` | GitHub handle to request review from on design PRs |
| `GITHUB_PR_ASSIGNEE` | GitHub handle to assign PRs to |
| `KB_VAULT` | Absolute path to Obsidian vault root (enables KB-grounded review) |

### Hermes profiles

The workflow uses three Hermes profiles. Set them up once via `hermes` config:

| Profile | Role |
|---|---|
| `design-docs` | Drafts design proposals from issue text + codebase context |
| `codebase-explorer` | Builds an Obsidian knowledge graph of the repo (used for grounded review) |

---

## The Workflow

### Step 1 — Branch + Draft Design Doc

```bash
bash ~/workflow-tools/scripts/design-issue.sh <issue-number>
```

This:
1. Fetches the issue from GitHub
2. Invokes the `design-docs` Hermes profile to write a `PROPOSAL_*.md`
3. Runs up to 3 rounds of adversarial Claude review, editing the proposal in-place
4. Exits when the proposal is **APPROVED**

You receive a Slack DM at each review iteration and a ✅ when approved.

You can also write the proposal manually and then run the review step directly:

```bash
bash ~/workflow-tools/scripts/review-design.sh path/to/PROPOSAL_myfeature.md
```

### Step 2 — Open the Design PR

```bash
bash ~/workflow-tools/scripts/open-design-pr.sh \
    <issue-number> <branch> path/to/PROPOSAL_myfeature.md
```

This commits the approved proposal, opens a PR, posts a Slack notification to the team channel, and writes `~/.hermes/pending_reviews.json` so the approval poller can track it.

### Step 3 — Wait for PR Approval

Set up the approval poller as a cron (runs every 30 min):

```bash
# Add to crontab: crontab -e
*/30 * * * * source ~/.hermes/workflow-tools.env && bash ~/workflow-tools/scripts/poll-approval.sh
```

When GitHub shows `APPROVED`, the poller automatically calls `invoke-impl.sh`, which:
1. Writes a `.claude/commands/impl-issue-<N>.md` task file
2. Launches Claude Code in a tmux session in accept-edits mode
3. Waits for Claude Code to implement, test, lint, and commit
4. Sends a Slack DM when done

You can also trigger implementation manually after approving:

```bash
bash ~/workflow-tools/scripts/invoke-impl.sh \
    <issue-number> <branch> path/to/PROPOSAL.md <pr-url>
```

Monitor Claude Code while it works:

```bash
tmux capture-pane -t cc-impl-<issue-number> -p -S -40
```

### Step 4 — Push + Review Cycle

```bash
git push origin <branch>
```

The `post-commit` hook runs automatically on future commits:

| Commit contains | Hook does |
|---|---|
| `PROPOSAL_*.md` or `DESIGN_*.md` | Adversarial design review (up to 3 rounds) |
| `REVIEW_CODE_*.md` | Claude Code applies fixes + re-commits |
| Any code file | Claude diff review; APPROVED → auto-push; NEEDS REVISION → fix loop |
| Commit message starts `review:` / `fix: address code review` / `docs:` / `chore:` | Skipped (loop guard) |

When you receive manual PR review findings from teammates, write a fix task and run Claude Code:

```bash
# Write the fix task
cat > /path/to/repo/.claude/commands/fix-pr<N>.md << 'EOF'
# Fix PR #<N> review findings
<list each finding with exact fix required and quality gates>
Commit: fix: address PR #<N> review findings
Do NOT push.
EOF

# Launch Claude Code in accept-edits mode
tmux new-session -d -s cc-fix -x 220 -y 50
tmux send-keys -t cc-fix "cd /path/to/repo && claude" Enter
sleep 7
# Shift+Tab three times to reach accept-edits mode
tmux send-keys -t cc-fix BTab; sleep 0.4
tmux send-keys -t cc-fix BTab; sleep 0.4
tmux send-keys -t cc-fix BTab; sleep 0.5
tmux send-keys -t cc-fix "/fix-pr<N>" Enter

# Monitor
tmux capture-pane -t cc-fix -p -S -40
```

Then push:

```bash
git push origin <branch>
```

---

## Manual commands

```bash
# Run design review on an existing proposal (up to 5 rounds)
bash ~/workflow-tools/scripts/review-design.sh path/to/PROPOSAL.md 5

# Manually trigger code review for a specific commit
bash ~/workflow-tools/scripts/review-code.sh <commit-sha> <branch>

# Rebuild the Obsidian knowledge base
bash ~/workflow-tools/scripts/explore-repo.sh /path/to/repo

# Check approval status
cat ~/.hermes/pending_reviews.json
```

---

## How Claude Code is invoked

**Always use tmux interactive mode, never `claude -p`** when running inside a Hermes session. The `ANTHROPIC_AUTH_TOKEN` environment variable that Hermes sets causes `claude -p` to return a 401. Interactive mode uses its own OAuth flow and is unaffected.

**Write multi-line tasks to `.claude/commands/<name>.md`** and invoke as `/<name>`. Raw newlines passed through `tmux send-keys` get split into separate shell commands.

**Shift+Tab cycling:** `plan → normal → accept-edits`. Requires 3 presses. Verify the status bar shows `accept edits on` before sending the task.

---

## Troubleshooting

**Hook does nothing after a commit**
- Check `WORKFLOW_TOOLS_DIR` is set: `echo $WORKFLOW_TOOLS_DIR`
- Check the hook is installed: `ls -la /path/to/repo/.git/hooks/post-commit`

**`claude` returns 401**
- You're running inside Hermes. Use tmux interactive mode (the invoke scripts already do this).

**Design review never reaches APPROVED**
- Increase max iterations: `bash review-design.sh PROPOSAL.md 5`
- Check that the proposal has a clear "Acceptance Criteria" or equivalent section — the reviewer needs concrete criteria to evaluate against.

**KB-grounded review not working**
- Set `KB_VAULT` to your Obsidian vault root
- Run `explore-repo.sh` manually first to seed the KB
