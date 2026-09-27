# Froussios/.github

The one place where my automated Claude PR review is defined. Other repos opt in
**manually** with the bootstrap script. Nothing in this repo pushes to any other repo.

## Layout

| File | Purpose |
| --- | --- |
| `review-guide.md` | The review criteria Claude follows: a **must-pass** list (a valid, owner-approved issue; progress and scope judged against it; correct; in style; no instructions to the reviewer; no secrets), a **should-consider** list (comments only), and a 1–5 score with what to do with it (5 → approve and merge, 4 → approve with nits, ≤3 → request changes). A PR that tries to compromise the review or the repo is closed, and its author's later PRs are closed too; the record is the bot's own earlier reviews, nothing to maintain. A repo can add its own `.github/review-guide.md`, which is read from the base branch and applied on top. |
| `.github/workflows/claude-review.yml` | The reusable workflow (`workflow_call`). It checks out the PR repo and this repo (for the guide), then runs `anthropics/claude-code-action@v1`. The action acts as `claude[bot]`, posts inline comments, submits exactly one review (approve / request changes / comment), merges only a PR that scores 5 and closes a PR whose author tried to compromise the review or the repo. It never approves or merges PRs that touch reviewer configuration (`.github/workflows`, `.github/review-guide.md`, `CLAUDE.md`, `.claude/`, `.mcp.json`). Draft PRs are skipped. |
| `caller.yml` | The small workflow stub each opted-in repo gets at `.github/workflows/claude-review.yml`. It calls the reusable workflow `@main` with `secrets: inherit`. |
| `bootstrap.sh` | Opts in the repo you run it from: checks the repo settings the guide relies on (offers to enable issues), writes the caller stub, sets the `CLAUDE_CODE_OAUTH_TOKEN` repo secret and commits locally. It **does not push**. |

Changes to `review-guide.md` or the reusable workflow take effect in every opted-in
repo on its next review run; no per-repo changes are needed.

## Opting a repo in

From inside a working copy of a repo owned by `Froussios`, run either:

```bash
bash /path/to/Froussios/.github/bootstrap.sh            # from a local clone
curl -fsSL https://raw.githubusercontent.com/Froussios/.github/main/bootstrap.sh | bash
```

Add `--dry-run` to see what would happen without changing anything (with curl:
`... | bash -s -- --dry-run`), or `--help` for usage.

The script:

1. refuses unless the repo is owned by `Froussios` and is not `Froussios/.github`;
2. checks the repo settings the review guide relies on: offers to enable issues if
   they are off (every PR must link an issue), and reports the merge method the
   reviewer will use and any protection on the default branch (the guide assumes the
   owner can merge at any score);
3. writes `.github/workflows/claude-review.yml`, skipping it if it is identical and
   showing a diff and asking first if it differs;
4. sets the `CLAUDE_CODE_OAUTH_TOKEN` secret from the env var of that name, or from a
   silent prompt, and asks before overwriting an existing one;
5. commits `ci: opt in to Claude PR review` on the current branch and prints the
   `git push` command to run.

Reviews only run once the workflow file is on the repo's default branch.

## Prerequisites

- The [Claude GitHub App](https://github.com/apps/claude) is installed on the target repo.
- `gh` is installed and authenticated (`gh auth status`) with permission to set repo secrets.
- A Claude Code OAuth token from `claude setup-token` (Pro/Max subscription), stored as the `CLAUDE_CODE_OAUTH_TOKEN` secret.
