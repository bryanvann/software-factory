#!/bin/zsh
# Patrol: ephemeral anti-stuck watcher. launchd fires this every 15 min; it runs
# one pass and exits. Nothing persistent, nothing to resume.
#
# Deliberately deterministic-first: the cheap shell checks run every time, and a
# model is only invoked when there is something that actually needs judgement.
# Most patrols should cost zero tokens.
set -uo pipefail

PROJECT="${1:?usage: patrol.sh <project-dir>}"
NAME="$(basename "$PROJECT")"
LOG="$HOME/Library/Logs/factory/patrol-$NAME.log"
NTFY_TOPIC="${NTFY_TOPIC:-${NTFY_TOPIC}}"
STALL_MINUTES="${STALL_MINUTES:-30}"

exec >>"$LOG" 2>&1
echo "=== patrol $(date -Iseconds) $NAME ==="
cd "$PROJECT" || { echo "FATAL: $PROJECT missing"; exit 1; }

notify() { curl -s -d "$1" "ntfy.sh/$NTFY_TOPIC" >/dev/null 2>&1 || true; }

# --- 1. Foreman liveness (free) ---
if ! tmux has-session -t "foreman-$NAME" 2>/dev/null; then
  echo "ALERT: foreman-$NAME tmux session is DOWN"
  notify "FACTORY: foreman-$NAME is down"
fi

# --- 2. Stalled in-progress tasks (free) ---
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

if [[ -z "$STALLED" ]]; then
  echo "ALL CLEAR (no stalled tasks) — no model call made"
  echo "=== patrol done $(date -Iseconds) ==="
  exit 0
fi

echo "STALLED CANDIDATES:"; echo "$STALLED"

# --- 3. Judgement, only when warranted (costs tokens) ---
# Haiku: this is a mechanical triage call run at most a few times a day.
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
