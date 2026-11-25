# Operations

What is running, what expires, and what to do when it does. Everything here
was learned by running one factory for two months; the reasoning behind each
item is in [FINDINGS.md](FINDINGS.md).

## What runs

Per macOS account:

| Thing | launchd label | Log (under `~/Library/Logs/factory/`) |
|---|---|---|
| Boot recovery, starts each Foreman in tmux | `com.<prefix>.factory-boot` | `boot.log` |
| Remote Control spawner, one per project | `com.<prefix>.claude-rc-<project>` | `claude-rc-<project>.log` |
| Patrol, one per project | `com.<prefix>.patrol-<project>` | `patrol-<project>.log` |

Foremen are tmux sessions named `foreman-<project>`. `tmux ls` is the
authoritative list; the phone app's session names drift.

## Remote Control: two separate things

They are easy to conflate, and each fails differently.

**1. Sessions registering themselves.** Set this once per account in
`~/.claude/settings.json`:

```json
{ "remoteControlAtStartup": true }
```

`./install.sh` sets it for you. With it, every new interactive session
registers with Remote Control when it launches, so the Foreman appears in the
phone app without anyone typing a command into it. Without it, a Foreman started by `boot.sh` runs correctly and
is invisible from the phone. The setting is read at session start: sessions
already running when you add it need a restart.

**2. Spawners.** `claude remote-control --spawn same-dir` under launchd is what
lets the phone start a *new* session. A spawner is tied to one directory, and
that directory is the "environment" the phone shows. `install.sh --project`
installs one per project, so each project appears in the Claude app as its
own environment.

## The login expires about once a month

The claude.ai OAuth login that Remote Control depends on expires roughly a
month after `claude auth login`. Nothing in the app warns you. When it lapses:

- every session silently drops off the phone;
- spawners exit and are respawned by launchd in a loop;
- agents already running keep working, so the factory looks alive from the
  ledger and dead from the phone.

The patrol reads the expiry from the keychain on every run and sends a
notification **72 hours ahead**, at most once a day, and again if it has
actually expired.

**The fix needs hands on the machine** (or a remote shell to it):

```sh
claude auth login

# then restart every spawner; they do not recover on their own
for l in $(launchctl list | awk '/claude-rc/ {print $3}'); do
  launchctl kickstart -k "gui/$(id -u)/$l"
done
```

Interactive sessions, including each Foreman, reconnect by themselves after
the re-login. **Spawners do not.** The patrol notices that the expiry moved
forward and reminds you once to restart them; it never restarts them itself,
because a restart drops any sessions the spawner is hosting.

`claude setup-token` is not a way out. Its token lasts a year and is fine for
headless use, but it cannot register Remote Control. A factory you reach from
a phone needs the interactive login, and therefore a monthly visit. Put the
re-login on a calendar a few days inside the window rather than relying on
the 72-hour warning arriving at a convenient moment.

## Usage limits

All agents share one subscription's usage window. When it is exhausted every
agent, the Foreman included, dies with a 429 that names a reset time.

- The patrol finds that message in the session transcripts, notifies you
  once, and **pauses**: no nudges, no model calls, until the reset time.
- On the first pass after the reset it nudges the Foreman once to resume
  whatever was cut off.
- `max_parallel_workers` in [factory-config.md](factory-config.md) is the
  prevention. The patrol alerts when in-progress issues exceed it.

The detector parses Claude Code's transcript format and the wording of the
error, and reads the reset time in the machine's timezone. None of that is a
stable interface. If the factory stalls after an upgrade with no "usage
limit" line in the patrol log, check the match strings in `patrol.sh` first.

## Patrol cadence

launchd fires the patrol every 15 minutes. Login, spawner and Foreman
liveness checks run every time. The rest of the pass backs off to hourly
when the last full pass found nothing in flight and nothing actionable, and
returns to every 15 minutes at the first finding.

State lives next to the logs, one set per project:

