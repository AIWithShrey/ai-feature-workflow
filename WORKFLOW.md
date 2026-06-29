# OttoFlow Feature Development Workflow

This document describes the end-to-end workflow for implementing a GitHub issue in this repo. The workflow uses [Hermes Agent](https://hermes-agent.nousresearch.com) as the orchestrator, Claude Code for implementation, and Gemini for adversarial design and code review.

---

## Prerequisites

Install once per developer machine:

```bash
# 1. Hermes Agent (orchestrator)
curl -sSL https://hermes-agent.nousresearch.com/install | sh
hermes setup          # configure API keys (Anthropic + Google for Gemini review)

# 2. Claude Code (implementation agent)
npm install -g @anthropic-ai/claude-code
claude auth login     # browser OAuth or set ANTHROPIC_API_KEY

# 3. Supporting tools
npm install -g gitnexus    # call-graph impact analysis
brew install gh tmux       # GitHub CLI + terminal multiplexer

# 4. Workflow tools (clone separately from the main repo)
git clone git@github.com:nirmata/ottoflow-workflow-tools.git ~/nirmata/ottoflow-workflow-tools
bash ~/nirmata/ottoflow-workflow-tools/install.sh ~/nirmata/ottoflow
```

The `install.sh` script will:
- Install the `post-commit` and `post-merge` git hooks in your local clone
- Create `~/.hermes/ottoflow-workflow.env` with a stub for your personal config
- Print next steps

Fill in your values in `~/.hermes/ottoflow-workflow.env` and source it in your shell rc:

```bash
# ~/.zshrc or ~/.bashrc
source ~/.hermes/ottoflow-workflow.env
```

### Hermes profiles required

The workflow uses three Hermes profiles. Ask your team lead to share the profile configs or set them up from the docs:

| Profile | Role |
|---|---|
| `design-docs` | Drafts PROPOSAL_*.md from issue text + codebase context |
| `codebase-explorer` | Builds the Obsidian knowledge graph for the repo |
| `code-reviewer` | (optional) explicit code review on demand |

---

## The Workflow

### Step 1 — Branch + Draft Design Doc

```bash
cd ~/nirmata/ottoflow
git checkout main && git pull
# Use the design-issue script — it drafts the proposal and kicks off review automatically
bash ~/nirmata/ottoflow-workflow-tools/scripts/design-issue.sh <issue-number>
```

This script:
1. Fetches the issue from GitHub
2. Invokes the `design-docs` Hermes profile to draft `docs/dev/PROPOSAL_<name>.md`
3. Immediately runs up to 3 rounds of adversarial Gemini review, editing the proposal in-place
4. Exits when the proposal is **APPROVED** (or after 3 iterations)

You will receive a Slack DM at each review iteration and a final ✅ when approved.

> You can also write the proposal manually and run:
> ```bash
> bash ~/nirmata/ottoflow-workflow-tools/scripts/review-design.sh docs/dev/PROPOSAL_<name>.md
> ```

### Step 2 — Open the Design PR

```bash
bash ~/nirmata/ottoflow-workflow-tools/scripts/open-design-pr.sh \
    <issue-number> <branch> docs/dev/PROPOSAL_<name>.md
```

This commits the approved proposal, opens a PR assigned to the reviewer (default: `patelrit`), and posts a Slack notification to the team channel. It writes `~/.hermes/pending_reviews.json` so the approval poller can track it.

### Step 3 — Wait for PR Approval

The `ottoflow-approval-poller` cron (runs every 30 min on your machine) checks for GitHub PR approval. When it sees `APPROVED`:

1. It calls `invoke-impl.sh` automatically
2. Claude Code launches in a tmux session and implements all acceptance criteria from the proposal
3. Runs `make generate manifests && go build ./... && go test ./... && make lint` — fixes all errors
4. Commits with the spec commit message
5. You receive a Slack DM when done

You can also trigger implementation manually after PR approval:

```bash
bash ~/nirmata/ottoflow-workflow-tools/scripts/invoke-impl.sh \
    <issue-number> <branch> docs/dev/PROPOSAL_<name>.md <pr-url>
```

Monitor Claude Code:

```bash
tmux capture-pane -t cc-impl-<issue-number> -p -S -40
```

### Step 4 — Push + PR Review Cycle

```bash
git push origin <branch>
```

From here, code review runs automatically via the `post-commit` hook on any future commits to non-`docs/*` branches. When the implementation commit lands:

1. **Gemini reviews the diff** grounded by the codebase knowledge base
2. On `APPROVED` → auto-pushes + Slack
3. On `NEEDS REVISION` → commits a `REVIEW_CODE_*.md` file → Claude Code applies fixes → re-review

When you receive PR review findings from teammates, write a fix task and run Claude Code manually:

```bash
cat > .claude/commands/fix-pr<N>-review.md << 'EOF'
# Fix PR #<N> review findings
... enumerate each finding, exact fix required, quality gates, commit message ...
EOF

# Launch Claude Code in accept-edits mode
tmux new-session -d -s cc-fix -x 220 -y 50
tmux send-keys -t cc-fix "cd ~/nirmata/ottoflow && claude" Enter
sleep 7
# Shift+Tab three times: plan → normal → accept-edits
tmux send-keys -t cc-fix BTab; sleep 0.4
tmux send-keys -t cc-fix BTab; sleep 0.4
tmux send-keys -t cc-fix BTab; sleep 0.5
tmux send-keys -t cc-fix "/fix-pr<N>-review" Enter
# Monitor:
tmux capture-pane -t cc-fix -p -S -40
```

Then push:

```bash
git push origin <branch>
```

---

## What runs automatically (post-commit hook)

| Commit contains | Hook does |
|---|---|
| `docs/dev/PROPOSAL_*.md` or `DESIGN_*.md` | Runs `review-design.sh` (Gemini adversarial review, up to 3 rounds) |
| `docs/dev/REVIEW_*.md` | Runs `apply-code-fixes.sh` (Claude Code fixes + re-review) |
| `*.go` / `*.yaml` / Helm on non-`docs/*` branch | Runs `review-code.sh` (Gemini KB-grounded diff review) |
| Commit message starts `review:` / `fix: address code review` / `docs:` | Skipped (loop guard) |

The `post-merge` hook (fires when `main` is updated) rebuilds the Obsidian knowledge base via `codebase-explorer`.

---

## Common manual commands

```bash
# Manually run design review on an existing proposal
bash ~/nirmata/ottoflow-workflow-tools/scripts/review-design.sh \
    docs/dev/PROPOSAL_myfeature.md 3 88 my-branch

# Manually trigger KB rebuild
bash ~/nirmata/ottoflow-workflow-tools/scripts/explore-repo.sh ~/nirmata/ottoflow

# Manually trigger code review for a commit
bash ~/nirmata/ottoflow-workflow-tools/scripts/review-code.sh <sha> <branch>

# gitnexus impact analysis before touching a symbol
cd ~/nirmata/ottoflow
npx gitnexus analyze                                          # refresh index if stale
npx gitnexus impact "Struct:api/v1alpha1/MyType" --repo ottoflow
```

---

## Key constraints

- **Never use `claude -p` inside a Hermes session** — `ANTHROPIC_AUTH_TOKEN` causes a 401. Always use tmux interactive mode.
- **Write multi-line Claude Code tasks to `.claude/commands/<name>.md`** — raw newlines in tmux send-keys split into separate shell commands. The `/<name>` slash command handles arbitrary length cleanly.
- **Always run `make generate manifests` after any `api/v1alpha1/*.go` change** — deepcopy and CRD YAMLs must be regenerated before `go build` will succeed.
- **Design PRs: assign `AIWithShrey`, reviewer `patelrit`** — always ready-for-review (not draft).

---

## Slack channel IDs (Nirmata workspace)

| Purpose | ID |
|---|---|
| Personal DM (Shreyas) | `D0BAUA69H5Z` |
| `#dev-ottoflow` | `C0AFFBS1N73` |
| `#code-review` | `C07Q61M5F7C` |

Set your own DM channel ID in `~/.hermes/ottoflow-workflow.env` (`SLACK_DM_CHANNEL`).
