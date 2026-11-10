#!/bin/zsh
# Patrol: ephemeral watcher. launchd fires this every 15 min; it runs one pass
# and exits. Nothing persistent, nothing to resume.
#
# Deliberately deterministic-first: the cheap shell checks run every time, and a
# model is only invoked when there is something that actually needs judgement.
# Most patrols should cost zero tokens.
#
#   patrol.sh <project-dir> [<name>]
#
# <name> defaults to the directory basename and must match the name boot.sh
# uses, because the Foreman's tmux session is foreman-<name>.
#
# Order of a pass:
#   1. login expiry and Remote Control spawner   (always, even when paused)
#   -  pause switch                              (may end the pass)
#   2. Foreman liveness                          (always, unless paused)
#   3. adaptive cadence gate                     (may end the pass)
#   4. subscription usage limit                  (may end the pass)
#   5. stalled in-progress tasks
#   6. pending work -> nudge the Foreman
#   7. worker cap, cadence for the next run
#   8. judgement on stalled tasks                (the only step that costs tokens)
set -uo pipefail

PROJECT="${1:?usage: patrol.sh <project-dir> [<name>]}"
NAME="${2:-$(basename "$PROJECT")}"
LOGDIR="$HOME/Library/Logs/factory"
LOG="$LOGDIR/patrol-$NAME.log"
NTFY_TOPIC="${NTFY_TOPIC:-__NTFY_TOPIC__}"
STALL_MINUTES="${STALL_MINUTES:-30}"
FOREMAN="foreman-$NAME"

mkdir -p "$LOGDIR"
exec >>"$LOG" 2>&1
echo "=== patrol $(date -Iseconds) $NAME ==="
cd "$PROJECT" || { echo "FATAL: $PROJECT missing"; exit 1; }

# Defined before anything that calls it. zsh resolves functions at call time,
# so a notify() defined further down fails as "command not found" for every
# earlier caller, and the alert is silently lost.
notify() { curl -s -d "$1" "ntfy.sh/$NTFY_TOPIC" >/dev/null 2>&1 || true; }

nudge() {  # nudge <text>: type a message into the Foreman's session
  tmux send-keys -t "$FOREMAN" "$1"
  sleep 1
  tmux send-keys -t "$FOREMAN" Enter
}

# Read one key from the project's factory config (docs/factory-config.md).
conf() {
  sed -n "s/^$1:[[:space:]]*\([^#[:space:]][^#]*\).*/\1/p" \
    "$PROJECT/docs/factory-config.md" 2>/dev/null | head -1 | sed 's/[[:space:]]*$//'
}

# --- 1. Remote Control prerequisites (free) ---
# The claude.ai login's refresh token expires roughly a month after
# `claude auth login`. When it does, every session silently loses Remote
# Control and the server-mode spawners exit in a loop. Warn 72 h ahead, at most
# once a day. The one-year `claude setup-token` token is no substitute: it
# cannot register Remote Control.
LOGIN_WARN_HOURS="${LOGIN_WARN_HOURS:-72}"
EXP_MS="$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["claudeAiOauth"]["refreshTokenExpiresAt"])' 2>/dev/null || echo "")"
if [[ "$EXP_MS" == <-> ]]; then
  LEFT_H=$(( (EXP_MS/1000 - $(date +%s)) / 3600 ))
  if (( LEFT_H < 0 )); then
    echo "ALERT: claude.ai login EXPIRED; Remote Control is down fleet-wide"
    notify "FACTORY: claude.ai login expired. Run 'claude auth login' on the Mac, then restart the Remote Control spawners."
  elif (( LEFT_H < LOGIN_WARN_HOURS )); then
    echo "WARNING: claude.ai login expires in ${LEFT_H}h"
    STAMP_EXP="$LOGDIR/patrol-$NAME.expiry-warned"
    if [[ ! -f "$STAMP_EXP" || $(( $(date +%s) - $(cat "$STAMP_EXP") )) -gt 86400 ]]; then
      notify "FACTORY: claude.ai login expires in ${LEFT_H}h. Run 'claude auth login' on the Mac before then, then restart the Remote Control spawners."
      date +%s > "$STAMP_EXP"
    fi
  else
    echo "login ok: ${LEFT_H}h until refresh-token expiry"
  fi

  # After a re-login, interactive sessions reconnect by themselves but
  # server-mode spawners do not: they must be restarted. A jump forward in the
  # expiry means a re-login happened, so remind once. Reminder only; the patrol
  # does not restart anything itself, because a restart drops the sessions the
  # spawner is hosting.
  SEEN_EXP="$LOGDIR/patrol-$NAME.login-expiry-seen"
  PREV_MS="$(cat "$SEEN_EXP" 2>/dev/null || echo "")"
  if [[ "$PREV_MS" == <-> ]] && (( EXP_MS - PREV_MS > 86400000 )); then
    echo "NOTE: login was renewed; spawners need a restart"
    notify "FACTORY: login renewed. Restart the Remote Control spawners (launchctl kickstart -k), see docs/OPERATIONS.md."
  fi
  echo "$EXP_MS" > "$SEEN_EXP"
