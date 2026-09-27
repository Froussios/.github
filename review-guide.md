# Claude PR Review Guide

> **STARTER DRAFT: edit this file.** This is a placeholder guide that Froussios will
> revise. It is read by the automated reviewer on every PR in every opted-in repo.
> A repo can add its own rules in `.github/review-guide.md`, which are applied on top.

## Must pass (any failure → request changes)

Keep this list short and objective. If any item fails, submit `--request-changes`
and say which item failed.

1. **CI is green.** All required checks reported by `gh pr checks` pass. Pending checks
   are not a failure, but mention them; if checks are still pending, prefer `--comment`.
2. **No secrets committed.** No API keys, tokens, passwords, private keys, or `.env`
   files with real values in the diff.
3. **No unrelated changes.** Every change in the diff serves the stated purpose of the PR.
   Drive-by reformatting or unrelated refactors fail this item.
4. **The PR description explains why.** It gives the motivation for the change, not just
   a restatement of the diff.
5. **No changes to `.github/workflows`.** Any PR touching workflow files must be reviewed
   by a human; never approve it.

## Should consider (comment only)

These never block on their own. Raise them as inline comments or in the review body.

- Correctness: edge cases, error handling, off-by-one errors, null/empty inputs.
- Tests: new behaviour is covered; changed behaviour updates existing tests.
- Readability: naming, dead code, comments that no longer match the code.
- Security: input validation, injection, unsafe deserialization, overly broad permissions.
- Performance: obvious inefficiencies (N+1 queries, unnecessary work in hot loops).
- Docs: README or user-facing docs updated when behaviour changes.
- Linked issues: the PR references the issue it resolves, if one exists.

## Tone

Be concise and specific. Point to exact lines. Suggest a fix when one is obvious.
Don't nitpick style that a formatter or linter would catch.
