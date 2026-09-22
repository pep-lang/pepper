---
name: finish-pr
description: >
  Use when the user wants a branch moved from "done coding" to "merged" —
  "finish this PR", "finish the PR", "wrap up this branch", "ship this
  branch", "push this and open a PR", "is CI green yet, merge it", "check on
  my PR" — even if they don't spell out the individual steps. Also use it to
  resume that work: invoke it again after review feedback is resolved or CI
  finishes, and it picks up from wherever things stand instead of redoing the
  push, the PR, or the review. Review findings are always reported to the
  user with proposed fixes and never resolved on the skill's own initiative,
  whatever else it was told to do.
---

# Finish PR

A feature branch goes through the same handful of stages on its way to
`main`: push it, open a PR, get it reviewed, triage feedback with the user,
wait for CI, merge. This skill carries a branch through those stages,
stopping at the one point that genuinely needs a human: when the code review
turns up findings that need triaging. A clean review plus green CI is, on its
own, enough authorization to squash-merge and delete the branch — invoking
this skill at all is the user asking it to get the branch to "merged," so
once there's nothing left for a human to decide, finish the job rather than
pausing to ask "should I merge?" again. The user can always say "hold off" or
stop the skill before this point if they want a manual look first.

That autonomy covers *merging*, and nothing else. It is never authorization
to resolve review findings yourself: those are the one thing this workflow
hands back to the user every time (Phase 5).

Read the current state before acting — don't assume you're starting from
step 1. A user invoking this after already opening a PR and getting a review
almost certainly wants you to check CI and merge, not redo the push.

## Phase 1 — Sync the branch

```bash
git status
```

Confirm the working tree is clean. If there are uncommitted changes, stop and
ask the user what to do with them — don't stash or discard anything on your
own initiative.

Check whether the branch has an upstream and, if so, whether it's behind it:

```bash
git fetch origin
git status -sb
```

- **No upstream yet** — nothing to sync; move to Phase 2.
- **Behind, not ahead** — fast-forward only: `git pull --ff-only`. This can
  never lose local work, so it doesn't need confirmation.
- **Diverged (both ahead and behind)** — something else pushed to this
  branch. Don't merge, rebase, or force-push to reconcile it yourself;
  explain the situation to the user and let them decide how to proceed.

This phase is about the branch's own remote, not about rebasing onto `main`
— that's a history-rewriting operation with its own risks and wasn't asked
for. If `main` has moved on, that'll show up later as a mergeability problem
on the PR (Phase 3), which is the right time to surface it.

## Phase 2 — Push

```bash
git push -u origin <branch>   # -u only needed the first time
```

Never force-push here. If the push is rejected because the remote has
commits this branch doesn't, that's the same "something else changed this
branch" situation as above — stop and ask rather than forcing.

If there's nothing to push (already up to date with origin), that's fine —
it just means this invocation is picking up mid-workflow. Continue anyway;
the remaining phases are each cheap to no-op through if there's nothing new.

## Phase 3 — Open or find the PR

```bash
gh pr view --json url,number,state,title,mergeable 2>/dev/null
```

- **No PR exists** — create one with `gh pr create`. Write the title and
  body from the branch's actual commits (`git log main..HEAD`, `git diff
  main...HEAD`), not a generic placeholder — a PR description should tell a
  reviewer what changed and why. This repo's PRs use a `## Summary` bullet
  list plus a `## Test plan` of the checks actually run, and its history is
  linear with squashed `(#N)` commits.
- **A PR already exists** — note its URL/number and move on. Don't create a
  second one.
- **State is `MERGED` or `CLOSED`** — stop and tell the user; this branch's
  PR has already been resolved one way or another, and re-running this
  workflow on it would be confused at best.

If `mergeable` comes back false, surface that now: it usually means `main`
has moved on and there's a real conflict to resolve, which the user needs to
handle themselves (again, not something to force through).

