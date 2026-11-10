# Software Factory

A minimalist software factory on a Mac: fire off a spec, have it implemented
without babysitting, get pushed only on escalations, review PRs per feature, and
have the whole thing survive a reboot.

Native Claude Code plus about 500 lines of shell. No orchestrator framework,
no third-party agent runtime.

```
Phone (Claude app, Code tab)
        │  Remote Control (outbound-only from the Mac)
        ▼
Mac (always on; one factory per macOS account)
├── launchd: one RC spawner per project  ← phone picks a project by environment
├── Foreman (persistent, tmux, one per project, never writes code)
├── Workers, reviewers, QA (spawned by the Foreman, each in its own worktree)
├── Task list (~/.claude/tasks/<project>/, on disk, survives restarts)
├── Patrol (launchd, 15 min, deterministic-first)
└── Hooks: gate pyramid + escalation fallback
        │
        ▼
GitHub: issue → spec PR → code PR → reviewer agent (verdict label) → merge
```

## The fleet

| Process | Lifecycle | Started by | Runs from | Model | Defined in |
|---|---|---|---|---|---|
| RC spawner | always on | launchd | one per project dir | n/a | `launchd/rc-server.plist.template` |
| Foreman | always on | launchd → tmux | project root | strongest | `roles/foreman.md` |
| Worker | per issue | Foreman | own worktree | mid-tier | `agents/worker.md` |
| Reviewer | per implementation PR, and again per push | Foreman | own worktree | strongest | `agents/reviewer.md` |
| QA | on request, or after a risky merge | Foreman | own worktree | strongest | `agents/qa.md` |
| Patrol | every 15 min, hourly when idle | launchd | project root | none; cheapest when it must judge | `scripts/patrol.sh` |

What each one does:

- **Foreman** coordinates and never writes code. Turns approved specs into
  tasks, dispatches workers up to a cap, dispatches a reviewer for every PR,
  lands approved PRs, triages escalations, and runs the retro.
- **Worker** implements one issue against its spec, opens a PR, and iterates
  until the reviewer approves. Never merges.
- **Reviewer** is independent of the worker. It re-runs the gates, reproduces
  the spec's acceptance criteria against the running app, posts inline
  findings to the PR, and sets a verdict **label**: `ai-approved` or
  `ai-changes-requested`. A label, because all agents share one GitHub
  account and GitHub rejects self-approval.
- **QA** runs the project's QA procedure, files an issue per confirmed bug,
  investigates to root cause, and proposes the fix as a spec PR. Never
  implements.
- **Patrol** is shell. It nudges the Foreman about ready issues, unreviewed
  PRs and freshly merged specs; watches for a dead Foreman, a stalled task, an
  exhausted usage limit and an expiring login. A healthy factory costs it zero
  tokens.

Roles are **system prompts**, not first user messages. Skills are *procedures*
any session can invoke. `CLAUDE.md` holds rules every session must load. Keep
those three separate — see [docs/ROLES.md](docs/ROLES.md).

## Install

```sh
sudo pmset -a sleep 0 disablesleep 1      # machine level, once

./install.sh                              # account level
./install.sh --project ~/code/myproject   # per project: scaffolding only
```

Each command prints the manual steps that follow it. The ones that matter:

1. Set `"remoteControlAtStartup": true` in `~/.claude/settings.json`, or the
   Foreman cannot be reached from the phone.
2. **Run `/onboard-repo` in the project and merge its PR before starting
   anything** (next section).
3. Accept the two one-time prompts launchd cannot answer (workspace trust per
   directory, Remote Control consent per machine), create the labels, add the
   project to `boot.sh`, load the launchd jobs.

## Onboarding a repository

`install.sh --project` writes templates. They know nothing about your
codebase, and agents dispatched against templates will guess.

The `onboard-repo` skill closes that gap in two phases:

- **It analyses the repository**: architecture and components; the build,
  test and validation commands, each one actually run; existing conventions;
  the areas most likely to break.
- **It interviews you** for what the code cannot say: your golden principles;
  which existing patterns are intent and which are debt; what QA depth means
  for this app (simulators, a browser, API contract tests); what agents may
  decide alone and what must escalate; your default `review:` and `budget:`.

It then opens **one pull request** containing a draft `AGENTS.md`, a draft
`qa-procedure` skill, and the factory config. You review it line by line.
Nothing is dispatched until you merge it.

This is iteration zero of the feedback loop described below: the same
artifacts, changed by the same propose-then-approve mechanism the factory
uses forever after.

## How work flows

```
QA finds a bug (or you file an issue)
  → GitHub issue, immediately                     status:triage
  → investigation to root cause
  → a SPEC PR, titled "spec: …"                   status:needs-spec
      Part 1, for you: what is wrong, what changes,
              how we will know. No code identifiers.
      Part 2, for the worker: root cause at file:line,
              acceptance criteria, evidence required.
  → YOU merge the spec PR  ← the approval gate
  → patrol sees the merge; Foreman relabels       status:ready
  → Foreman creates a task, dispatches a worker
    into its own worktree (at most 5 at once)     status:in-progress
  → worker opens a PR containing "Closes #n"
  → Foreman dispatches a reviewer (never the worker itself)
  → reviewer re-runs the gates, reproduces the
    acceptance criteria, posts inline findings,
    labels the PR ai-approved | ai-changes-requested
  → worker addresses findings; reviewer goes again
  → review: human → you merge
    review: auto   → the Foreman merges
  → issue closes on merge; Foreman runs the retro
```

