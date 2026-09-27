# Froussios/.github

The one place where my automated Claude PR review is defined. Other repos opt in
**manually** with the bootstrap script. Nothing in this repo pushes to any other repo.

## Layout

| File | Purpose |
| --- | --- |
| `review-guide.md` | The review criteria Claude follows: a short objective **must-pass** list (any failure → request changes) and a **should-consider** list (comments only). A repo can add its own `.github/review-guide.md`, which is applied on top. |
| `.github/workflows/claude-review.yml` | The reusable workflow (`workflow_call`). It checks out the PR repo and this repo (for the guide), then runs `anthropics/claude-code-action@v1`. The action acts as `claude[bot]`, posts inline comments and submits exactly one review (approve / request changes / comment). It never approves PRs that touch `.github/workflows`. Draft PRs are skipped. |
| `caller.yml` | The small workflow stub each opted-in repo gets at `.github/workflows/claude-review.yml`. It calls the reusable workflow `@main` with `secrets: inherit`. |
| `bootstrap.sh` | Opts in the repo you run it from: writes the caller stub, sets the `ANTHROPIC_API_KEY` repo secret and commits locally. It **does not push**. |

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
2. writes `.github/workflows/claude-review.yml`, skipping it if it is identical and
   showing a diff and asking first if it differs;
3. sets the `ANTHROPIC_API_KEY` secret from the env var of that name, or from a
   silent prompt, and asks before overwriting an existing one;
4. commits `ci: opt in to Claude PR review` on the current branch and prints the
   `git push` command to run.

Reviews only run once the workflow file is on the repo's default branch.

## Prerequisites

- The [Claude GitHub App](https://github.com/apps/claude) is installed on the target repo.
- `gh` is installed and authenticated (`gh auth status`) with permission to set repo secrets.
- An Anthropic API key to store as the `ANTHROPIC_API_KEY` secret.