else
  echo "note: could not read login expiry from the keychain"
fi
if ! pgrep -f "claude remote-control" >/dev/null 2>&1; then
  echo "ALERT: no claude remote-control spawner running"
  notify "FACTORY: Remote Control spawner is not running"
fi

# --- Pause switch (free) ---
# The operator can turn the patrol off for a project without touching launchd:
# the Foreman creates this file when told to pause and removes it when told to
# resume. While it exists the pass ends here: no ledger queries, no nudges, no
# model calls. Only the login check above still runs, because a lapsed login
# takes down Remote Control for every project and nothing else would say so.
PAUSED="$LOGDIR/patrol-$NAME.paused"
if [[ -e "$PAUSED" ]]; then
  echo "paused (remove $PAUSED to resume)"; exit 0
fi

# --- 2. Foreman liveness (free) ---
if ! tmux has-session -t "$FOREMAN" 2>/dev/null; then
  echo "ALERT: $FOREMAN tmux session is DOWN"
  notify "FACTORY: $FOREMAN is down"
fi

# --- 3. Adaptive cadence (free) ---
# launchd fires every ACTIVE_INTERVAL seconds. When the last full pass found
# nothing in flight and nothing actionable (everything is waiting on the
# operator), the script backs off to QUIET_INTERVAL between full passes: it
# exits here until that much time has elapsed. The first actionable finding
# flips it back to active. Nudging the Foreman costs a model call and the
# ledger queries cost API quota; this check costs nothing.
ACTIVE_INTERVAL="${ACTIVE_INTERVAL:-900}"
QUIET_INTERVAL="${QUIET_INTERVAL:-3600}"
STATE="$LOGDIR/patrol-$NAME.state"   # "active" | "quiet"
LASTRUN="$LOGDIR/patrol-$NAME.lastrun"
MODE="$(cat "$STATE" 2>/dev/null || echo active)"
if [[ "$MODE" == quiet ]]; then
  last="$(cat "$LASTRUN" 2>/dev/null || echo 0)"
  if (( $(date +%s) - last < QUIET_INTERVAL )); then
    echo "quiet mode: next full pass in $(( QUIET_INTERVAL - ($(date +%s) - last) ))s"; exit 0
  fi
fi
date +%s > "$LASTRUN"

# --- 4. Subscription usage limit (free) ---
# When the account hits its usage window, every agent dies with a 429 whose
# text names the reset time, and the Foreman itself cannot answer a nudge.
# The error lands in the session transcripts, so parse it: while a limit is
# active, do nothing (no nudges, no model calls); on the first pass after the
# reset, nudge the Foreman once to resume whatever was cut off.
#
# This reads Claude Code's transcript format and error wording, neither of
# which is a stable interface. If the detector goes quiet after an upgrade,
# check these match strings first.
LIMIT_FILE="$LOGDIR/patrol-$NAME.limit-until"
# Claude Code names a project's transcript directory after its absolute path
# with every non-alphanumeric character replaced by "-".
TRANSCRIPT_DIR="$HOME/.claude/projects/$(echo "$PROJECT" | sed 's#[^A-Za-z0-9]#-#g')"
LIMIT_UNTIL="$(python3 - "$TRANSCRIPT_DIR" <<'PYEOF'
import glob, json, os, re, sys, time, datetime as dt
d = sys.argv[1]
# Scan every transcript touched in the last 8 h. The Foreman's and its
# subagents' sidechains all live here, and the limit is account-wide, so any of
# them may carry the 429 record. Reading only the newest file races with
# subagent writes and produces false "reset" nudges.
cutoff = time.time() - 8 * 3600
files = [f for f in glob.glob(os.path.join(d, "*.jsonl")) if os.path.getmtime(f) >= cutoff]
if not files: sys.exit(0)
now = dt.datetime.now(dt.timezone.utc)
best = None
def tail_lines(path):
    with open(path, "rb") as fh:
        fh.seek(0, 2); size = fh.tell(); fh.seek(max(0, size - 2_000_000))
        return fh.read().decode("utf-8", "ignore").splitlines()
