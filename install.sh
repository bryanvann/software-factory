#!/bin/zsh
# Install the factory into the CURRENT macOS account.
#
# One factory per macOS account: each gets its own Claude login, its own
# LaunchAgents, its own tmux server, its own ~/.claude. Run this once per
# account, then `./install.sh --project <path>` per project you onboard.
#
# Safe to re-run: it refreshes the role, agents, skills and scripts, and never
# overwrites a project's own files, your notification topic, or boot.sh.
set -euo pipefail

PREFIX="${FACTORY_PREFIX:-factory}"
NTFY_TOPIC="${NTFY_TOPIC:-}"
PROJECT_DIR=""
PROJECT_NAME=""

usage() {
  cat <<USAGE
usage:
  ./install.sh                          install account-level pieces
  ./install.sh --project <path> [--name <name>]
                                        scaffold one project. <name> defaults
                                        to the directory name; pass it only if
                                        the project should be called something
                                        else, and use the same name in boot.sh
env:
  FACTORY_PREFIX   launchd label prefix (default: factory)
  NTFY_TOPIC       ntfy.sh topic for escalation fallback (default: reuse the
                   installed one, else generate)
USAGE
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT_DIR="${2:?--project needs a path}"; shift 2;;
    --name)    PROJECT_NAME="${2:?--name needs a value}"; shift 2;;
    -h|--help) usage;;
    *) echo "unknown arg: $1"; usage;;
  esac
done

HERE="$(cd "$(dirname "$0")" && pwd)"
FACTORY="$HOME/.claude/factory"
mkdir -p "$HOME/.claude/agents" "$HOME/.claude/skills" "$FACTORY/hooks" \
         "$HOME/Library/Logs/factory" "$HOME/Library/LaunchAgents"

# Reuse the installed topic so a re-run does not orphan the phone subscription.
if [[ -z "$NTFY_TOPIC" && -s "$FACTORY/NTFY_TOPIC" ]]; then
  NTFY_TOPIC="$(cat "$FACTORY/NTFY_TOPIC")"
fi

render() {  # render <template> <dest> [<dir> <name>]
  local dir="${3:-}" name="${4:-none}"
  sed -e "s|__HOME__|$HOME|g" \
      -e "s|__PREFIX__|$PREFIX|g" \
      -e "s|__PROJECT__|$name|g" \
      -e "s|__PROJECT_DIR__|$dir|g" \
      -e "s|__NTFY_TOPIC__|$NTFY_TOPIC|g" \
      "$1" > "$2"
}

keep() {  # keep <src> <dest>: copy only if the project does not have it yet
  if [[ -e "$2" ]]; then echo "  kept    ${2#$PROJECT_DIR/}"
  else mkdir -p "$(dirname "$2")"; cp "$1" "$2"; echo "  wrote   ${2#$PROJECT_DIR/}"; fi
}

