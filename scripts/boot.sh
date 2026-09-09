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
PROJECTS=(
  "$HOME/code/<project>"
)

for PROJECT in "${PROJECTS[@]}"; do
  NAME="$(basename "$PROJECT")"
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
  tmux new-session -d -s "$SESSION" -c "$PROJECT" \
    "claude --append-system-prompt \"\$(cat $HOME/.claude/foreman.md)\" \
            --model 'claude-fable-5-1[1m]' --fallback-model opus"
done

echo "=== boot done $(date -Iseconds) ==="
tmux ls 2>&1 || echo "(no tmux sessions)"
