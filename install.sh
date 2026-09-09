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

  cp "$HERE/roles/foreman.md"   "$HOME/.claude/foreman.md"
  cp "$HERE/agents/worker.md"   "$HOME/.claude/agents/worker.md"
  cp "$HERE/scripts/patrol.sh"  "$HOME/.claude/factory/patrol.sh"
  cp "$HERE/scripts/boot.sh"    "$HOME/.claude/factory/boot.sh"
  cp "$HERE"/scripts/hooks/*    "$HOME/.claude/factory/hooks/"
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

mkdir -p "$PROJECT_DIR/.github/workflows"
cp -n "$HERE/.github/workflows/claude-review.yml" \
      "$PROJECT_DIR/.github/workflows/claude-review.yml" 2>/dev/null || true

render "$HERE/launchd/rc-server.plist.template" \
       "$HOME/Library/LaunchAgents/com.$PREFIX.claude-rc-$NAME.plist"
render "$HERE/launchd/patrol.plist.template" \
       "$HOME/Library/LaunchAgents/com.$PREFIX.patrol-$NAME.plist"

cat <<NEXT

==> project files written. Remaining steps:

  1. Accept Remote Control consent ONCE (it persists to ~/.claude.json):
       cd "$PROJECT_DIR" && claude remote-control --spawn same-dir --name $NAME
     Answer y, then Ctrl+C. launchd cannot answer this prompt.

  2. Load the jobs:
       launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.$PREFIX.claude-rc-$NAME.plist
       launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.$PREFIX.patrol-$NAME.plist

  3. Add "$PROJECT_DIR" to PROJECTS in ~/.claude/factory/boot.sh

  4. Add ANTHROPIC_API_KEY as a GitHub repo secret, or the reviewer never runs.

  5. Create the status labels:
       for l in triage needs-spec ready in-progress blocked; do
         gh label create "status:\$l" --repo <owner>/<repo> || true
       done
NEXT
