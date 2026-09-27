#!/usr/bin/env bash
# Opt the current repository in to the central Claude PR review.
#
# Run from inside the working copy of the repo to opt in:
#   bash /path/to/Froussios/.github/bootstrap.sh [--dry-run]
#   curl -fsSL https://raw.githubusercontent.com/Froussios/.github/main/bootstrap.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/Froussios/.github/main/bootstrap.sh | bash -s -- --dry-run
#
# It checks the repo settings the review guide relies on (offering to enable issues),
# writes the caller workflow, sets the CLAUDE_CODE_OAUTH_TOKEN repo secret and commits
# locally. It never pushes.
set -euo pipefail

OWNER="Froussios"
CENTRAL_REPO="Froussios/.github"
WORKFLOW_PATH=".github/workflows/claude-review.yml"
SECRET_NAME="CLAUDE_CODE_OAUTH_TOKEN"
COMMIT_MSG="ci: opt in to Claude PR review"

# Keep in sync with caller.yml at the root of Froussios/.github.
CALLER_YML=$(cat <<'EOF'
name: Claude PR Review
on:
  pull_request:
    types: [opened, synchronize, ready_for_review, reopened]
concurrency:
  group: claude-review-${{ github.event.pull_request.number }}
  cancel-in-progress: true
jobs:
  review:
    uses: Froussios/.github/.github/workflows/claude-review.yml@main
    secrets: inherit
EOF
)

usage() {
  cat <<EOF
Usage: bootstrap.sh [--dry-run] [--help]

Opt the current git repository (owned by ${OWNER}) in to Claude PR review:
  1. check the repo settings the review guide relies on (issues on, merge method,
     protection of the default branch); offer to enable issues if they are off
  2. write ${WORKFLOW_PATH} (calls the reusable workflow in ${CENTRAL_REPO})
  3. set the ${SECRET_NAME} repo secret (from \$${SECRET_NAME} or a silent prompt)
  4. commit the workflow on the current branch (never pushes)

Options:
  --dry-run   Print what would happen; change nothing.
  --help      Show this help.
EOF
}

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }
dry() { echo "[dry-run] would: $*"; }

# Prompts read from the terminal so they work when the script itself is piped to bash.
have_tty() { (: </dev/tty) 2>/dev/null; }

ask_yes() {
  local reply
  have_tty || die "cannot prompt (no terminal) for: $1"
  read -r -p "$1 [y/N] " reply </dev/tty
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

command -v git >/dev/null || die "git is not installed"
command -v gh >/dev/null || die "gh is not installed"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"
cd "$(git rev-parse --show-toplevel)"

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) \
  || die "could not determine the GitHub repo for this directory (is gh authenticated and is there a GitHub remote?)"
[[ "${REPO%%/*}" == "$OWNER" ]] || die "repo $REPO is not owned by $OWNER; refusing"
[[ "$REPO" != "$CENTRAL_REPO" ]] || die "this is $CENTRAL_REPO itself; refusing"

info "Opting in $REPO"
[[ $DRY_RUN -eq 1 ]] && info "Dry run: nothing will be changed"

# 1. Repo settings the review guide relies on. Read-only, except enabling issues on request.
SETTINGS=$(gh repo view "$REPO" \
  --json hasIssuesEnabled,squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed,defaultBranchRef \
  -q '.hasIssuesEnabled, .squashMergeAllowed, .mergeCommitAllowed, .rebaseMergeAllowed, .defaultBranchRef.name') \
  || die "could not read the settings of $REPO"
{ read -r HAS_ISSUES; read -r SQUASH; read -r MERGE; read -r REBASE; read -r DEFAULT_BRANCH; } <<<"$SETTINGS"

# Every PR must link an issue, so issues must be on.
if [[ "$HAS_ISSUES" != "true" ]]; then
  info "Issues are disabled on $REPO; the reviewer rejects every PR that is not linked to an issue"
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "ask before enabling issues on $REPO"
  elif ask_yes "Enable issues on $REPO?"; then
    gh repo edit "$REPO" --enable-issues
    info "Enabled issues on $REPO"
  else
    info "Leaving issues disabled; PRs will fail review until they are enabled"
  fi
fi

# The reviewer merges a 5/5 PR with the first allowed method of squash, merge, rebase.
if [[ "$SQUASH" == "true" ]]; then MERGE_METHOD=squash
elif [[ "$MERGE" == "true" ]]; then MERGE_METHOD=merge
else MERGE_METHOD=rebase; fi
info "Merge method the reviewer will use: $MERGE_METHOD (pin another in .github/review-guide.md)"

