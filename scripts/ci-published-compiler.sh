#!/usr/bin/env bash
# Says whether CI can test a commit with the published build of main (the
# toolchain scripts/ci-install-toolchain.sh installs) instead of building
# the commit's compiler: only when that build's compiler is the commit's.
# The build of main publishes after main's CI passes, so a cancelled run
# leaves it behind main's newest compiler changes (pep-lang/pepper#124).
#
#   scripts/ci-published-compiler.sh [<commit>]
#
# It exits 0 when the commit the `v<VERSION>` tag is on is an ancestor of
# <commit> (default HEAD) and their tools/compiler/ is the same, and 1
# otherwise: VERSION is not published, the tag is not on <commit>'s
# history, or the list it prints of compiler files differs. Either way it
# prints why. It needs the history between the two (CI's `changes` job
# checks out every commit) and reads the tag from origin.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
commit="${1:-HEAD}"
tag="v$(tr -d '\r' < VERSION)"

built="$(git ls-remote origin "refs/tags/$tag" | cut -f1)"
if [ -z "$built" ]; then
  echo "build the commit's compiler: $tag is not published"
  exit 1
fi
# The tag moves on each publish, so a checkout can lack its newest commit.
git cat-file -e "$built^{commit}" 2>/dev/null || git fetch --no-tags --filter=blob:none origin "$built"
if ! git merge-base --is-ancestor "$built" "$commit"; then
  echo "build the commit's compiler: the published $tag (the build of $built) is not on its history"
  exit 1
fi
if ! git diff-tree --quiet "$built" "$commit" -- tools/compiler; then
  echo "build the commit's compiler: the published $tag (the build of $built) lacks these changes to tools/compiler/:"
  git diff-tree -r --name-only "$built" "$commit" -- tools/compiler
  exit 1
fi
echo "use the published $tag: the build of $built, whose tools/compiler/ is the commit's"
