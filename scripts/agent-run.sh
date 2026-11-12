#!/usr/bin/env bash
# The ONLY way the agent runs pull / push / update / migrate - and only while
# the human has agent mode on (tmp/.agent-mode, switched by the human with
# "agent mode on" in the chat or scripts/agent-mode.py in a terminal).
# Checked on EVERY call; when the mode is off or expired, nothing runs.
#
# Usage: agent-run.sh status
#        agent-run.sh pull
#        agent-run.sh push [-full] [-backup]
#        agent-run.sh update
#        agent-run.sh migrate <db/migrations/file.sql> [...] [ADMIN_CONN]
#
# Unattended means fail-safe: wherever the human scripts would ASK, this
# refuses and says why. In detail:
#   * Fixed target: the stamped dev connection and default app only. No
#     connection/app arguments, no promote, no supporting-object scripts.
#   * pull   refuses when apex/<app> has uncommitted changes (commit first).
#            Records an exact baseline: one hash per exported file.
#   * push   refuses unless apex/<app> is clean (only COMMITTED work is
#            pushed, so every push is a git commit you can read and revert)
#            and a baseline exists. Then the exact drift check: a fresh
#            export compared file by file with the baseline - any Builder
#            change since the last pull stops the push. Then push.sh
#            (validation gate, import), then a pull so the repo and the
#            baseline match the Builder again.
#   * update refuses on a dirty tree; accepts the stamped defaults.
#   * migrate only committed files under db/migrations/; the ledger and
#            compile gate of migrate.sh apply as usual.
# Every action is appended to tmp/agent-runs.log.
#
# Everything lives in main(), called on the LAST line: bash then has the
# whole file parsed before anything runs, so `update` replacing this script
# mid-run cannot corrupt it (see the note in update-from-template.sh).
set -euo pipefail

main() {
  command -v sql >/dev/null 2>&1 || PATH="$HOME/sqlcl/bin:$PATH"
  CONN="__CONN__"
  APP="__APP__"
  APP_ID="__APP_ID__"
  REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  TOKEN="$REPO/tmp/.agent-mode"
  BASELINE="$REPO/tmp/.agent-baseline-$APP"
  LOG="$REPO/tmp/agent-runs.log"
  cd "$REPO"
  mkdir -p tmp

  local action="${1:-}"; shift || true
  case "$action" in
    status)  mode_status; return 0 ;;
    pull|push|update|migrate) ;;
    *) echo "usage: agent-run.sh status | pull | push [-full] [-backup] | update | migrate <files> [ADMIN_CONN]" >&2; return 2 ;;
  esac

  require_scope "$action"
  # one agent action at a time (two imports racing would be a mess)
  exec 9>"$REPO/tmp/.agent-run.lock"
  flock -n 9 || { echo "another agent-run.sh is still running" >&2; return 1; }

  log "START $action $* (HEAD $(git rev-parse --short HEAD 2>/dev/null || echo none))"
  trap 'log "END   '"$action"' rc=$?"' EXIT
  # called plainly, NOT as `do_x || rc=$?`: inside an || list bash switches
  # set -e off for the whole function, and a failed import would carry on
  "do_$action" "$@"
}

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

# ---- the mode token ----------------------------------------------------------
token_get() { grep -oP "^$1=\K.*" "$TOKEN" 2>/dev/null | head -1 || true; }

mode_status() {
  if [[ ! -f "$TOKEN" ]]; then echo "agent mode: OFF"; return; fi
  local exp; exp="$(token_get expires)"
  if [[ -z "$exp" || "$(date +%s)" -ge "$exp" ]]; then
    echo "agent mode: EXPIRED (it is off)"; return
  fi
  echo "agent mode: ON until $(date -d "@$exp" '+%a %H:%M') - allowed: $(token_get scopes) (switched on from $(token_get by))"
  echo "target: connection $CONN, app $APP (id $APP_ID)"
}