# ---------- account level ----------
if [[ -z "$PROJECT_DIR" ]]; then
  echo "==> installing account-level factory"

  cp "$HERE/roles/foreman.md"    "$HOME/.claude/foreman.md"
  cp "$HERE/agents/worker.md"    "$HOME/.claude/agents/worker.md"
  cp "$HERE/agents/reviewer.md"  "$HOME/.claude/agents/reviewer.md"
  cp "$HERE/agents/qa.md"        "$HOME/.claude/agents/qa.md"
  cp "$HERE/scripts/patrol.sh"   "$FACTORY/patrol.sh"
  cp "$HERE"/scripts/hooks/*     "$FACTORY/hooks/"

  # The onboarding skill is account-level: it has to be available in a repo
  # before that repo has any factory files of its own.
  mkdir -p "$HOME/.claude/skills/onboard-repo"
  cp "$HERE/.claude/skills/onboard-repo/SKILL.md" "$HOME/.claude/skills/onboard-repo/SKILL.md"

  # The optional GitHub Action reviewer. Never installed into a project by
  # this script; the onboarding skill copies it only if the operator asks.
  mkdir -p "$FACTORY/examples"
  cp "$HERE/examples/claude-review.yml" "$FACTORY/examples/claude-review.yml"

  # boot.sh holds your PROJECTS list. Never clobber it.
  if [[ -e "$FACTORY/boot.sh" ]]; then
    cp "$HERE/scripts/boot.sh" "$FACTORY/boot.sh.new"
    echo "==> kept your boot.sh; the new version is boot.sh.new — merge by hand if it changed"
  else
    cp "$HERE/scripts/boot.sh" "$FACTORY/boot.sh"
  fi

  # Escalation channel. ntfy topics are unauthenticated: anyone who knows the
  # name can read and post, so use a random one and treat it as a secret.
  if [[ -z "$NTFY_TOPIC" ]]; then
    NTFY_TOPIC="factory-$(openssl rand -hex 6)"
    echo "==> generated ntfy topic: $NTFY_TOPIC"
    echo "    subscribe on your phone: https://ntfy.sh/$NTFY_TOPIC"
  fi
  echo "$NTFY_TOPIC" > "$FACTORY/NTFY_TOPIC"
  sed -i '' "s|__NTFY_TOPIC__|$NTFY_TOPIC|g" \
    "$FACTORY/patrol.sh" "$FACTORY/hooks/escalate.sh"
  chmod +x "$FACTORY"/*.sh "$FACTORY/hooks/"*

  render "$HERE/launchd/factory-boot.plist.template" \
         "$HOME/Library/LaunchAgents/com.$PREFIX.factory-boot.plist"

  # Every session started on this machine should be reachable from the Claude
  # app, the Foreman above all: it is started by boot.sh, not from the phone.
  # Merge the one key into the account settings, leaving the rest untouched.
  python3 - "$HOME/.claude/settings.json" <<'PY'
import json, os, shutil, sys
p = sys.argv[1]
try:
    s = json.load(open(p)) if os.path.exists(p) else {}
except Exception as e:
    print(f"==> could not parse {p} ({e}); add \"remoteControlAtStartup\": true by hand")
    sys.exit(0)
if s.get("remoteControlAtStartup") is True:
    print("==> remoteControlAtStartup already on")
else:
    if os.path.exists(p): shutil.copy(p, p + ".bak-factory")
    s["remoteControlAtStartup"] = True
    json.dump(s, open(p, "w"), indent=2); open(p, "a").write("\n")
    print("==> set remoteControlAtStartup: true in ~/.claude/settings.json (sessions already running need a restart)")
PY

  cat <<NEXT

==> account-level files installed. Remaining steps, all by hand:

  1. Machine level, once, as admin:
       sudo pmset -a sleep 0 disablesleep 1

  2. Install the ntfy app on your phone and subscribe to the topic in
     ~/.claude/factory/NTFY_TOPIC. The patrol is a shell script and cannot
     send Claude app notifications; this is how it reaches you, and it is the
     only channel that still works when Remote Control itself is down.

  3. Add your project paths to PROJECTS in ~/.claude/factory/boot.sh, then:
       launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.$PREFIX.factory-boot.plist

  4. Put a monthly reminder in your calendar to run 'claude auth login' on
     this machine. The login behind Remote Control expires about monthly; the
     patrol warns 72 h ahead, but the fix needs hands on the machine.
     See docs/OPERATIONS.md.

  Then, per project:  ./install.sh --project <path>
NEXT
  exit 0
fi

# ---------- project level ----------
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
[[ -e "$PROJECT_DIR/.git" ]] || { echo "not a git repo: $PROJECT_DIR"; exit 1; }
NAME="${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
echo "==> scaffolding project: $NAME ($PROJECT_DIR)"

mkdir -p "$PROJECT_DIR/.claude" "$PROJECT_DIR/docs/specs" "$PROJECT_DIR/.githooks"

if [[ ! -f "$PROJECT_DIR/.claude/settings.json" ]]; then
  cat > "$PROJECT_DIR/.claude/settings.json" <<JSON
{
  "env": {
    "CLAUDE_CODE_TASK_LIST_ID": "$NAME"
  }
}
JSON
  echo "  wrote   .claude/settings.json (task list id: $NAME)"
else
  echo "  kept    .claude/settings.json — make sure its env sets CLAUDE_CODE_TASK_LIST_ID"
fi

keep "$HERE/docs/specs/_TEMPLATE.md"                 "$PROJECT_DIR/docs/specs/_TEMPLATE.md"
keep "$HERE/templates/AGENTS.md"                     "$PROJECT_DIR/AGENTS.md"
keep "$HERE/templates/factory-config.md"             "$PROJECT_DIR/docs/factory-config.md"
keep "$HERE/templates/proposals.md"                  "$PROJECT_DIR/docs/proposals.md"
keep "$HERE/templates/review-checklist.md"           "$PROJECT_DIR/docs/review-checklist.md"
keep "$HERE/docs/FEEDBACK.md"                        "$PROJECT_DIR/docs/FEEDBACK.md"
keep "$HERE/.claude/skills/qa-procedure/SKILL.md"    "$PROJECT_DIR/.claude/skills/qa-procedure/SKILL.md"
keep "$HERE/scripts/hooks/pre-commit"                "$PROJECT_DIR/.githooks/pre-commit"
chmod +x "$PROJECT_DIR/.githooks/pre-commit"
git -C "$PROJECT_DIR" config core.hooksPath .githooks
echo "  set     core.hooksPath=.githooks (applies to every worktree)"

# Agent worktrees are nested in the checkout. Unignored, `git add -A` stages
# each one as a broken submodule reference.
if ! grep -qxF '.claude/worktrees/' "$PROJECT_DIR/.gitignore" 2>/dev/null; then
  echo '.claude/worktrees/' >> "$PROJECT_DIR/.gitignore"
  echo "  added   .claude/worktrees/ to .gitignore"
fi

# One Remote Control spawner per project: it is what lets the Claude app start
# a new session in this repository. And one patrol.
render "$HERE/launchd/rc-server.plist.template" \
       "$HOME/Library/LaunchAgents/com.$PREFIX.claude-rc-$NAME.plist" "$PROJECT_DIR" "$NAME"
render "$HERE/launchd/patrol.plist.template" \
       "$HOME/Library/LaunchAgents/com.$PREFIX.patrol-$NAME.plist" "$PROJECT_DIR" "$NAME"

cat <<NEXT

==> scaffolding written, uncommitted. The files above are templates: they do
    not yet know anything about this project. Remaining steps, in order:

  1. Workspace trust — per DIRECTORY, never inherited from a parent:
       cd "$PROJECT_DIR" && claude
     Accept the trust dialog.

     Not scripted on purpose. Trust gates whether this repo's local config
     executes: .claude/settings.json env and hooks, core.hooksPath scripts,
     skills, plugins. Since this factory is built on repo-local hooks, a bad
     one costs you more than most. Grant it deliberately, per project; do
     not disable trust globally.

  2. ONBOARD THE REPO. In that same session, run:
       /onboard-repo
     It analyses the repository, interviews you, and opens ONE pull request
     with a draft AGENTS.md, a draft qa-procedure skill and the factory
     config. Review it line by line and merge it. Do not start the factory
     before you have: until then the agents have no rules for this codebase.

  3. Create the labels:
       cd "$PROJECT_DIR"
       for l in triage needs-spec ready in-progress blocked; do
         gh label create "status:\$l" || true
       done
       gh label create ai-approved          --color 0E8A16 || true
       gh label create ai-changes-requested --color B60205 || true
       gh label create human-review         --color FBCA04 || true
       gh label create auto-merge           --color 1D76DB || true

  4. Remote Control consent — per MACHINE, so only the first time on a given
     Mac (persists as remoteDialogSeen in ~/.claude.json). launchd cannot
     answer it, and without it the spawner exits and respawns in a loop:
       cd "$PROJECT_DIR" && claude remote-control --spawn same-dir --name $NAME
     Answer y, then Ctrl+C.

  5. Add this project to PROJECTS in ~/.claude/factory/boot.sh:
       "$PROJECT_DIR|$NAME"

  6. Start it:
       launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.$PREFIX.claude-rc-$NAME.plist
       launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.$PREFIX.patrol-$NAME.plist
       ~/.claude/factory/boot.sh

  The reviewer is the local agent the Foreman dispatches (docs/REVIEW.md).
  It needs no GitHub secret and no workflow. An optional GitHub Action
  reviewer is in examples/claude-review.yml; it is not installed.
NEXT