# The guide assumes the owner can merge at any score; protection on the default branch may say otherwise.
# gh api prints the error body to stdout on 404/403, so reset on failure rather than test for emptiness.
PROTECTION=$(gh api "repos/$REPO/branches/$DEFAULT_BRANCH/protection" \
  -q '"approvals=\(.required_pull_request_reviews.required_approving_review_count // 0) dismiss_stale=\(.required_pull_request_reviews.dismiss_stale_reviews // false) enforce_admins=\(.enforce_admins.enabled)"' \
  2>/dev/null) || PROTECTION=""
RULES=$(gh api "repos/$REPO/rules/branches/$DEFAULT_BRANCH" -q '[.[].type] | unique | join(" ")' 2>/dev/null) || RULES=""
if [[ -z "$PROTECTION" && -z "$RULES" ]]; then
  info "$DEFAULT_BRANCH is unprotected: reviews are advisory; anyone with write access can merge at any score"
else
  info "$DEFAULT_BRANCH is protected (classic: ${PROTECTION:-none}; ruleset rules: ${RULES:-none})"
  info "The reviewer assumes you, the owner, can merge at any score; check that these rules let you bypass"
fi

# 2. Workflow file
WRITE_WORKFLOW=1
if [[ -f "$WORKFLOW_PATH" ]]; then
  if [[ "$(cat "$WORKFLOW_PATH")" == "$CALLER_YML" ]]; then
    info "$WORKFLOW_PATH already up to date; skipping"
    WRITE_WORKFLOW=0
  else
    info "$WORKFLOW_PATH exists and differs:"
    diff -u "$WORKFLOW_PATH" <(printf '%s\n' "$CALLER_YML") || true
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "ask before overwriting $WORKFLOW_PATH"
    elif ! ask_yes "Overwrite $WORKFLOW_PATH?"; then
      info "Keeping existing $WORKFLOW_PATH"
      WRITE_WORKFLOW=0
    fi
  fi
fi
if [[ $WRITE_WORKFLOW -eq 1 ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "write $WORKFLOW_PATH"
  else
    mkdir -p "$(dirname "$WORKFLOW_PATH")"
    printf '%s\n' "$CALLER_YML" >"$WORKFLOW_PATH"
    info "Wrote $WORKFLOW_PATH"
  fi
fi

# 3. Secret
SET_SECRET=1
if gh secret list --repo "$REPO" --json name -q '.[].name' | grep -qx "$SECRET_NAME"; then
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "ask before overwriting existing secret $SECRET_NAME"
  elif ! ask_yes "Secret $SECRET_NAME already exists on $REPO. Overwrite?"; then
    info "Keeping existing secret $SECRET_NAME"
    SET_SECRET=0
  fi
fi
if [[ $SET_SECRET -eq 1 ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    if [[ -n "${!SECRET_NAME:-}" ]]; then
      dry "set secret $SECRET_NAME on $REPO from the \$$SECRET_NAME env var"
    else
      dry "prompt silently for $SECRET_NAME and set it on $REPO"
    fi
  else
    value="${!SECRET_NAME:-}"
    if [[ -z "$value" ]]; then
      have_tty || die "no terminal to prompt for $SECRET_NAME; export it and re-run"
      read -rs -p "Enter $SECRET_NAME: " value </dev/tty
      echo
    fi
    [[ -n "$value" ]] || die "$SECRET_NAME is empty"
    printf '%s' "$value" | gh secret set "$SECRET_NAME" --repo "$REPO"
    unset value
    info "Set secret $SECRET_NAME on $REPO"
  fi
fi

# 4. Commit (never push)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ $DRY_RUN -eq 1 ]]; then
  dry "git add $WORKFLOW_PATH && git commit -m \"$COMMIT_MSG\" on branch $BRANCH (if there are changes)"
else
  git add -- "$WORKFLOW_PATH"
  if git diff --cached --quiet -- "$WORKFLOW_PATH"; then
    info "No workflow changes to commit"
  else
    git commit -m "$COMMIT_MSG" -- "$WORKFLOW_PATH"
    info "Committed on $BRANCH (not pushed)"
  fi
fi

cat <<EOF

Next steps:
  [ ] Push:  git push origin $BRANCH
      The workflow must reach $DEFAULT_BRANCH before reviews run.
  [ ] Confirm the Claude GitHub App is installed on $REPO:
      https://github.com/apps/claude
  [ ] Open a test PR and check that claude[bot] posts a review.
EOF
