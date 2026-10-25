#!/usr/bin/env bash
# Opens the pull request for a branch a workflow has pushed (Release's
# version bump, Stage 0's pin), or says where to open it.
#
#   scripts/ci-open-pull-request.sh <base> <branch> <title> <body-file>
#
# The repository does not let GitHub Actions open pull requests, so when
# `gh pr create` fails it writes a warning and, to the run's summary, the
# compare link that opens the pull request by hand. One a person opens runs
# CI as any pull request does. Should Actions be allowed to, it opens the
# pull request and, when <base> is DEFAULT_BRANCH, dispatches CI on
# <branch>, since a pull request opened with the workflow's token starts no
# workflows; that run does not count toward the `test` check main requires,
# so the pull request merges as an admin.
#
# It reads GH_TOKEN, GITHUB_REPOSITORY and GITHUB_STEP_SUMMARY, which a
# workflow step has, and DEFAULT_BRANCH (unset dispatches nothing).
set -euo pipefail

if [ $# -ne 4 ]; then
  echo "usage: $0 <base> <branch> <title> <body-file>" >&2
  exit 2
fi
base=$1
branch=$2
title=$3
body=$4
repo=$GITHUB_REPOSITORY

if gh pr create -R "$repo" --base "$base" --head "$branch" --title "$title" --body-file "$body"; then
  if [ "$base" = "${DEFAULT_BRANCH:-}" ]; then
    gh workflow run ci.yml -R "$repo" --ref "$branch"
    echo "::notice::opened $branch's pull request and dispatched CI on it; merge it with 'gh pr merge $branch --squash --admin' once CI passes"
  fi
else
  url="https://github.com/$repo/compare/$base...$branch?expand=1"
  echo "::warning::could not open $branch's pull request (see gh's error above; Actions may not open pull requests in $repo): open it at $url"
  printf '### %s\n\nOpen the pull request for `%s`: %s\n' "$title" "$branch" "$url" >> "$GITHUB_STEP_SUMMARY"
fi