require_scope() {
  local exp scopes
  exp="$(token_get expires)"
  if [[ ! -f "$TOKEN" || -z "$exp" || "$(date +%s)" -ge "$exp" ]]; then
    echo "REFUSED: agent mode is off or expired. '$1' is human-only right now." >&2
    echo "Ask the human to type in the chat:  agent mode on [hours] $1" >&2
    exit 3
  fi
  scopes=" $(token_get scopes) "
  if [[ "$scopes" != *" $1 "* ]]; then
    echo "REFUSED: agent mode is on, but '$1' is not allowed (allowed:$scopes)." >&2
    echo "Ask the human to type in the chat:  agent mode on [hours] <scopes including $1>" >&2
    exit 3
  fi
}

# ---- helpers -------------------------------------------------------------------
# same formula as push.sh / apex-validate.sh: "<sha256>  ./relative/path"
manifest_of() { (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum); }

apex_dirty() { [[ -n "$(git status --porcelain -- "apex/$APP")" ]]; }

record_baseline() {
  manifest_of "$REPO/apex/$APP" > "$BASELINE"
  echo "baseline recorded: $(wc -l < "$BASELINE") files (tmp/$(basename "$BASELINE"))"
}

# ---- actions -------------------------------------------------------------------
do_pull() {
  if apex_dirty; then
    echo "REFUSED: uncommitted changes under apex/$APP - the pull would erase them:" >&2
    git status --short -- "apex/$APP" >&2
    echo "Commit them first (or discard them deliberately), then pull again." >&2
    return 1
  fi
  bash "$REPO/scripts/pull.sh" < /dev/null
  record_baseline
}

