# AI Feature Workflow

An AI-powered development loop that takes a GitHub issue from **idea to merged PR** with human approval gates at the right moments. No code is written until a design is reviewed and approved. No implementation ships until tests and review pass.

Works with any GitHub repository.

---

## What this does

You point it at a GitHub issue number. The tools handle the rest:

```
GitHub Issue
     │
     ▼
 [design-issue.sh]
 AI drafts a design proposal (PROPOSAL_*.md)
 Gemini adversarially reviews it — up to 3 rounds
 Edits the proposal in-place until APPROVED
     │
     ▼
 [open-design-pr.sh]
 Commits the approved proposal
 Opens a PR and notifies the team on Slack
     │
     ▼ (you approve the PR on GitHub)
     │
 [poll-approval.sh] ← runs as a cron every 30 min
 Detects GitHub PR approval
     │
     ▼
 [invoke-impl.sh]
 Claude Code reads the proposal and implements all acceptance criteria
 Runs tests, linter, build — fixes every error before committing
 Sends you a Slack DM when done
     │
     ▼
 [post-commit hook] ← fires automatically on every commit
 Gemini reviews the diff against the codebase knowledge base
 APPROVED → auto-push
 NEEDS REVISION → Claude Code applies fixes → re-review loop
     │
     ▼
 PR ready for human review
```

The only things you do manually:
1. Run one command to start: `design-issue.sh <issue-number>`
2. Review the design PR on GitHub and click Approve
3. Review the implementation PR when it lands

Everything else — design drafting, adversarial review, implementation, testing, code review — runs autonomously.

---

## How it works under the hood