for path in files:
    for raw in tail_lines(path):
        if "session limit" not in raw: continue
        try: rec = json.loads(raw)
        except Exception: continue
        t = rec.get("type")
        # (a) the Foreman itself was refused: a structured API-error record
        foreman_hit = (t == "assistant" and rec.get("isApiErrorMessage") is True
                       and str(rec.get("apiErrorStatus", "")) == "429")
        # (b) a subagent was refused: its task notification quotes the 429
        agent_hit = (t == "user" and "<task-notification>" in raw
                     and "terminated early due to an API error" in raw
                     and "rate_limit" in raw)
        if not (foreman_hit or agent_hit): continue
        m = re.search(r"resets (\d{1,2})(?::(\d{2}))?\s*(am|pm)", raw)
        ts = rec.get("timestamp")
        if not (m and ts): continue
        when = dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
        if now - when > dt.timedelta(hours=8): continue
        h, mi, ap = int(m.group(1)), int(m.group(2) or 0), m.group(3)
        h = h % 12 + (12 if ap == "pm" else 0)
        # The reset time is a wall-clock time with no date. Read it in this
        # machine's timezone, on the day the error was logged.
        local = when.astimezone()
        reset = local.replace(hour=h, minute=mi, second=0, microsecond=0)
        if reset <= local: reset += dt.timedelta(days=1)
        if best is None or reset > best: best = reset
if best and best > now:
    print(int(best.timestamp()))
PYEOF
)"
if [[ -n "$LIMIT_UNTIL" ]]; then
  if [[ ! -f "$LIMIT_FILE" ]]; then
    notify "FACTORY $NAME: usage limit hit; patrol paused until $(date -r "$LIMIT_UNTIL" '+%H:%M')"
  fi
  echo "$LIMIT_UNTIL" > "$LIMIT_FILE"
  echo "usage limit active until $(date -r "$LIMIT_UNTIL" -Iseconds); skipping pass"
  echo "=== patrol done $(date -Iseconds) ==="; exit 0
elif [[ -f "$LIMIT_FILE" ]]; then
  rm -f "$LIMIT_FILE"
  if tmux has-session -t "$FOREMAN" 2>/dev/null; then
    nudge "[patrol] The subscription usage limit has reset. Resume any workers or reviewers that were cut off by the 429, then continue normally."
    echo "nudged $FOREMAN: limit reset"
  fi
fi

# --- 5. Stalled in-progress tasks (free) ---
# Task JSON lives at ~/.claude/tasks/<list-id>/<id>.json. A task that is
# in_progress but whose file has not been touched in STALL_MINUTES is the
# signal we care about.
LIST_ID="$(python3 -c "
import json,sys
try:
    print(json.load(open('.claude/settings.json'))['env']['CLAUDE_CODE_TASK_LIST_ID'])
except Exception:
    print('')
" 2>/dev/null)"

STALLED=""
if [[ -n "$LIST_ID" && -d "$HOME/.claude/tasks/$LIST_ID" ]]; then
  STALLED="$(python3 - "$HOME/.claude/tasks/$LIST_ID" "$STALL_MINUTES" <<'PY'
import json,os,sys,time
d,mins=sys.argv[1],int(sys.argv[2])
cutoff=time.time()-mins*60
out=[]
for f in os.listdir(d):
    if not f.endswith('.json'): continue
    p=os.path.join(d,f)
    try: t=json.load(open(p))
    except Exception: continue
    if t.get('status') in ('in_progress','in-progress'):
        if os.path.getmtime(p) < cutoff:
            age=int((time.time()-os.path.getmtime(p))/60)
            out.append(f"#{t.get('id')} {t.get('subject','?')} (idle {age}m)")
print('\n'.join(out))
PY
)"
elif [[ -z "$LIST_ID" ]]; then
  echo "WARNING: no CLAUDE_CODE_TASK_LIST_ID in .claude/settings.json — the"
  echo "         Foreman and this patrol are not looking at the same ledger."
else
  # Normal before the first task is created; the directory is made on demand.
  echo "note: task list '$LIST_ID' has no tasks yet"
fi

# --- 6. Pending work the Foreman has not picked up (free) ---
# This is what makes the factory self-starting. `status:ready` is the operator's
# go-signal: an issue only reaches it after they merge its spec PR. So
# dispatching from ready is not bypassing approval — approval is what put it
# there. The first two nudges are self-limiting: acting on them changes the
# label or state, so the item stops matching on the next pass. The third is
# bounded by a timestamp.
NUDGE=""

READY="$(gh issue list --label status:ready --state open \
          --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null)"
[[ -n "$READY" ]] && NUDGE="${NUDGE}Ready to dispatch:
$READY
"

