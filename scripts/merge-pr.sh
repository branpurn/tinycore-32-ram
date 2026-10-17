#!/bin/sh
# Merge a pull request without leaking a personal email into history.
#   scripts/merge-pr.sh <PR number>
# The scan must pass on the PR branch first. The merge commit is authored by
# the GitHub no-reply address (GitHub itself is the committer); the
# resulting history is scanned again.
set -eu
cd "$(dirname "$0")/.."
n=${1:?usage: scripts/merge-pr.sh <PR number>}
NOREPLY=${GIT_NOREPLY:-$(git config user.email)}
case $NOREPLY in *@users.noreply.github.com) ;; *) echo "git user.email is not a GitHub no-reply address" >&2; exit 1;; esac
scripts/scan-public.sh
gh pr merge "$n" --merge --delete-branch --author-email "$NOREPLY"
git checkout -q main && git pull -q --ff-only
scripts/scan-public.sh
git log -1 --format='merged: %H'