| Component | Role |
|---|---|
| **[Hermes Agent](https://hermes-agent.nousresearch.com)** | Orchestrator. Runs design review, code review, and Slack notifications. Hosts the `design-docs` and `codebase-explorer` profiles. |
| **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** | Implementation agent. Reads the approved design spec and writes all the code, runs quality gates, commits. |
| **Gemini** | Adversarial reviewer. Reviews designs and code diffs. Using a different model from the implementer catches blind spots — Gemini and Claude have different reasoning patterns. |
| **Git hooks** | Glue. `post-commit` fires the right script automatically based on what changed. `post-merge` rebuilds the knowledge base when `main` is updated. |
| **Obsidian KB** *(optional)* | When configured, the codebase-explorer profile builds a knowledge graph of your repo into an Obsidian vault. Review prompts load relevant notes to ground findings in actual code, not hallucinations. |

---

## Prerequisites

You need these installed once per machine. All are available on macOS and Linux.

### 1. Hermes Agent

```bash
curl -sSL https://hermes-agent.nousresearch.com/install | sh
hermes setup
```

`hermes setup` will walk you through connecting your API keys. You need:
- **Anthropic API key** — for Claude (implementation, design drafting)
- **Google AI API key** — for Gemini (adversarial review)
- **Slack bot token** *(optional)* — for notifications

To configure Slack, add a bot to your workspace and get the bot token, then run:
```bash
hermes setup   # follow the Slack prompts
```

### 2. Claude Code

```bash
npm install -g @anthropic-ai/claude-code
claude auth login   # opens a browser for OAuth
```

If you prefer API key billing instead of OAuth:
```bash
claude auth login --console
```

### 3. GitHub CLI

```bash
brew install gh      # macOS
# or: https://cli.github.com for other platforms

gh auth login        # authenticates with your GitHub account
```

### 4. tmux

```bash
brew install tmux    # macOS
# or: sudo apt install tmux  (Ubuntu/Debian)
```

tmux is a terminal multiplexer. The workflow uses it to run Claude Code in a background session that you can monitor, without blocking your terminal.

### 5. Python 3

```bash
python3 --version    # check if already installed
# macOS: brew install python3  if not present
```

Used for lightweight JSON state management in the scripts.

---

## Setup

### Clone this repo

```bash
git clone https://github.com/AIWithShrey/ai-feature-workflow.git ~/ai-feature-workflow
```

### Run the installer

Point it at the repo you want to use the workflow on:

```bash
bash ~/ai-feature-workflow/install.sh /path/to/your/repo
```

The installer does three things:
1. Checks that all required tools are installed
2. Symlinks the `post-commit` and `post-merge` hooks into your repo's `.git/hooks/`
3. Creates `~/.hermes/workflow-tools.env` — a file where you put your personal config

### Configure your environment

Open `~/.hermes/workflow-tools.env` and fill in your values:

```bash
# Required — the workflow won't run without these
export REPO_PATH="/path/to/your/repo"        # absolute path to the repo
export GITHUB_REPO="org/repo-name"           # GitHub repo in org/name format
export WORKFLOW_TOOLS_DIR="$HOME/ai-feature-workflow/scripts"

# Slack notifications (optional — skip if you don't use Slack)
export SLACK_DM_CHANNEL="D0XXXXXXXXX"        # your personal DM channel ID*
export SLACK_TEAM_CHANNEL="C0XXXXXXXXX"      # shared team channel ID*
export SLACK_REVIEWER_ID="U0XXXXXXXXX"       # reviewer's Slack user ID for @mention*

# PR settings (optional)
export GITHUB_PR_REVIEWER="github-handle"    # who to request review from on PRs
export GITHUB_PR_ASSIGNEE="github-handle"    # who to assign PRs to

# Obsidian knowledge base (optional — enables grounded review)
export KB_VAULT="/path/to/your/obsidian/vault"
```

> **\* Finding Slack IDs:** In Slack, right-click your name (or a channel name) → "Copy link". The ID is the last segment of the URL. DM IDs start with `D`, channel IDs start with `C`, user IDs start with `U`.

Then source it in your shell so the env vars are available:

```bash
# Add this line to ~/.zshrc or ~/.bashrc, then restart your terminal
echo 'source ~/.hermes/workflow-tools.env' >> ~/.zshrc
source ~/.zshrc
```

### Set up the approval poller cron

This runs every 30 minutes in the background and fires implementation automatically when a design PR is approved on GitHub:

```bash
crontab -e
```

Add this line (replace the path with your actual path):

```
*/30 * * * * source ~/.hermes/workflow-tools.env && bash ~/ai-feature-workflow/scripts/poll-approval.sh >> /tmp/poll-approval.log 2>&1
```

### Set up Hermes profiles

The workflow uses two Hermes profiles. Ask your team lead to share the profile configs, or set them up manually:

```bash
# List your current profiles
hermes profile list

# The workflow expects these profile names:
#   design-docs       — drafts PROPOSAL_*.md from issue text
#   codebase-explorer — builds the Obsidian KB (optional)
```

Profile setup is specific to your organization's Hermes configuration. Contact your Hermes admin for the profile config files.

---

## Running the workflow

### Step 1 — Start from an issue

```bash
bash ~/ai-feature-workflow/scripts/design-issue.sh 88
```

Replace `88` with your issue number. The script:
- Fetches the issue title and body from GitHub
- Invokes the `design-docs` AI profile to draft a `PROPOSAL_*.md` in `docs/dev/`
- Runs up to 3 rounds of adversarial review, editing the proposal until Gemini approves it
- Sends you a Slack DM at each review round and a ✅ when done

This takes 5–15 minutes depending on proposal complexity.

**Already have a written proposal?** Skip directly to review:

```bash
bash ~/ai-feature-workflow/scripts/review-design.sh docs/dev/PROPOSAL_myfeature.md
```

### Step 2 — Open the design PR

```bash
bash ~/ai-feature-workflow/scripts/open-design-pr.sh \
    88 \
    docs/issue-88-myfeature \
    docs/dev/PROPOSAL_myfeature.md
```

Arguments: `<issue-number> <branch-name> <proposal-file>`

This commits the approved proposal, opens a PR on GitHub, and posts a Slack message to the team channel tagging the reviewer.

### Step 3 — Review and approve the PR

Go to GitHub and review the design proposal PR. When you're happy with it, click **Approve**.

The `poll-approval.sh` cron will detect the approval within 30 minutes and automatically launch implementation.

**Want to trigger it immediately?** Run manually after approving:

```bash
bash ~/ai-feature-workflow/scripts/invoke-impl.sh \
    88 \
    docs/issue-88-myfeature \
    docs/dev/PROPOSAL_myfeature.md \
    https://github.com/org/repo/pull/150
```

### Step 4 — Watch implementation (optional)

Claude Code runs in a tmux session. You can watch it work:

```bash
tmux capture-pane -t cc-impl-88 -p -S -40
```

Or attach directly:

```bash
tmux attach -t cc-impl-88
```

Claude Code will:
- Read the approved proposal
- Implement all acceptance criteria
- Run the repo's tests, linter, and build
- Fix every error it finds
- Commit with the message specified in the proposal

You receive a Slack DM when it finishes.

### Step 5 — Push and let the review loop run

```bash
git push origin docs/issue-88-myfeature
```

The `post-commit` hook fires automatically on every future commit to this branch:

| What you committed | What happens |
|---|---|
| `PROPOSAL_*.md` or `DESIGN_*.md` | Gemini adversarially reviews it (up to 3 rounds) |
| A `REVIEW_CODE_*.md` file | Claude Code applies the fixes and re-commits |
| Any code file (`.go`, `.py`, `.ts`, `.yaml`, …) | Gemini reviews the diff; APPROVED → auto-push; NEEDS REVISION → fix loop |
| Commit message starts with `review:`, `docs:`, `chore:` | Skipped to prevent infinite loops |

### Handling PR review feedback from teammates

When a teammate leaves review comments on your implementation PR, write a fix task and run Claude Code:

```bash
# 1. Write a fix task file describing what to change
cat > /path/to/repo/.claude/commands/fix-pr150.md << 'EOF'
# Fix PR #150 review findings

Finding 1: [describe the issue and exact fix needed]
Finding 2: [describe the issue and exact fix needed]

After fixing all issues:
- Run tests and lint — all must pass
- Commit: fix: address PR #150 review findings
- Do NOT push
EOF

# 2. Launch Claude Code
tmux new-session -d -s cc-fix -x 220 -y 50
tmux send-keys -t cc-fix "cd /path/to/repo && claude" Enter
sleep 7

# 3. Switch Claude Code to accept-edits mode (Shift+Tab three times)
tmux send-keys -t cc-fix BTab; sleep 0.4
tmux send-keys -t cc-fix BTab; sleep 0.4
tmux send-keys -t cc-fix BTab; sleep 0.5

# 4. Send the task
tmux send-keys -t cc-fix "/fix-pr150" Enter

# 5. Monitor progress
tmux capture-pane -t cc-fix -p -S -40
```

Then push when done:
```bash
git push origin docs/issue-88-myfeature
```

---

## File structure

```
ai-feature-workflow/
├── README.md                  ← you are here
├── WORKFLOW.md                ← detailed reference (all options, edge cases)
├── install.sh                 ← one-time setup script
│
├── scripts/
│   ├── config.sh              ← reads env vars, shared by all scripts
│   ├── design-issue.sh        ← Step 1: draft + review proposal
│   ├── review-design.sh       ← adversarial Gemini review loop
│   ├── open-design-pr.sh      ← Step 2: commit + open PR + Slack
│   ├── poll-approval.sh       ← Step 3: detect GH approval → trigger impl
│   ├── invoke-impl.sh         ← Step 3: Claude Code implementation via tmux
│   ├── review-code.sh         ← Gemini diff review (called by hook)
│   ├── apply-code-fixes.sh    ← Claude Code fix loop (called by hook)
│   └── explore-repo.sh        ← rebuild Obsidian KB (called by post-merge)
│
└── hooks/
    ├── post-commit            ← auto-fires review/fix on every commit
    └── post-merge             ← auto-rebuilds KB when main is updated
```

---

## Configuration reference

All configuration is via environment variables. Source them from `~/.hermes/workflow-tools.env` in your shell rc.

| Variable | Required | Description |
|---|---|---|
| `REPO_PATH` | ✅ | Absolute path to your local repo clone |
| `GITHUB_REPO` | ✅ | GitHub repository in `org/name` format |
| `WORKFLOW_TOOLS_DIR` | ✅ | Absolute path to this repo's `scripts/` directory |
| `SLACK_DM_CHANNEL` | Optional | Your personal Slack DM channel ID — for notifications sent directly to you |
| `SLACK_TEAM_CHANNEL` | Optional | Team/project Slack channel ID — for PR and design notifications |
| `SLACK_REVIEWER_ID` | Optional | Reviewer's Slack user ID — @mentioned in design PR posts |
| `GITHUB_PR_REVIEWER` | Optional | GitHub handle to auto-request review from on design PRs |
| `GITHUB_PR_ASSIGNEE` | Optional | GitHub handle to auto-assign design PRs to |
| `KB_VAULT` | Optional | Absolute path to your Obsidian vault root — enables KB-grounded review |

Without Slack variables set, notifications are silently skipped. Without `KB_VAULT`, review still works but without codebase grounding (higher chance of false-positive findings).

---

## Troubleshooting

**The post-commit hook does nothing**

The hook fails open (never blocks commits) and stays silent when not configured. Check:
```bash
echo $WORKFLOW_TOOLS_DIR           # must be set and point to scripts/
ls -la /path/to/repo/.git/hooks/post-commit  # should be a symlink
```

If `WORKFLOW_TOOLS_DIR` is empty, you didn't source the env file. Add `source ~/.hermes/workflow-tools.env` to your shell rc.

**`claude` exits with 401**

This happens when Claude Code is launched inside a Hermes terminal session — Hermes sets `ANTHROPIC_AUTH_TOKEN` in the environment, which Claude Code sends as a bearer token and gets rejected. The `invoke-impl.sh` and `apply-code-fixes.sh` scripts already work around this by using tmux interactive mode. If you're running `claude` manually inside Hermes, open a separate terminal outside of Hermes instead.

**Design review loops forever without APPROVED**

Increase the iteration limit:
```bash
bash ~/ai-feature-workflow/scripts/review-design.sh PROPOSAL.md 6
```

Also check that your proposal has explicit acceptance criteria — Gemini needs concrete criteria to evaluate against, not just prose description.

**`gh` can't open a PR** (`GraphQL: Head sha can't be blank`)

The branch hasn't been pushed yet. Push it first:
```bash
git push origin <branch-name>
```
Then run `open-design-pr.sh` again.

**Poll-approval cron isn't firing**

Check the cron log:
```bash
cat /tmp/poll-approval.log
```

Common causes: env file isn't sourced in cron context (verify the `source` line is in the crontab entry), or `gh` auth isn't available in the cron environment (`gh auth status`).

**Claude Code is stuck mid-implementation**

Attach to the tmux session to see what's happening:
```bash
tmux attach -t cc-impl-<issue-number>
```

If it's waiting on a prompt you can't answer, you can type your response directly in the attached session. To detach without killing it: `Ctrl+B` then `D`.

---

## FAQ

**Does this work with private repos?**  
Yes. `gh` and Claude Code both support private repos as long as you have the right access tokens.

**What languages does this support?**  
The implementation agent (Claude Code) supports any language. The code review prompt currently pattern-matches `.go`, `.ts`, `.py`, `.yaml`, `.yml`, `.json` for the diff — edit `review-code.sh` to adjust for your stack.

**Can I use this without Slack?**  
Yes. Leave `SLACK_DM_CHANNEL` and `SLACK_TEAM_CHANNEL` empty. All Slack calls are silently skipped.

**Can I use this without Obsidian?**  
Yes. Leave `KB_VAULT` empty. Review still runs — it just won't be grounded by codebase-specific knowledge, so expect a slightly higher false-positive rate in review findings.

**How do I use this on a team?**  
Each developer runs `install.sh` on their machine and fills in their own `~/.hermes/workflow-tools.env`. The hooks and scripts are shared (from this repo) but config is personal — everyone uses their own API keys and Slack DM channel.

**The design-docs or codebase-explorer Hermes profile doesn't exist**  
These are Hermes profiles that need to be set up separately. They define the AI's role, system prompt, and tool access for each task. Contact your Hermes admin for the profile config files, or see the [Hermes docs](https://hermes-agent.nousresearch.com/docs) for how to create a profile.

---

## Contributing

Issues and PRs welcome. When contributing, please run through the full workflow on a test issue against a fork to verify nothing in the automation is broken.

## License

MIT
