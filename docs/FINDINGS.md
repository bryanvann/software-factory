# Findings

Things that were wrong in the original design, or true but undocumented, and
cost real debugging time. Every item here was observed on a running factory,
on Claude Code 2.1.266 through 2.1.321 / macOS 26.2. Items that depend on
undocumented behaviour say so; re-verify those after an upgrade.

---

## Remote Control

**`--spawn session` is the wrong mode for an always-on server.** It is
"classic single-session mode (exits when that session ends)." Paired with
launchd `KeepAlive` you get a respawn loop, not a persistent spawner. Use
`--spawn same-dir` (the default), which is "a persistent server that accepts
multiple concurrent sessions in the current directory."

**The RC server is directory-scoped, and the directory is the identity.** In
the phone app's "Choose environment" sheet, each running server appears as
`<device> <basename-of-cwd>`. There is **no directory picker** when creating a
session — the environment you choose *is* the directory. So to select a project
from your phone, run **one RC server per project**, each with that project as
its working directory.

**`--name` names the pre-created session, not the environment.** The server
seeds one empty session on start so there is somewhere to type immediately;
that is what `--name` labels. Suppress it with `--no-create-session-in-dir`.

**`--spawn worktree` requires a git repository.** It cannot run from a
non-repo parent directory, which is another reason to point servers at
projects rather than at `~/code`.

**Consent is one interactive prompt, once per machine.** `claude
remote-control` asks "Enable Remote Control? (y/n)" and launchd has no TTY to
answer it, so the job fails and respawns. Run it by hand once and answer; it
persists to `~/.claude.json` as `remoteDialogSeen: true` plus a
`remoteControlMachineId`. This is *not* the workspace trust dialog — running
plain `claude` in the directory does not satisfy it.

