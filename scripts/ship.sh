#!/bin/zsh
# ship.sh: the factory's ship step. The Foreman runs it right after an
# implementation PR merges, from the project root:
#
#   scripts/ship.sh [--dry-run] [--force] [--stamp-only]
#
# Merging a PR publishes nothing by itself. A git hook on push never fires for
# a merge made on GitHub, so this is a step the Foreman runs, and the patrol
# alerts when the default branch is ahead of what was last shipped.
#
# Order, deliberately:
#   0. take the ship lock; fetch; compare origin/<default> with the last stamp
#   1. production migration, if the project has one, then ASSERT it applied
#   2. per channel: clear the bundler cache, build from a clean detached
#      worktree at origin/<default>, VERIFY the artifact carries that
#      channel's configuration, then publish
#   3. record the shipped commit (the stamp); announce
#
# This file is the control flow. The project's own commands go in the ship_*
# functions marked TODO below, filled in at onboarding the same way
# .githooks/pre-commit takes the project's gates. Channel names, per-channel
# expectations and the docs-only paths come from the "Ship step" block in
# docs/factory-config.md, so the operator can change them without touching
# shell.
#
# Three failures this shape exists to prevent, each observed on a real
# factory and invisible until a device broke:
#   - a migration the ship step never applied, because the CLI read a folder
#     the clean worktree did not have (step 1 asserts; ship_prepare_worktree
#     mirrors);
#   - production bundles compiled with staging values, because the bundler
#     inlines public configuration at transform time and its cache key
#     ignores the values, so a staging build poisoned the production build
#     that followed in the same worktree (step 2 clears the cache before
#     every channel and refuses to publish an artifact that does not carry
#     what the channel expects);
#   - two Foreman sessions shipping at once, one wiping the other's worktree
#     (step 0 locks; the lock is released only from the EXIT trap).
#
# --dry-run does everything except migrate, publish and stamp.
# --force ships even when origin/<default> is what was last shipped.
# --stamp-only records origin/<default> as shipped without building: for a
#   merge the operator has decided needs no publish. Docs-only merges are
#   detected and stamped automatically (see ship_skip_paths).
set -uo pipefail

DRY=0; FORCE=0; STAMP_ONLY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --force) FORCE=1 ;;
    --stamp-only) STAMP_ONLY=1 ;;
    *) echo "unknown flag $a" >&2; exit 2 ;;
  esac
done

PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "run from inside the project checkout" >&2; exit 2; }
cd "$PROJECT" || exit 2
NAME="$(basename "$PROJECT")"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
LOGDIR="$HOME/Library/Logs/factory"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/ship-$NAME.log"
STAMP="$LOGDIR/ship-$NAME.last"          # the patrol reads this (unshipped check)
WORK="${FACTORY_WORK:-$HOME/.claude/factory/work}"; mkdir -p "$WORK"
WT="$WORK/ship-$NAME"                     # the clean detached worktree
LOCK="$WORK/ship-$NAME.lock"
NTFY_TOPIC="${NTFY_TOPIC:-$(cat "$HOME/.claude/factory/NTFY_TOPIC" 2>/dev/null || echo "")}"
LOCK_WAIT_SECONDS="${SHIP_LOCK_WAIT_SECONDS:-600}"
LOCK_STALE_MINUTES="${SHIP_LOCK_STALE_MINUTES:-30}"

exec > >(tee -a "$LOG") 2>&1
echo "=== ship $(date -Iseconds) $NAME dry=$DRY force=$FORCE stamp_only=$STAMP_ONLY ==="

notify() { [[ -n "$NTFY_TOPIC" ]] && curl -s -d "$1" "ntfy.sh/$NTFY_TOPIC" >/dev/null 2>&1 || true; }
die() { echo "!! $1"; notify "SHIP $NAME FAILED: $1"; cleanup; exit 1; }

# Read one key from the project's factory config (same format the patrol
# reads: `key: value` lines, comments after #).
conf() {
  sed -n "s/^$1:[[:space:]]*\([^#[:space:]][^#]*\).*/\1/p" \
    "$PROJECT/docs/factory-config.md" 2>/dev/null | head -1 | sed 's/[[:space:]]*$//'
}

