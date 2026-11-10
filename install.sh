#!/bin/zsh
# Install the factory into the CURRENT macOS account.
#
# One factory per macOS account: each gets its own Claude login, its own
# LaunchAgents, its own tmux server, its own ~/.claude. Run this once per
# account, then `./install.sh --project <path>` per project you onboard.
set -euo pipefail

PREFIX="${FACTORY_PREFIX:-factory}"
NTFY_TOPIC="${NTFY_TOPIC:-}"
PROJECT_DIR=""

usage() {
  cat <<USAGE
usage:
  ./install.sh                          install account-level pieces
  ./install.sh --project <path>         onboard one project
env:
  FACTORY_PREFIX   launchd label prefix (default: factory)
  NTFY_TOPIC       ntfy.sh topic for escalation fallback (optional)
USAGE
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT_DIR="${2:?--project needs a path}"; shift 2;;
    -h|--help) usage;;
    *) echo "unknown arg: $1"; usage;;
  esac
done

HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOME/.claude/agents" "$HOME/.claude/factory/hooks" "$HOME/Library/Logs/factory"

render() {  # render <template> <dest>
  sed -e "s|__HOME__|$HOME|g" \
      -e "s|__PREFIX__|$PREFIX|g" \
      -e "s|__PROJECT__|$(basename "${PROJECT_DIR:-none}")|g" \
      -e "s|__PROJECT_DIR__|${PROJECT_DIR:-}|g" \
      -e "s|__NTFY_TOPIC__|$NTFY_TOPIC|g" \
      "$1" > "$2"
}

# ---------- account level ----------
if [[ -z "$PROJECT_DIR" ]]; then
  echo "==> installing account-level factory"

  cp "$HERE/roles/foreman.md"    "$HOME/.claude/foreman.md"
  cp "$HERE/agents/worker.md"    "$HOME/.claude/agents/worker.md"
  cp "$HERE/agents/reviewer.md"  "$HOME/.claude/agents/reviewer.md"
  cp "$HERE/agents/qa.md"        "$HOME/.claude/agents/qa.md"
  cp "$HERE/scripts/patrol.sh"  "$HOME/.claude/factory/patrol.sh"
  cp "$HERE/scripts/boot.sh"    "$HOME/.claude/factory/boot.sh"
  cp "$HERE"/scripts/hooks/*    "$HOME/.claude/factory/hooks/"

  # Escalation channel. ntfy topics are unauthenticated: anyone who knows the
  # name can read and post, so use a random one and treat it as a secret.
  if [[ -z "$NTFY_TOPIC" ]]; then
    NTFY_TOPIC="factory-$(openssl rand -hex 6)"
    echo "==> generated ntfy topic: $NTFY_TOPIC"
    echo "    subscribe on your phone: https://ntfy.sh/$NTFY_TOPIC"
  fi
  echo "$NTFY_TOPIC" > "$HOME/.claude/factory/NTFY_TOPIC"
  sed -i '' "s|__NTFY_TOPIC__|$NTFY_TOPIC|g" \
    "$HOME/.claude/factory/patrol.sh" "$HOME/.claude/factory/hooks/escalate.sh"
  chmod +x "$HOME/.claude/factory"/*.sh "$HOME/.claude/factory/hooks/"*

  render "$HERE/launchd/factory-boot.plist.template" \
         "$HOME/Library/LaunchAgents/com.$PREFIX.factory-boot.plist"

  echo "==> edit \$HOME/.claude/factory/boot.sh and add your project paths to PROJECTS"
  echo "==> then: launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.$PREFIX.factory-boot.plist"
  echo
  echo "Machine-level, run once as admin:  sudo pmset -a sleep 0 disablesleep 1"
  exit 0
fi

# ---------- project level ----------
[[ -d "$PROJECT_DIR/.git" ]] || { echo "not a git repo: $PROJECT_DIR"; exit 1; }
NAME="$(basename "$PROJECT_DIR")"
echo "==> onboarding project: $NAME ($PROJECT_DIR)"

mkdir -p "$PROJECT_DIR/.claude" "$PROJECT_DIR/docs/specs" "$PROJECT_DIR/.githooks"

if [[ ! -f "$PROJECT_DIR/.claude/settings.json" ]]; then
  cat > "$PROJECT_DIR/.claude/settings.json" <<JSON
{
  "env": {
    "CLAUDE_CODE_TASK_LIST_ID": "$NAME"
  }
}
JSON
  echo "  wrote .claude/settings.json (task list id: $NAME)"
fi

cp -n "$HERE/docs/specs/_TEMPLATE.md" "$PROJECT_DIR/docs/specs/_TEMPLATE.md" 2>/dev/null || true
cp -n "$HERE/templates/AGENTS.md"     "$PROJECT_DIR/AGENTS.md" 2>/dev/null || true
cp    "$HERE/scripts/hooks/pre-commit" "$PROJECT_DIR/.githooks/pre-commit"
chmod +x "$PROJECT_DIR/.githooks/pre-commit"
git -C "$PROJECT_DIR" config core.hooksPath .githooks
echo "  installed pre-commit gate (core.hooksPath=.githooks — applies to all worktrees)"

render "$HERE/launchd/rc-server.plist.template" \
       "$HOME/Library/LaunchAgents/com.$PREFIX.claude-rc-$NAME.plist"
render "$HERE/launchd/patrol.plist.template" \
       "$HOME/Library/LaunchAgents/com.$PREFIX.patrol-$NAME.plist"

cat <<NEXT

==> project files written. Remaining steps:

  1. Two one-time prompts, both of which launchd cannot answer. Do them now
     or the RC server will exit and be respawned by KeepAlive in a loop.

     a) Workspace trust — per DIRECTORY, never inherited from a parent:
          cd "$PROJECT_DIR" && claude
        Accept the trust dialog, then quit.

        Not scripted on purpose. Trust gates whether this repo's local config
        executes: .claude/settings.json env and hooks, core.hooksPath scripts,
        skills, plugins. Since this factory is built on repo-local hooks, a bad
        one costs you more than most. Grant it deliberately, per project; do
        not disable trust globally.

     b) Remote Control consent — per MACHINE, so only needed the first time on
        a given Mac (persists as remoteDialogSeen in ~/.claude.json):
          cd "$PROJECT_DIR" && claude remote-control --spawn same-dir --name $NAME
        Answer y, then Ctrl+C.

  2. Load the jobs:
       launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.$PREFIX.claude-rc-$NAME.plist
       launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.$PREFIX.patrol-$NAME.plist

  3. Add "$PROJECT_DIR" to PROJECTS in ~/.claude/factory/boot.sh

  4. Create the labels:
       for l in triage needs-spec ready in-progress blocked; do
         gh label create "status:\$l" || true
       done
       gh label create ai-approved          --color 0E8A16 || true
       gh label create ai-changes-requested --color B60205 || true
       gh label create auto-merge           --color 1D76DB || true

  The reviewer is the local agent the Foreman dispatches (docs/REVIEW.md,
  Path A). It needs no GitHub secret and no workflow. An optional GitHub
  Action reviewer is in examples/claude-review.yml; it is not installed.
NEXT
