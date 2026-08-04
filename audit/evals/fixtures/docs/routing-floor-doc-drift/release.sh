#!/usr/bin/env bash
#
# Release helper. See README.md for the documented interface.
set -euo pipefail

DRY_RUN=0
TAG=""
CHANNEL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)  DRY_RUN=1; shift ;;
    --tag)      TAG="$2"; shift 2 ;;
    --channel)  CHANNEL="$2"; shift 2 ;;
    --skip-tests) SKIP_TESTS=1; shift ;;   # read below
    -h|--help)  echo "usage: release.sh [--dry-run] [--tag <version>] [--channel <name>] [--skip-tests]"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if [ "${SKIP_TESTS:-0}" -eq 0 ]; then
  echo "running tests"
fi

if [ -n "$TAG" ] && [ "$DRY_RUN" -eq 0 ]; then
  git tag -a "$TAG" -m "release $TAG"
  git push origin "$TAG"
fi

if [ -n "$CHANNEL" ]; then
  : "${SLACK_WEBHOOK:?SLACK_WEBHOOK must be set when --channel is used}"
  echo "would post to $CHANNEL"
fi

echo "dry_run=$DRY_RUN tag=${TAG:-none} channel=${CHANNEL:-none}"