Note that `gh pr edit --body-file` has failed in this repo with a GraphQL
`projectCards` deprecation error; `gh api repos/{owner}/{repo}/pulls/<n> -X
PATCH -F body=@<file>` is the working fallback for setting a PR body.

## Phase 4 — Code review

This is the phase most worth getting right, and the one least worth
reinventing: delegate to the **requesting-code-review** skill (or spawn the
`reviewer` agent directly) rather than re-implementing rule-checking here,
so this skill never goes stale relative to whatever review standards the
repo grows. If a `REVIEW.md` or equivalent rules file appears in the repo
later, the review skill is what should learn to read it — not this one.

Let the review do its normal job: real bugs and correctness issues first,
then reuse/simplification/efficiency concerns. Point it at the PR's diff
(`git diff main...HEAD`) so it reviews the branch as a whole, not just the
most recent commit.

**Skip this phase if you're confident it already happened for the current
state of the PR** — e.g., you (in this same conversation) already reviewed
this exact set of commits and nothing has been pushed since. If any commits
were added or amended since the last review (including ones just pushed in
Phase 2), re-run it — a review is only as good as the diff it saw.

**Stream the review's feedback; don't make the user wait for a batch.**
A finished review is one artifact, but a long silent review feels like a stuck
one — and the first finding is often worth seeing before the last. So when
you dispatch the reviewer:

- Tell it in the task to **send you a message as soon as it confirms a
  finding** (file, line, issue, proposed fix) via `hub` send to `Main`, and
  a one-line progress note if the review runs past a few minutes. The final
  structured report is still due at the end — streamed messages are previews,
  not replacements.
- While it runs, relay each message to the user as it arrives: a confirmed
  finding goes out immediately with its proposed fix; progress notes only if
  you'd otherwise be silent for minutes. Don't batch findings in your pocket
  until the final report lands.

## Phase 5 — Findings gate the merge; a clean review doesn't

- **The review has findings** — present every one, most severe first, each
  with the fix you would propose for it, and stop there. Do not apply any of
  them until the user has said which ones to fix — not in this pass, not in
  the next one.

  **Surfacing is unconditional.** Which findings get fixed, and how, is the
  user's call — that is the entire reason this phase exists. None of the
  following authorizes fixing them yourself instead, announced or not:

  - The user already said "finish the PR", "ship it", or "merge it". That
    authorizes *merging a clean review*. It does not authorize editing code
    on their behalf, and it does not convert a findings result into a clean
    one.
  - The finding is obviously correct, or the reviewer handed over the exact
    patch to apply.
  - You wrote the code under review yourself, minutes ago, in this very
    conversation.
  - The fix is small, mechanical, or "only a comment/doc change".
  - Fixing it looks faster than asking about it.

  A finding you fix on your own initiative is a decision the user never got
  to see, and the diff they eventually approve is not the one that was
  reviewed. Present the findings with proposals; then wait.

  - Once the user picks fixes, apply exactly those, commit and push, then go
    back to **Phase 4** — the diff changed, and a review is only as good as
    the diff it saw. Re-review even when the fixes were verbatim the
    reviewer's own suggestions.
  - Never continue to Phase 6 in the same pass that surfaced findings, even
    if every finding looks minor.
- **The review is clean (no findings)** — say so, briefly, and continue
  straight into Phase 6 in the same pass. A clean review is exactly the
  condition this skill is waiting for; once it has that, there's nothing
  left for a human to weigh in on, so don't stop to ask "should I merge?" —
  that question was already answered by the review coming back clean.

### Red flags — every one of these means "surface it, don't fix it"

- "These are the reviewer's own patches, so applying them isn't a judgment
  call."
- "The user told me to merge, so they obviously want the findings cleared."
- "It's my own code from this session, so I'm just correcting myself."
- "It's only documentation / a comment / a one-liner."
- "I'll fix them and list what I fixed in the summary."

The summary is not a substitute for the user's decision. Stop, present the
findings and the proposed fixes, and let them choose.

## Phase 6 — CI and merge

