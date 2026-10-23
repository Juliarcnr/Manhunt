#!/bin/bash
# Updates the repo and runs the app in release mode on a connected device.
# Double-click in Finder to run.
set -e

# Work from the repo root, regardless of where the script is started from.
cd "$(dirname "$0")/.."

# Only re-apply a stash if we actually created one; otherwise
# `git stash apply` would apply an older, unrelated stash.
stashed=false
if [ -n "$(git status --porcelain)" ]; then
  git stash
  stashed=true
fi

git pull

if [ "$stashed" = true ]; then
  git stash apply
fi

flutter run --release --dart-define-from-file=config/maptiler.json

echo
read -n 1 -s -r -p 'Done. Press any key to close.'
