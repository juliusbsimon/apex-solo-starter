#!/usr/bin/env bash
# Is the apex-solo-starter template newer than what this project last
# updated from? Prints ONE line when it is; silent when current. Never
# fails the caller: no network, no git, or any error = say nothing.
#
# The project's version is .template-version (written and committed by
# update-from-template.sh). The latest is `git ls-remote` on the template's
# main branch, cached for the day in tmp/.template-check so a busy day of
# pushes costs one network call.
# Run from pull/push (and the GUI does the same check in Python).
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 0
URL="https://github.com/juliusbsimon/apex-solo-starter.git"
CACHE="$REPO/tmp/.template-check"
TODAY="$(date +%F)"

LATEST=""
if [[ -f "$CACHE" ]] && [[ "$(cut -d' ' -f1 "$CACHE" 2>/dev/null)" == "$TODAY" ]]; then
  LATEST="$(cut -d' ' -f2 "$CACHE")"
else
  LATEST="$(timeout 5 git ls-remote "$URL" refs/heads/main 2>/dev/null | cut -f1)"
  [[ -n "$LATEST" ]] || exit 0
  mkdir -p "$REPO/tmp" && echo "$TODAY $LATEST" > "$CACHE"
fi
[[ -n "$LATEST" ]] || exit 0

MINE="$(head -1 "$REPO/.template-version" 2>/dev/null | cut -d' ' -f1)"
if [[ -z "$MINE" ]]; then
  echo "TEMPLATE: this project's template version is unknown - run 'bash scripts/update-from-template.sh' once to record it."
elif [[ "$MINE" != "$LATEST" ]]; then
  echo "TEMPLATE: update available (yours ${MINE:0:7}, latest ${LATEST:0:7}) - run 'bash scripts/update-from-template.sh' when convenient."
fi
exit 0