# cleanup() removes the worktree. It runs at the START of a run too, to clear
# a worktree a crashed run left behind, so it must never touch the lock: a
# cleanup that also released the lock let two ships collide.
cleanup() {
  cd "$PROJECT" 2>/dev/null || return
  git worktree remove --force "$WT" >/dev/null 2>&1 || rm -rf "$WT"
  git worktree prune >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Project-specific commands. TODO at onboarding: fill these in from
# docs/factory-config.md "Ship step" and the project's deployment docs.
# Every function runs with the clean worktree as the current directory.
# A function the project does not need stays as it is and returns success.
# ---------------------------------------------------------------------------

# Make the clean worktree buildable: dependencies (a copy-on-write clone of
# the checkout's installed modules is instant), the untracked environment
# files the build needs for each channel, and ANY folder a CLI reads that git
# does not track. If the migration tool reads a folder other than the one
# tracked in git, mirror the tracked one into it here; that mirror is a
# documented convention of the project (docs/factory-config.md), not a
# surprise the ship step rediscovers.
ship_prepare_worktree() {
  # TODO: e.g. cp -c -R "$PROJECT/node_modules" ./node_modules
  # TODO: e.g. cp "$PROJECT/.env.production" ./.env.production
  # TODO: e.g. mkdir -p <cli-migrations-dir> && cp <tracked-migrations>/* <cli-migrations-dir>/
  return 0
}

# Print the production migrations not yet applied, one version per line.
# Empty output means none pending. Non-zero exit means "could not tell"
# (login or link missing), which aborts the ship: never publish a bundle that
# may meet the old schema.
ship_pending_migrations() {
  # TODO: e.g. <migration tool> list --remote | awk '<local present, remote empty> {print $1}'
  return 0
}

# Apply pending migrations to production.
ship_apply_migrations() {
  # TODO: e.g. <migration tool> push --remote </dev/null
  return 0
}

# Exit 0 only when the remote migration list shows <version> applied. This is
# the assertion that catches a migration tool that silently did nothing.
ship_migration_applied() {  # <version>
  # TODO: e.g. <migration tool> list --remote | grep -q "^ *$1 *| *$1"
  return 0
}

# Clear the bundler's cache. Called before EVERY channel build. The cache
# key of most bundlers ignores inlined public configuration, so a build for
# one channel poisons the next unless this runs between them.
ship_clear_cache() {
  # TODO: e.g. rm -rf ./node_modules/.cache
  return 0
}

# Build the deployable artifact for <channel> into <outdir>, with that
# channel's configuration loaded. Non-zero exit marks the channel failed.
ship_build() {  # <channel> <outdir>
  # TODO: e.g. ( source "$HOME/.claude/factory/env/$NAME.$1" && <bundler> export --output-dir "$2" )
  return 0
}

# Print the configuration the built artifact in <outdir> actually carries, in
# the form the config's ship_expect_<channel> value is written in: for
# example every backend host string found in the bundle, sorted, one per
# line. The ship step compares this with the expectation and refuses to
# publish on mismatch. Use fixed-string or anchored matching; this is the
# check that stood between staging values and production phones.
ship_artifact_config() {  # <channel> <outdir>
  # TODO: e.g. strings "$(find "$2" -name '*.bundle' | head -1)" | grep -oE 'https://[a-z0-9-]+\.<backend-domain>' | sort -u
  echo ""
}

# Publish the verified artifact in <outdir> to <channel>.
ship_publish() {  # <channel> <outdir> <message>
  # TODO: e.g. <publisher> update --channel "$1" --input-dir "$2" --skip-bundler --message "$3"
  return 0
}

# ---------------------------------------------------------------------------
# 0. Lock, fetch, compare
# ---------------------------------------------------------------------------

# One ship at a time per project. The lock is a directory holding the owner's
# pid; waiters queue for LOCK_WAIT_SECONDS, then give up; a lock whose owner
# is gone and which is older than LOCK_STALE_MINUTES is reclaimed. The lock
# is released ONLY from the EXIT trap below. Never from cleanup(), never from
# die(): both run in places where this process does not yet, or no longer,
# own the lock.
waited=0
while :; do
  if mkdir "$LOCK" 2>/dev/null; then echo $$ > "$LOCK/pid"; break; fi
  OWNER="$(cat "$LOCK/pid" 2>/dev/null || echo 0)"
  if ! kill -0 "$OWNER" 2>/dev/null && [[ -n "$(find "$LOCK" -maxdepth 0 -mmin +"$LOCK_STALE_MINUTES" 2>/dev/null)" ]]; then
    echo "reclaiming stale ship lock (pid $OWNER gone, older than ${LOCK_STALE_MINUTES}m)"; rm -rf "$LOCK"; continue
  fi
  (( waited == 0 )) && echo "another ship is running (pid $OWNER); waiting up to ${LOCK_WAIT_SECONDS}s"
  (( waited >= LOCK_WAIT_SECONDS )) && { echo "!! could not acquire ship lock after ${LOCK_WAIT_SECONDS}s"; exit 1; }
  sleep 10; waited=$(( waited + 10 ))
done
release_lock() { [[ -f "$LOCK/pid" && "$(cat "$LOCK/pid" 2>/dev/null)" == "$$" ]] && rm -rf "$LOCK"; }
trap release_lock EXIT

git fetch -q origin "$DEFAULT_BRANCH" || die "git fetch failed"
SHA="$(git rev-parse "origin/$DEFAULT_BRANCH")"
SHORT="$(git rev-parse --short "$SHA")"
MSG="$(git log -1 --format=%s "$SHA")"
LAST="$(cat "$STAMP" 2>/dev/null || echo none)"
echo "origin/$DEFAULT_BRANCH = $SHORT ($MSG); last shipped = ${LAST:0:7}"
if [[ "$SHA" == "$LAST" && $FORCE -eq 0 ]]; then
  echo "nothing to ship"; echo "=== ship done $(date -Iseconds) ==="; exit 0
fi

# Docs-only merges advance the stamp without a publish, so the patrol's
# unshipped alert does not fire for a README change. "Docs-only" means every
# file changed since the last stamp is under one of ship_skip_paths
# (default docs/). --stamp-only forces the same outcome by hand.
SKIP_PATHS=(${=${$(conf ship_skip_paths):-docs/}})
if (( STAMP_ONLY == 0 )) && [[ "$LAST" != none ]] && git merge-base --is-ancestor "$LAST" "$SHA" 2>/dev/null; then
  CHANGED="$(git diff --name-only "$LAST" "$SHA")"
  NONDOC="$CHANGED"
  for p in "${SKIP_PATHS[@]}"; do NONDOC="$(echo "$NONDOC" | awk -v p="$p" 'index($0, p) != 1')"; done
  if [[ -n "$CHANGED" && -z "$NONDOC" ]]; then
    echo "only $(echo "$CHANGED" | wc -l | tr -d ' ') file(s) under ${SKIP_PATHS[*]} changed since ${LAST:0:7}; stamping without a publish"
    STAMP_ONLY=1
  fi
fi
if (( STAMP_ONLY )); then
  if (( DRY )); then echo "[dry-run] would record $SHORT as shipped (no publish)"
  else echo "$SHA" > "$STAMP"; echo "recorded $SHORT as shipped (no publish)"; fi
  echo "=== ship done $(date -Iseconds) ==="; exit 0
fi

# --- clean worktree at origin/<default> ---
# Never build from the checkout's working tree: it has uncommitted scratch,
# and what ships must be exactly what merged.
cleanup
git worktree add --detach -q "$WT" "$SHA" || die "worktree add failed"
cd "$WT" || die "cd worktree failed"
ship_prepare_worktree || die "ship_prepare_worktree failed"

# ---------------------------------------------------------------------------
# 1. Production migration, then assert
# ---------------------------------------------------------------------------
PENDING="$(ship_pending_migrations)" || die "could not list production migrations; not publishing"
if [[ -n "$PENDING" ]]; then
  echo "pending production migrations: $(echo "$PENDING" | tr '\n' ' ')"
  if (( DRY )); then
    echo "[dry-run] would apply them"
  else
    ship_apply_migrations || die "production migration failed; nothing published"
    # The tool's exit code is not the evidence. The remote list is.
    while IFS= read -r v; do
      [[ -n "$v" ]] || continue
      ship_migration_applied "$v" || die "migration $v still not applied on production after push; nothing published"
    done <<<"$PENDING"
    echo "migrations applied and verified"
  fi
else
  echo "no pending production migrations"
fi

# ---------------------------------------------------------------------------
# 2. Build, verify, publish, per channel
# ---------------------------------------------------------------------------
CHANNELS=(${=$(conf ship_channels)})
(( ${#CHANNELS[@]} )) || die "no ship_channels in docs/factory-config.md"
FAILED=""
for CH in "${CHANNELS[@]}"; do
  echo "-> channel=$CH"
  OUT="$WT/dist-$CH"; rm -rf "$OUT"
  # Clear the cache before EVERY channel. Never build two channels with
  # different values without this between them.
  ship_clear_cache
  ship_build "$CH" "$OUT" || { FAILED="$FAILED $CH(build)"; continue; }
  # Verify before publish: the artifact must carry exactly what this channel
  # expects. The expectation is the config's ship_expect_<channel> value; a
  # missing expectation is itself a failure, because an unverified channel is
  # how staging values reached production.
  WANT="$(conf "ship_expect_$CH")"
  [[ -n "$WANT" ]] || { echo "!! no ship_expect_$CH in docs/factory-config.md; not publishing"; FAILED="$FAILED $CH(no-expectation)"; continue; }
  GOT="$(ship_artifact_config "$CH" "$OUT" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [[ "$GOT" != "$WANT" ]]; then
    echo "!! $CH artifact carries [$GOT], wanted [$WANT]; not publishing"
    FAILED="$FAILED $CH(config-check)"; continue
  fi
  echo "   $CH artifact verified: $GOT"
  if (( DRY )); then echo "[dry-run] would publish $CH"; continue; fi
  ship_publish "$CH" "$OUT" "$SHORT: $MSG" || FAILED="$FAILED $CH(publish)"
done
[[ -z "$FAILED" ]] || die "ship failed for:$FAILED"

# ---------------------------------------------------------------------------
# 3. Record and announce
# ---------------------------------------------------------------------------
# The stamp is what the patrol compares against and what the Foreman checks
# before it tells anyone a change shipped: the issue comment is posted only
# when the PR is MERGED, this script exited 0, and the stamp equals
# origin/<default>. Never on the merge command's exit code alone.
if (( DRY )); then
  echo "[dry-run] would record $SHORT as shipped"
else
  echo "$SHA" > "$STAMP"
  notify "SHIPPED $NAME $SHORT: $MSG"
  echo "SHIPPED $SHA"
fi
cleanup
echo "=== ship done $(date -Iseconds) ==="