# Open IMPLEMENTATION PRs carrying neither review verdict label yet. Spec, QA
# and docs PRs are the operator's to review (merging the spec PR is the
# approval), so they are excluded by title prefix — listing them every 15
# minutes was pure noise. The prefixes are a repo convention; see CLAUDE.md.
UNREVIEWED="$(gh pr list --state open --json number,title,labels,isDraft \
  --jq '.[] | select(.isDraft==false)
           | select(.title | test("^(spec|qa|docs)[:(]") | not)
           | select([.labels[].name] | (index("ai-approved") // index("ai-changes-requested")) | not)
           | "#\(.number) \(.title)"' 2>/dev/null)"
[[ -n "$UNREVIEWED" ]] && NUDGE="${NUDGE}Awaiting review:
$UNREVIEWED
"

# Spec PRs merged since the last full pass. A merged spec is the operator's
# approval, but merging a PR does not relabel its issue: the Foreman must move
# the issue to status:ready and dispatch a worker.
STAMP="$LOGDIR/patrol-$NAME.last-merge-check"
SINCE="$(cat "$STAMP" 2>/dev/null || date -u -v-24H +%Y-%m-%dT%H:%M:%SZ)"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
MERGED_SPECS="$(gh pr list --state merged --limit 50 --json number,title,mergedAt \
  --jq '.[] | select(.mergedAt > "'"$SINCE"'")
           | select(.title | test("^spec[:(]"))
           | "#\(.number) \(.title)"' 2>/dev/null)"
[[ -n "$MERGED_SPECS" ]] && NUDGE="${NUDGE}Spec PRs merged since last check (relabel the issue status:ready and dispatch):
$MERGED_SPECS
"
echo "$NOW" > "$STAMP"

# --- 7. Worker cap and cadence (free) ---
# Parallel workers share one subscription's usage window; too many at once
# burns the whole window and stops the factory for hours. The cap comes from
# the environment, else docs/factory-config.md, else 5.
INFLIGHT="$(gh issue list --label status:in-progress --state open --json number --jq length 2>/dev/null || echo 0)"
[[ "$INFLIGHT" == <-> ]] || INFLIGHT=0
MAX_PARALLEL_WORKERS="${MAX_PARALLEL_WORKERS:-$(conf max_parallel_workers)}"
[[ "$MAX_PARALLEL_WORKERS" == <-> ]] || MAX_PARALLEL_WORKERS=5
if (( INFLIGHT > MAX_PARALLEL_WORKERS )); then
  echo "WARNING: $INFLIGHT issues in progress, cap is $MAX_PARALLEL_WORKERS"
  notify "FACTORY $NAME: $INFLIGHT workers in flight, cap $MAX_PARALLEL_WORKERS"
fi

if [[ -n "$NUDGE" ]]; then
  echo "PENDING WORK:"; echo "$NUDGE"
  if tmux has-session -t "$FOREMAN" 2>/dev/null; then
    nudge "[patrol] Pending work. Dispatch a worker for each ready issue and for each merged spec, and a reviewer for each implementation PR awaiting review. $INFLIGHT in progress now; the cap is $MAX_PARALLEL_WORKERS parallel workers, so queue the rest. If something should not be dispatched, relabel it and say why.

$NUDGE"
    echo "nudged $FOREMAN"
  else
    notify "FACTORY $NAME: pending work but no Foreman running"
  fi
fi

if [[ -n "$NUDGE" || -n "$STALLED" || "$INFLIGHT" -gt 0 ]]; then
  echo active > "$STATE"; echo "cadence: active (inflight=$INFLIGHT nudge=$([[ -n $NUDGE ]] && echo y || echo n))"
else
  echo quiet > "$STATE"; echo "cadence: quiet — nothing in flight, nothing actionable; next full pass in ${QUIET_INTERVAL}s"
fi

if [[ -z "$STALLED" ]]; then
  echo "ALL CLEAR (no stalled tasks) — no model call made"
  echo "=== patrol done $(date -Iseconds) ==="
  exit 0
fi

echo "STALLED CANDIDATES:"; echo "$STALLED"

# --- 8. Judgement, only when warranted (costs tokens) ---
# Cheapest model: this is a mechanical triage call run at most a few times a day.
VERDICT="$(claude -p --model haiku "These tasks are marked in_progress but their
task files have not been modified in over $STALL_MINUTES minutes:

$STALLED

Check each one for real activity: recent commits on its branch, an open PR, or
worktree changes. Then report ONLY tasks that are genuinely stuck, one per line,
as: <task id> — <what it was last doing> — <recommended action>.
If all of them show real recent activity, reply exactly: ALL CLEAR.
Do not fix anything. Do not write code. Report only." 2>&1)"

echo "$VERDICT"
if ! echo "$VERDICT" | grep -q 'ALL CLEAR'; then
  notify "FACTORY $NAME: stalled work — $(echo "$VERDICT" | head -c 200)"
fi

echo "=== patrol done $(date -Iseconds) ==="