| File | Meaning |
|---|---|
| `patrol-<project>.paused` | present while the operator has the patrol turned off |
| `patrol-<project>.state` | `active` or `quiet` |
| `patrol-<project>.lastrun` | when the last full pass ran |
| `patrol-<project>.limit-until` | present while a usage limit is in force |
| `patrol-<project>.last-merge-check` | watermark for "spec PRs merged since" |
| `patrol-<project>.expiry-warned` | last login-expiry warning sent |
| `patrol-<project>.login-expiry-seen` | last expiry observed, to detect a re-login |
| `ship-<project>.last` | the commit `scripts/ship.sh` last shipped; the patrol alerts when the default branch is ahead of it |

To force a full pass now: `rm ~/Library/Logs/factory/patrol-<project>.state`.

**Turning it off.** Tell the Foreman to pause the patrol, or do it yourself:
`touch ~/Library/Logs/factory/patrol-<project>.paused`. While that file
exists the patrol does nothing for that project except the login-expiry
check. Remove the file, or tell the Foreman to resume, to turn it back on.
Nothing resumes it automatically. The launchd job stays loaded throughout, so
there is nothing to `bootout` and nothing to remember to reload.

The patrol finds the Foreman by tmux session name. If you gave a project an
explicit name in `boot.sh` (`"<path>|<name>"`), install it with the same one:
`./install.sh --project <path> --name <name>`.

## Logs

Nothing rotates the files under `~/Library/Logs/factory/`. The spawner logs
are the ones that grow: tens of megabytes a month each. Truncate or rotate
them on whatever schedule you already use; the factory keeps no state in
them.

## How the factory reaches you

Two channels, and they are not the same thing.

| Channel | Who uses it | For |
|---|---|---|
| **Claude app notifications** (through Remote Control) | the Foreman and other sessions | escalations, "this PR is ready for you", anything that needs a decision |
| **ntfy** (a separate phone app, subscribed to your private topic) | the patrol and the escalation hook | the factory itself is unhealthy: login expiring, spawner down, usage limit hit, Foreman could not be restarted |

The patrol is a shell script and cannot send a Claude app notification. More
to the point, most of what it reports is Remote Control being down, which is
exactly when the Claude app cannot reach you. **If you have not installed
ntfy and subscribed to the topic in `~/.claude/factory/NTFY_TOPIC`, you
receive none of the patrol's alerts.**

Each condition is alerted **once**, when it first appears, and not again
until it has cleared and recurred. The login-expiry warning is the exception:
once a day for the last 72 hours.

## Restarting a Foreman

The patrol does this by itself: if a Foreman's tmux session is gone it runs
`boot.sh`, and you hear about it only if that fails. By hand:

```sh
tmux kill-session -t foreman-<project>
~/.claude/factory/boot.sh
```

This is a cold start by design. The Foreman rebuilds from the issue labels,
the task list, the open PRs and `docs/factory-config.md`. If a restart loses
something, that thing was in the wrong place; write it into the config file
or the ledger and file it as a finding.

Restart after changing the Foreman role, any agent definition, or
`.claude/settings.json`: all are read at session start, and a running session
never picks them up.

## The ship step

Merging an implementation PR publishes nothing. A git hook on push never
fires for a merge made on GitHub (one factory's default branch drifted 42
commits past its last published build that way), so shipping is a step the
Foreman runs right after each merge, from the project root:

```sh
scripts/ship.sh              # the normal run
scripts/ship.sh --dry-run    # everything except migrate, publish, stamp
scripts/ship.sh --stamp-only # record origin/main as shipped, no publish
```

`install.sh --project` copies the skeleton into the project; onboarding fills
in the project's own commands (the `ship_*` functions at the top of the
script) and the "Ship step" block in `docs/factory-config.md`. The control
flow is the factory's and is the same everywhere:

1. **Lock.** One ship per project at a time. The lock is a directory holding
   the owner's pid, released only from an `EXIT` trap. Waiters queue for ten
   minutes, then give up; a lock whose owner is gone and which is older than
   thirty minutes is reclaimed. Two Foreman sessions once shipped at once and
   one wiped the other's worktree; a later version released the lock from a
   cleanup function that also ran at start, and they collided again.
2. **Compare.** Fetch, and stop if `origin/main` is what was last shipped.
   If every file changed since the last stamp is under the config's
   `ship_skip_paths` (default `docs/`), stamp without a publish, so a README
   merge does not trigger the unshipped alert and does not rebuild anything.
3. **Clean worktree.** Build from a detached worktree at `origin/main`,
   never from the checkout's working tree. The project's
   `ship_prepare_worktree` copies in dependencies and the untracked
   environment files each channel needs, and mirrors any folder a CLI reads
   that git does not track.
4. **Migrate, then assert.** If the project has a production migration step,
   list what is pending, apply it, and then **check the remote migration
   list shows each version applied**. The tool's exit code is not the
   evidence. One factory's ship step never applied a migration for a day
   because the CLI read a folder the clean worktree did not have, and
   nothing said so until a device broke. If the CLI reads a different folder
   than the one tracked in git, mirroring it is a documented convention in
   the config, not a surprise.
5. **Per channel: clear, build, verify, publish.** Clear the bundler's cache
   before every channel build. Build. Extract the configuration the artifact
   actually carries (`ship_artifact_config`: backend host, client ids,
   feature flags) and compare it with `ship_expect_<channel>` in the config.
   On mismatch, do not publish, and name the channel in the failure summary.
   A channel with no expectation configured also fails. The reason: bundlers
   inline public configuration at transform time and their cache key ignores
   the values, so a staging build poisons the production build that follows
   it in the same worktree. One factory published production bundles with
   staging values for a day before a phone showed it. Never build two
   channels with different values without a cache clear between them.
6. **Stamp, then announce.** Write the shipped commit to
   `~/Library/Logs/factory/ship-<project>.last` and notify the phone. The
   patrol reads the stamp and alerts when `main` is ahead of it.

The Foreman posts "Shipped" on the issue only when `gh pr view --json state`
says `MERGED`, the script exited 0, and the stamp equals `origin/main`. Never
on `gh pr merge`'s exit code alone.

**Device builds.** When the project ships native builds, a new build is
offered to testers only after a short smoke on a real device; the config
lists the steps and the Foreman asks for "smoke ok" before publishing the
install. Simulators lag real devices and have passed builds whose sign-in
button crashed the app. QA exercises the published update path on a release
build at least once per pass, not only a dev-server bundle: the publish step
is where configuration goes wrong, and a dev server never runs it.

Log: `~/Library/Logs/factory/ship-<project>.log`. Worktree and lock:
`~/.claude/factory/work/ship-<project>` and `ship-<project>.lock`
(`FACTORY_WORK` overrides the directory).

## Two Foreman sessions at once

The standing tmux Foreman and an interactive session the operator opens in
the same project both act on the same ledger. Left to themselves they
double-dispatch workers and reviewers and race each other's ship worktrees.
Four rules keep them apart, and the Foreman role carries them:

- claim an issue only by editing its label while it is still
  `status:ready`; the edit is the claim;
- comment "Reviewer dispatched for PR #n" on the issue before dispatching
  one, and look for that line before dispatching;
- the ship lock serialises shipping; never bypass it;
- the interactive session finishes what it already holds and leaves new
  queue dispatch to the standing session.

## Upgrading from this template

`./install.sh` is safe to re-run. It re-copies the role, agents, skills and
scripts into `~/.claude`, keeps the existing notification topic, and keeps an
existing `boot.sh` (the new one is written beside it as `boot.sh.new` for you
to merge, because `boot.sh` holds your `PROJECTS` list).
`./install.sh --project <path>` never overwrites a project's `AGENTS.md`,
spec template, config, checklist, QA skill, product-reference index or ship
script.

Then restart each Foreman. Running sessions keep the role they started with.