You are in this loop twice: merging the spec, and merging the code when the
spec says `review: human`. Everything else is driven by the patrol.

Two fields in each spec are yours alone, never guessed by an agent:

```
review: human | auto     # who approves the implementation PR
budget: 15               # iteration cap that stops a grinding worker
```

Specs are always reviewed by you. `review: auto` means "you already approved
the intent; you don't need to see the code."

## Standing rules

[docs/factory-config.md](docs/factory-config.md) holds the rules the Foreman
runs by. The shipped defaults are the safe ones:

| Setting | Default | Meaning |
|---|---|---|
| `landing` | `per-spec` | `review: human` is honored: the Foreman does not merge those PRs |
| `max_parallel_workers` | `5` | all agents share one usage window |
| `default_review` / `default_budget` | `human` / `15` | what an agent drafting a spec starts from |
| `data_policy` | `preserve` | anything that could lose existing data escalates |

A deployment may override them. A pre-release project with no users might
choose `landing: autonomous`, so approved code lands without you, and
`data_policy: regenerable`. That choice has to be written in the file.

So does every other rule. **If you tell the Foreman "always" or "never"
anything, it writes the rule into that file the same day.** A long-lived
agent session accumulates instructions that exist nowhere else and vanish at
its next restart; the first deployment found three.

## The feedback loop

Every merged PR is mined for lessons, from five sources: your PR comments,
your answers to escalations, reviewer findings, the worker's reflection, and
the bugs QA finds. Each lesson is routed by what it is:

- **Golden principles** (durable judgement: architectural rules, invariants,
  scope philosophy) are proposed to `AGENTS.md`.
- **Tactical hardening** (mechanical, enforceable) is proposed to the artifact
  that enforces it: a new test, the reviewer's checklist, the QA procedure,
  the spec template, or a config default.

Everything lands in one queue, [docs/proposals.md](docs/proposals.md), each
line tagged with its target and carrying one line of evidence. You approve
line by line. Approved instruction edits are applied in one PR you merge;
approved test proposals become tasks. `AGENTS.md` changes only by lines you
approved.
The Foreman tells you the pending count every time you ask for status, so the
queue cannot rot quietly. Details: [docs/FEEDBACK.md](docs/FEEDBACK.md).

## What you have to do, ongoing

- Merge spec PRs. Merge `review: human` code PRs.
- Answer escalations: one specific question each.
- Review the proposal queue when the count bothers you.
- **About once a month, run `claude auth login` on the machine.** The login
  behind Remote Control expires and cannot be renewed from the phone. The
  patrol warns 72 hours ahead. See [docs/OPERATIONS.md](docs/OPERATIONS.md).

## Read this before building

**[docs/FINDINGS.md](docs/FINDINGS.md)** — what was wrong in the original design
and what is true but undocumented. It will save you a day.

**[docs/OPERATIONS.md](docs/OPERATIONS.md)** — the runbook: Remote Control
setup, the monthly login expiry, usage-limit pauses, restarting things.

**[docs/REVIEW.md](docs/REVIEW.md)** — how review works: a local reviewer agent
that runs the code and signals its verdict with a label, and the optional
GitHub Action for when you need an off-machine review or a formal approval.

**[docs/FEEDBACK.md](docs/FEEDBACK.md)** — how the factory changes its own
instructions, and why you approve every line.

**[docs/QA-REFERENCE.md](docs/QA-REFERENCE.md)** — one complete implementation
of the QA procedure contract, described.

**[docs/DESIGN.md](docs/DESIGN.md)** — the reasoning: why per-project Foremen,
why no orchestrator framework, what is deliberately not used.

**[docs/QUESTIONS.md](docs/QUESTIONS.md)** — what is still undecided.

## Deliberately not used

- **Orchestrator frameworks** — throughput over correctness, lost work by
  design, yolo defaults. The opposite bargain from this one.
- **Multi-session agent teams** — built for work whose interfaces move
  mid-flight. If you pin contracts in the spec first, tasks are independent and
  the coordination fabric is unnecessary.
- **A dedicated backlog tool on day one** — GitHub Issues plus the native task
  list covers a single project. Upgrade when the backlog spans machines.
- **A GitHub Action as the reviewer** — it was the original design and never
  produced a review (a missing GitHub App install; 401 on every PR). It also
  cannot run the app, which turned out to be most of what review is for. Kept
  as an opt-in example in [`examples/`](examples/claude-review.yml).
- **GitHub's formal approvals and branch protection** — unavailable while every
  agent shares one GitHub account. The verdict is a label and `review: human`
  is a convention the Foreman follows.

## Honest limits

- macOS only: launchd, the keychain and tmux are assumed throughout.
- Mobile cannot change permission modes mid-session; launch workers in their
  final mode.
- `review: human` is enforced by the Foreman's instructions, not by GitHub.
- The login expiry needs hands on the machine about monthly.
- The patrol's usage-limit and login-expiry checks read undocumented Claude
  Code internals and may need adjusting after an upgrade.
- Multi-agent runs cost several times the tokens of equivalent single-agent
  output. The `budget:` field and the worker cap are the controls.
- Reliability compounds downward across chained steps. Keep the pipeline
  shallow: spec → worker → reviewer.
- **Spec quality is the bottleneck.** Vague specs do not fail loudly; they
  produce scope creep caught late. Time in the spec is the cheapest quality
  gate in the system.
