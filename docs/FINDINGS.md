# Findings

Things that were wrong in the original design, or true but undocumented, and
cost real debugging time. Every item here was verified empirically on
Claude Code 2.1.266 / macOS 26.2.

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
own commit. Exclude the scanner from the diff it inspects:
`git diff --cached -U0 -- . ':(exclude)*secret-scan.sh'`. Found by this repo
refusing to accept its own first commit.

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
different identity (a GitHub Action runs as `github-actions[bot]`, which can
approve).

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
