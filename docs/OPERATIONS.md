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
| Remote Control spawner for a parent directory (optional) | `com.<prefix>.claude-rc-<dirname>` | `claude-rc-<dirname>.log` |
| Patrol, one per project | `com.<prefix>.patrol-<project>` | `patrol-<project>.log` |

Foremen are tmux sessions named `foreman-<project>`. `tmux ls` is the
authoritative list; the phone app's session names drift.

## Remote Control: three separate things

They are easy to conflate, and each fails differently.

**1. Sessions registering themselves.** Set this once per account in
`~/.claude/settings.json`:

```json
{ "remoteControlAtStartup": true }
```

With it, every new interactive session registers with Remote Control when it
launches, so the Foreman appears in the phone app without anyone typing a
command into it. Without it, a Foreman started by `boot.sh` runs correctly and
is invisible from the phone. The setting is read at session start: sessions
already running when you add it need a restart.

**2. Spawners.** `claude remote-control --spawn same-dir` under launchd is what
lets the phone start a *new* session. A spawner is tied to one directory, and
that directory is the "environment" the phone shows. `install.sh --project`
installs one per project.

**3. A second spawner for everything else.** The per-project spawners only
start sessions inside their project. For ad-hoc work that belongs to no
project, or spans several, run one more spawner in the directory that
contains your checkouts:

```sh
./install.sh --spawner ~/code
```

It shows up on the phone as its own environment. Sessions it starts can reach
every repository beneath it, which is the point and also the reason to keep
it separate: use the project's own spawner for project work, so those sessions
load that project's settings, hooks and task list. Like any spawner
directory, it needs the workspace trust dialog accepted once by hand
(`cd <dir> && claude`).

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
| `patrol-<project>.state` | `active` or `quiet` |
| `patrol-<project>.lastrun` | when the last full pass ran |
| `patrol-<project>.limit-until` | present while a usage limit is in force |
| `patrol-<project>.last-merge-check` | watermark for "spec PRs merged since" |
| `patrol-<project>.expiry-warned` | last login-expiry warning sent |
| `patrol-<project>.login-expiry-seen` | last expiry observed, to detect a re-login |

To force a full pass now: `rm ~/Library/Logs/factory/patrol-<project>.state`.

The patrol finds the Foreman by tmux session name. If you gave a project an
explicit name in `boot.sh` (`"<path>|<name>"`), pass the same name as the
patrol's second argument in its plist.

## Logs

Nothing rotates the files under `~/Library/Logs/factory/`. The spawner logs
are the ones that grow: tens of megabytes a month each. Truncate or rotate
them on whatever schedule you already use; the factory keeps no state in
them.

## Restarting a Foreman

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

## Upgrading from this template

`./install.sh` is safe to re-run. It re-copies the role, agents, skills and
scripts into `~/.claude`, keeps the existing notification topic, and keeps an
existing `boot.sh` (the new one is written beside it as `boot.sh.new` for you
to merge, because `boot.sh` holds your `PROJECTS` list).
`./install.sh --project <path>` never overwrites a project's `AGENTS.md`,
spec template, config, checklist or QA skill.

Then restart each Foreman. Running sessions keep the role they started with.