Reachable automatically once Phase 5 lands on a clean review — whether
that's the first pass through, or a later one after the user decided which
findings to fix, those fixes were applied and pushed, and the re-run review
came back clean. No separate "merge it" is needed here: the clean review is
the authorization, and this phase's only remaining job is to confirm CI agrees
before actually merging. Merging is visible to everyone else who touches
this repo and isn't something to walk back casually, so still never skip a
real check or bypass branch protection to force it through — the autonomy
here is about not re-asking a question that's already been answered, not
about being less careful with the merge itself.

Check CI:

```bash
gh pr view --json statusCheckRollup,mergeable,mergeStateStatus
```

- **Still running** — don't block the conversation on a tight synchronous
  poll, but there's no human gate left to wait on either, so don't just
  report and stop and make the user re-invoke the skill: watch the check to
  completion (e.g. `gh pr checks --watch` as a background command, or an
  equivalent bounded wait). A watched check turning green only confirms the
  check-run conclusion, not `mergeStateStatus`/`mergeable` — main can move
  in the meantime — so once it resolves, loop back and re-run the "Check
  CI" command above rather than merging off the stale payload, then fall
  through to whichever case below the fresh result actually matches.
- **No checks configured at all** — this repo may have no CI workflows yet,
  in which case `statusCheckRollup` comes back empty. That's not a green
  light by omission: fall back to running the repo's own verification
  locally (see the **build** and **test** skills — `cargo test --workspace`)
  and treat that result as this phase's gate.
- **Failing** — surface which check failed and why (`gh run view` /
  `gh pr checks` for logs if needed). Don't merge, and don't try to bypass
  or skip the check — find out why it's failing, which is usually a real
  problem introduced by the branch. This is a genuine stop: report it and
  let the user decide the next step, the same as a review finding would.
- **`mergeStateStatus` is `BEHIND` (or `BLOCKED` for the same reason)** —
  branch protection is requiring this branch to be current with `main`
  before it'll allow a merge, even though CI already passed once. This
  showed up in practice: `gh pr merge` refuses with "the head branch is not
  up to date with the base branch" once something else has merged into
  `main` while this PR sat waiting on review. Bring it up to date the same
  way the PR page's own "Update branch" button would — a real merge commit
  of `main` into this branch, not a rebase, so it doesn't rewrite anything
  already pushed:

  ```bash
  gh api repos/{owner}/{repo}/pulls/<number>/update-branch -X PUT
  ```

  That merge commit needs its own CI run before anything can merge, so loop
  back to "check CI" above and wait for it — don't treat the branch's
  *previous* green run as still valid for the new commit. Like everything
  else in this phase, this doesn't need a fresh ask ("should I update the
  branch?"); it's a mechanical step on the way to the merge Phase 5 already
  authorized.
- **Green, mergeable, and up to date (`mergeStateStatus` is `CLEAN`)** —
  merge:

  ```bash
  gh pr merge <number> --squash --delete-branch
  ```

  matching this repo's convention: PR → checks green → squash merge →
  delete branch, which is what its linear `(#N)` history reflects.
  Afterward, `git fetch --prune` to clear out the now-stale remote-tracking
  ref for the deleted branch, and confirm the local repo landed back on the
  default branch.

Never skip git hooks (`--no-verify`) or force anything in this phase. If
`gh pr merge` refuses for a reason other than the stale-branch case above —
real conflicts, a required check that's actually failing, admin-only
restrictions — that's information, not an obstacle to route around;
`--admin` and `--auto` exist as escape hatches but bypass the protections
this phase exists to respect, so don't reach for them without the user
explicitly asking for that specific override.

## A note on scope

This skill is written around "the current branch," which covers the normal
case of finishing whatever you're already working on. If the user names a
different branch or a PR number, the same phases apply — just address `gh`
and `git` commands at that branch/PR instead of assuming the current
checkout, and `git checkout` it first if a local operation (like Phase 1's
sync) needs a working tree to act on.