do_push() {
  local opts=()
  while [[ "${1:-}" == -* ]]; do
    case "$1" in
      -full|-backup) opts+=("$1") ;;
      *) echo "REFUSED: option $1 is not available in agent mode (supporting objects and other targets stay human-only)" >&2; return 2 ;;
    esac
    shift
  done
  [[ $# -eq 0 ]] || { echo "REFUSED: agent-run.sh push takes no connection/app arguments - it pushes $APP ($APP_ID) to $CONN only" >&2; return 2; }

  if apex_dirty; then
    echo "REFUSED: apex/$APP has uncommitted changes. Agent mode pushes committed work only:" >&2
    git status --short -- "apex/$APP" >&2
    echo "Commit (feat(pNN): ... / fix: ...) and run the push again." >&2
    return 1
  fi
  if [[ ! -s "$BASELINE" ]]; then
    echo "REFUSED: no agent baseline yet. Run agent-run.sh pull first (it records what the Builder looked like)." >&2
    return 1
  fi

  # ---- exact drift check: fresh export vs. the baseline, file by file
  local stage="$REPO/tmp/agent-drift" src cur added removed
  rm -rf "$stage"; mkdir -p "$stage"
  echo "== drift check: exporting app $APP_ID to compare with the last pull (exact, file by file) =="
  sql -name "$CONN" <<SQLEOF
whenever sqlerror exit failure
whenever oserror  exit failure
apex export -applicationid $APP_ID -dir "$stage" -exptype apexlang -force
exit success
SQLEOF
  src="$(find "$stage" -mindepth 1 -maxdepth 1 -type d | head -1)"
  if [[ -z "$src" || ! -f "$src/application.apx" ]]; then
    echo "REFUSED: drift-check export incomplete - not pushing." >&2; return 1
  fi
  cur="$(manifest_of "$src")"
  if [[ "$cur" != "$(cat "$BASELINE")" ]]; then
    added="$(LC_ALL=C comm -13 <(LC_ALL=C sort "$BASELINE") <(LC_ALL=C sort <<< "$cur") | cut -c67-)"
    removed="$(LC_ALL=C comm -23 <(cut -c67- "$BASELINE" | LC_ALL=C sort) <(cut -c67- <<< "$cur" | LC_ALL=C sort))"
    echo "REFUSED: the app changed in the Builder since the last pull. Pushing would ERASE that work." >&2
    [[ -n "$added" ]]   && { echo "  changed/new in the Builder:" >&2; head -20 <<< "$added" | sed 's/^/    /' >&2; }
    [[ -n "$removed" ]] && { echo "  deleted in the Builder:" >&2;     head -20 <<< "$removed" | sed 's/^/    /' >&2; }
    echo "Next: agent-run.sh pull (your commits stay in git history), re-apply your change on top" >&2
    echo "of the Builder's version, validate, commit, push. Tell the human someone else is editing." >&2
    log "DRIFT $(wc -l <<< "$added$removed") file(s) differ"
    return 1
  fi
  echo "no Builder changes since the last pull."
  rm -rf "$stage"

  echo "== pushing commit $(git log -1 --format='%h %s') =="
  bash "$REPO/scripts/push.sh" -drift-checked "${opts[@]}" < /dev/null

  # the Builder now holds this commit: re-export so repo + baseline match it
  echo "== post-push pull (repo and baseline now match the Builder) =="
  if bash "$REPO/scripts/pull.sh" < /dev/null; then
    record_baseline
    if apex_dirty; then
      echo "NOTE: the re-export differs from what was pushed (export normalisation)."
      echo "      Review it and commit as: chore(apex): post-push pull"
    fi
  else
    rm -f "$BASELINE"
    echo "WARNING: the push succeeded but the follow-up pull failed. Baseline cleared:" >&2
    echo "         run agent-run.sh pull before the next push." >&2
    return 1
  fi
}

do_update() {
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "REFUSED: the working tree is not clean - commit first so the update's diff stands alone:" >&2
    git status --short >&2
    return 1
  fi
  # Enter for every prompt = the values already stamped in this project.
  # If any default is missing, the updater stops with "missing values".
  # (printf, not `yes | head`: yes dies of SIGPIPE and pipefail fails the run)
  printf '\n%.0s' {1..20} | bash "$REPO/scripts/update-from-template.sh"
  echo
  echo "== what the update changed =="
  git status --short
  if ! git diff --quiet -- .claude/settings.json; then
    echo
    echo "ATTENTION: .claude/settings.json changed (the agent's permission rules). Show the human this diff:"
    git --no-pager diff -- .claude/settings.json
  fi
  find . -name '*.template.new' -not -path './.git/*' | sed 's/^/MERGE BY HAND: /'
}

do_migrate() {
  [[ $# -ge 1 ]] || { echo "usage: agent-run.sh migrate <db/migrations/file.sql> [...] [ADMIN_CONN]" >&2; return 2; }
  local args=("$@") last=$(( $# - 1 )) i a rel
  # migrations include db/ sources (@@../file.sql): ALL of db/ must be
  # committed, or what actually ran would not be in git
  if [[ -n "$(git status --porcelain -- db)" ]]; then
    echo "REFUSED: db/ has uncommitted changes - commit the migration and every source it includes first:" >&2
    git status --short -- db >&2
    return 1
  fi
  for i in "${!args[@]}"; do
    a="${args[$i]}"
    if [[ -f "$a" ]]; then
      rel="$(realpath --relative-to="$REPO" "$a")"
      [[ "$rel" == db/migrations/*.sql ]] \
        || { echo "REFUSED: $a is not a .sql file under db/migrations/" >&2; return 2; }
      git ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 \
        || { echo "REFUSED: $rel is not committed - commit the migration first" >&2; return 1; }
      git diff --quiet HEAD -- "$rel" \
        || { echo "REFUSED: $rel has uncommitted edits - commit them first" >&2; return 1; }
    elif [[ $i -eq $last ]]; then
      [[ "$a" =~ ^[A-Za-z0-9_.$#@-]{1,128}$ ]] \
        || { echo "REFUSED: invalid admin connection name: $a" >&2; return 2; }
    else
      echo "no such file: $a" >&2; return 2
    fi
  done
  bash "$REPO/scripts/migrate.sh" "$@" < /dev/null
  echo
  echo "Next (agent): check dba_errors and INVALID objects with scripts/ro.sh, then commit"
  echo "db/migrations/applied-$CONN.txt with message db(...): ..."
}

main "$@"; exit $?