**There are two separate one-time prompts, and you need both.** The Remote
Control consent is per *machine* (`remoteDialogSeen` in `~/.claude.json`); the
workspace trust dialog is per *directory* (`hasTrustDialogAccepted`, under that
project's entry). launchd can answer neither. Onboarding a new project means
running `claude` in it once even if Remote Control was accepted long ago —
otherwise the RC server exits with "Workspace not trusted" and KeepAlive
respawns it in a loop.

**Sessions do not register with Remote Control unless told to.** A spawner
lets the phone *start* sessions; it does nothing for a session started some
other way. The Foreman is started by `boot.sh` in tmux, so without
`"remoteControlAtStartup": true` in `~/.claude/settings.json` it runs fine and
cannot be reached from the phone. That one account-level key makes every new
interactive session register at launch.

**The login behind Remote Control expires about monthly, silently.** The
claude.ai OAuth refresh token lasts roughly a month from `claude auth login`.
When it lapses, sessions drop off the phone and spawners crash-loop under
`KeepAlive`, while running agents carry on, so the ledger shows a healthy
factory that cannot be reached. Recovery needs `claude auth login` typed on
the machine. The expiry is readable in advance from the keychain item
`Claude Code-credentials` (`claudeAiOauth.refreshTokenExpiresAt`), so have the
patrol warn 72 hours ahead. That keychain layout is undocumented.

**After a re-login, spawners must be restarted; interactive sessions must
not.** Interactive sessions pick up the new credential and reconnect by
themselves. Server-mode spawners keep failing until they are restarted
(`launchctl kickstart -k`).

**`claude setup-token` cannot do Remote Control.** Its one-year token looks
like the cure for the monthly expiry and is not: it authenticates headless
runs but cannot register a Remote Control session. A phone-driven factory
needs the interactive login and therefore a monthly visit.

**Per-project spawners leave no place for ad-hoc work.** A session started
from a project's environment is in that project. Run one extra spawner in the
parent directory of your checkouts for everything else. It uses `--spawn
same-dir`, which, unlike `--spawn worktree`, does not need a git repository.

## Roles and identity

**A role passed as `claude "$(cat role.md)"` is a user message, not a system
prompt.** It can be diluted, argued away, or lost to compaction — bad for a
session meant to run for days. Use `--append-system-prompt "$(cat role.md)"`
instead. Verified: a Foreman started this way restates its constraints
accurately after a restart.

**Do not resume a long-lived role session with `--continue`.** It resumes the
*most recent* session in that directory, which may be an ad-hoc session, a QA
session, or a throwaway probe. Cold-start from the role file; the role's
durable state belongs on disk, not in a context window. If you must resume a
specific session, resume it by id (`claude --resume <uuid>`).

**A long-lived role session accumulates rules that exist nowhere else.** Two
months in, the deployed Foreman was following three standing rules the
operator had given it in conversation: land approved code whatever the spec's
`review:` field said, never run more than five workers at once, and treat all
data as regenerable with one named exception. None was in any file. Each
would have vanished at the next cold start, and the factory would have
changed behaviour without telling anyone. This is the design's own rule
("nothing important lives only in a context window") being violated by its
most important session, and it happens by default, because telling the
Foreman something feels like configuring it. The fix is a config file the
Foreman must re-read (`docs/factory-config.md`) and a standing instruction to
write verbal rules into it the same day.

## The task system

**It exists and works, but is easy to conclude otherwise.** `TaskCreate`,
`TaskList` and `TaskUpdate` are real, need no feature flag, and store one JSON
file per task under `~/.claude/tasks/<list-id>/`, with a `.lock` and
`blocks`/`blockedBy` dependency edges.

**`CLAUDE_CODE_TASK_LIST_ID` in a project's `.claude/settings.json` `env`
block is sufficient** to route a session's tasks into a shared per-project
list. Verified end to end.

**Resumed sessions keep their original tool inventory.** A session resumed with
`--resume` does *not* gain tools that were added since it started. A session
resumed from before the task tools existed will correctly report that it has no
`TaskList`. A fresh session in the same directory has all three. Plan for this:
long-lived agents cannot be upgraded in place.

**Agents are unreliable narrators of their own tool inventory.** Two separate
sessions confidently reported that no task-list tool existed. One had checked
via tool search and was right about itself; the other was simply wrong. Verify
tool availability by *using* the tool, not by asking.

## Environment and process hygiene

**tmux sessions inherit the environment of whoever started the tmux server.**
Starting a Foreman from inside another Claude session leaks that session's
`CLAUDE_CODE_BRIDGE_SESSION_ID` and `CLAUDE_CODE_CHILD_SESSION` into it. Start
the tmux server from launchd so roles get a clean environment.

**Settings are read at session start.** A session started before you wrote
`.claude/settings.json` never sees it. When onboarding a project, restart any
already-running agents or their work lands in the wrong task list.

**`.githooks` + `core.hooksPath` propagates to every worktree for free**, since
`core.hooksPath` lives in shared config and the hooks directory is tracked.
One install covers all workers.

## Gates

**Gate agents differently from humans.** `CLAUDECODE=1` is set inside Claude
Code sessions and unset in a plain terminal. Use it so the diff-size guard is a
scope-creep tripwire for workers without blocking your own large hand commits.
Secret scanning should apply to everyone.

**Watch out for `grep` eating your patterns.** A secret-scan pattern beginning
with `-` (e.g. a PEM `BEGIN ... PRIVATE KEY` header) is parsed as a flag and
silently never matches. Use `grep -qE -- "$pattern"`. This class of bug fails
open, so test every pattern against a known-bad fixture.

**Do not enable a gate the repo cannot pass.** If `main` does not typecheck,
turning typecheck into a blocking pre-commit gate blocks every worker on
failures it did not cause. Fix the baseline first.

## Cost

**Pin a model per role explicitly.** Headless jobs inherit the account default,
so a 15-minute patrol cron silently runs on your most expensive model. Pin the
patrol to the cheapest capable model.

**Make the patrol deterministic-first.** Most patrol runs have nothing to
report. Do the liveness and staleness checks in shell, and only invoke a model
when there is a candidate to judge. A healthy factory then costs zero tokens
per patrol.

**Model spend is also a throughput ceiling.** Rate limits pool per account, so
tokens burned by a cron are capacity a worker cannot use.

**A secret scanner cannot scan itself.** A repo that ships secret-detection
patterns contains those patterns as literal strings, so the scanner blocks its
own commit — and so does any doc that discusses them. Two escape hatches are
needed: exclude the scanner file from the diff it inspects, and support an
inline `allowlist-secret` marker for lines that legitimately quote a pattern.
Found by this repo refusing to accept its own first commit, twice.

## Naming

**Remote-control sessions are named from their conversation, and the name
drifts.** `CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX` (set at launch, via
`tmux new-session -e VAR=value` for a tmux session) controls only the *initial*
name; the app then re-titles the session from its content as the conversation
moves on. A long-lived role session will therefore keep renaming itself after
whatever it most recently discussed — a Foreman that just processed a patrol
nudge shows up as something like "patrol pending work dispatch", not as
"foreman", and looks to the operator as though it vanished.

Do not rely on the app's session list to identify a role session. Identify it
by its tmux session name (`tmux ls`), its pane pid, or by asking it who it is.
Expect to explain this drift to anyone using the setup, because "my Foreman
disappeared" is the natural conclusion.

**The RC environment label is the server's directory basename and cannot be
changed.** So a project's identity should be its **repo/checkout name**, not a
product or container name: one place in the UI is hard-wired to the directory,
and every other label should agree with it. Keep a container directory name if
it helps you navigate, but never surface it in a label.

**Derive the project name explicitly, not by inference.** `basename` is a fine
default but breaks the moment a checkout directory disagrees with what the
project should be called. Make it an explicit field.

## Review

**One GitHub account cannot approve its own PR.** If every agent authenticates
with the same `gh` token, the "reviewer" is the PR author and
`gh pr review --approve` is rejected. A worker whose finish line is "reviewer
approved" will then poll forever on a `reviews` array that stays empty. Signal
the verdict with a **label** instead, or run the reviewer as a genuinely
different identity (a GitHub Action runs as a bot account, which can
approve).

**The GitHub Action reviewer failed with a 401 on every PR for five weeks.**
The template originally shipped `claude-review.yml` as the default reviewer.
`anthropics/claude-code-action` exchanges its OIDC token for a Claude Code
GitHub App token before it does anything else, and the App had never been
installed on the repository, so every run died with "Claude Code is not
installed on this repository" (401). The result was a red check on every PR
and zero reviews. The Foreman recorded the failure in its first retro, and
there it sat: the note was one line in a proposals file nobody was prompted
to read, and the Foreman was also dispatching the local reviewer agent, which
did all the real reviewing, so nothing visibly broke. The workflow was
eventually deleted. Three lessons:

- An API key is not sufficient for that action. The App install is a separate
  prerequisite, and the failure message names the App, not the key.
- The Action's prompt never mentioned the `ai-approved` /
  `ai-changes-requested` labels that the worker and the patrol wait on. Even
  with the App installed it would have reviewed into the void: comments, but
  no verdict the factory could read. Any reviewer, on any path, must end by
  setting the label.
- A check that is always red is worse than no check. If a gate has never
  passed, either fix it that day or delete it.
- A problem written into a queue is not a problem raised. This is why the
  Foreman now reports the pending-proposal count in every status answer.

The local agent is now the only reviewer installed. The Action survives as an
opt-in example with both problems fixed; see [REVIEW.md](REVIEW.md).

**The reviewer must run the code, not read it.** Reviews that re-ran the gates
and reproduced the device-level acceptance criteria found defects that every
code-only read had passed: tests that asserted call order with a marker
recorded at call time (green whether or not the code awaited), a revert that
"proved" a test only because it no longer compiled, evidence in a PR body
describing state that a later reset had wiped. Make reproduction the
reviewer's standing instruction, and give it the same app bring-up procedure
QA uses.

**Nothing acts on an `auto-merge` label by itself.** A label is not GitHub's
auto-merge feature, and with no workflow watching it, a `review: auto` PR sits
approved and open indefinitely. Either enable auto-merge on the repository
and have the worker call `gh pr merge --auto`, or (what this template does)
make the merge an explicit Foreman step once the verdict label is
`ai-approved`. The label remains as a visible marker of what the spec asked
for.

**The worker must not spawn its own reviewer.** It is technically easy and
quietly defeats the point: the writer ends up choosing what the reviewer sees
and how the task is framed. Dispatch reviewers from the Foreman.

**Post findings to the PR, not into chat.** Review comments are read by the
operator, acted on by the worker, and later mined for context-file proposals.
A finding that lives only in an agent's context dies with the session.

## Triggering

**Nothing triggers a persistent role session on its own.** A Foreman sitting in
tmux acts only when spoken to, so "fire and forget" does not happen for free —
someone has to notice that work is ready. Give the patrol that job: it already
runs on a schedule and already reads the ledger. Have it nudge the Foreman
(`tmux send-keys`) when it finds dispatchable issues or unreviewed PRs.

**Design the nudge to be self-limiting.** Nudge on states that *change* when
acted upon — an issue leaving `status:ready`, a PR gaining a verdict label — so
a handled item stops matching on the next pass without needing to track what
was already sent.

**A human-approval gate can double as the automation trigger.** If an issue only
reaches `status:ready` after a person merges its spec, then auto-dispatching
from `ready` is not bypassing review — approval is exactly what put it there.
Look for a state that already encodes consent before adding a separate one.

**Merging a spec PR approves it and changes nothing else.** The approval gate
is "the operator merges the spec PR", but a merge does not relabel the issue,
so the issue never reaches `status:ready` and the factory waits forever on
work that was approved. Have the patrol list spec PRs merged since its last
pass and tell the Foreman to relabel and dispatch.

**Tell the patrol which PRs are not the reviewer's.** "Open PRs with no
verdict label" also matches spec, QA and docs PRs, which are the operator's to
read. Nudging the Foreman about them every 15 minutes is noise, and worse, an
obedient Foreman dispatches a reviewer at a spec. A title-prefix convention
(`spec:`, `qa:`, `docs:`) is enough to exclude them, as long as it is written
in `CLAUDE.md` where every agent sees it.

**Back off when there is nothing to do.** When everything is waiting on the
operator, a 15-minute patrol just re-nudges about the same state. Track
active/quiet between runs: full passes hourly while nothing is in flight,
back to every 15 minutes at the first finding.

**A usage limit stops the Foreman too, so the patrol has to handle it
alone.** When the shared usage window is exhausted, every agent dies with a
429, and nudging a Foreman that cannot answer achieves nothing. The reset time
is in the error text, which lands in the session transcripts under
`~/.claude/projects/`. Parse it, pause until then, and nudge once afterwards
to resume what was cut off. Scan every recently-touched transcript, not just
the newest: subagent sidechains write there too, and reading only the newest
file produced false "limit reset" nudges. This depends on the transcript
format and the error wording, both undocumented.

**Cap parallel workers explicitly.** Nothing limits how many workers a Foreman
will dispatch from a full `status:ready` queue, and enough of them will spend
a whole usage window in one burst. Five was the workable ceiling on one
subscription. Make it a setting and have the patrol alert on a breach.

**In zsh, a function must be defined above its first call, and the failure is
silent.** The deployed patrol defined `notify()` halfway down the script,
below four call sites added later. Each of those calls fails as "command not
found" into a log nobody reads: the usage-limit notice was lost every time it
fired (seven times, by the log), and the login-expiry and spawner-down alerts
would have been lost the same way the first time they were needed. The script
exited zero throughout. Test an alerting path by making it fire, not by
reading it.

**Spawner logs grow without bound.** launchd appends each spawner's stdout to
one file forever. After two months the three spawner logs here were 24 MB,
69 MB and 166 MB. Rotate them (`newsyslog`, or truncate from the boot
script) before they become the reason the disk is full.

## Agent worktrees

**`isolation: worktree` nests the worktree inside the checkout**, at
`.claude/worktrees/<agent-id>`. The location is not configurable — there is no
env var or setting for it, and Claude Code owns that directory (a background
retention sweep deletes worktrees found there, so never put your own in it).

This is safe for git and unsafe for everything else that walks the filesystem:

- **git does not care.** A worktree's location is irrelevant: its `.git` file
  points at `<main>/.git/worktrees/<id>`, and it has its own HEAD, branch and
  index while sharing the object database. It commits and pushes normally.
  Git also treats it as a repository boundary and will not recurse into it.
- **`git add -A` in the parent stages it as a gitlink** (mode 160000), not as
  a copy of the files — an embedded-repo entry with no `.gitmodules`. Clones
  then get an empty directory and a broken submodule reference. Gitignore
  `.claude/worktrees/`.
- **Test runners and bundlers DO care.** Anything that scans from the project
  root sees N full copies of the source. In a React Native repo this surfaces
  as `jest-haste-map` naming collisions and a Metro watcher crawling every
  agent's checkout. Exclude the path explicitly:
  - jest: `modulePathIgnorePatterns` **and** `testPathIgnorePatterns`
  - Metro: `resolver.blockList`

Do this **before** dispatching a worker. Otherwise the first worker's own
worktree can break the test suite that its acceptance criteria depend on —
which is exactly how this was discovered.
