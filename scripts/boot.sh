#!/bin/zsh
# Boot recovery: runs once at login. Recreates the tmux session and resumes each
# project's Foreman. Workers are NOT restarted here — the patrol re-dispatches
# orphaned in_progress tasks, and workers rebuild from task + spec + branch
# state rather than from memory.
set -uo pipefail

LOG="$HOME/Library/Logs/factory/boot.log"
exec >>"$LOG" 2>&1
echo "=== boot $(date -Iseconds) ==="

# One line per active project. Add a line to onboard a project.
# One entry per active project: "<path>" or "<path>|<name>".
#
# <name> is the project's identity everywhere a human sees it: the tmux session,
# the phone app's session name, the task list id, and launchd labels. It
# defaults to the directory basename. Set it explicitly only when the checkout
# directory disagrees with what the project should be called — and prefer the
# REPO name, since the Remote Control environment label is the directory
# basename and cannot be changed.
PROJECTS=(
  "$HOME/code/<project>"
)

for ENTRY in "${PROJECTS[@]}"; do
  PROJECT="${ENTRY%%|*}"
  NAME="${ENTRY##*|}"
  [[ "$NAME" == "$PROJECT" ]] && NAME="$(basename "$PROJECT")"
  SESSION="foreman-$NAME"

  if [[ ! -d "$PROJECT" ]]; then
    echo "SKIP $NAME: $PROJECT does not exist"
    continue
  fi

  if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "SKIP $NAME: $SESSION already running"
    continue
  fi

  echo "starting $SESSION in $PROJECT"
  # Deliberately a COLD start, not `claude --continue`. --continue resumes the
  # most recent session in the directory, which may be an ad-hoc session or a
  # QA session rather than the Foreman. The Foreman's durable state is the
  # on-disk task list, not its context window, so a cold start loses nothing.
  # The role is injected as a SYSTEM prompt, not as a first user message.
  # A user message can be diluted or compacted away over a multi-day session;
  # a system prompt persists for the life of the session.
  # Name the remote-control session explicitly. Without this, sessions are
  # auto-named from their first message, so the Foreman shows up in the phone
  # app as whatever you happened to say to it first — impossible to pick out.
  tmux new-session -d -s "$SESSION" -c "$PROJECT" \
    -e "CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX=$NAME-foreman" \
    "claude --append-system-prompt \"\$(cat $HOME/.claude/foreman.md)\" \
            --model 'claude-fable-5-1[1m]' --fallback-model opus"
done

echo "=== boot done $(date -Iseconds) ==="
tmux ls 2>&1 || echo "(no tmux sessions)"
