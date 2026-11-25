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
| Spec writer | per bug with no spec | Foreman | own worktree | strongest | `agents/spec-writer.md` |
| Patrol | every 15 min, hourly when idle | launchd | project root | none; cheapest when it must judge | `scripts/patrol.sh` |
| Ship step | after each implementation merge | Foreman | project root | none | `scripts/ship.sh` |

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
- **QA** runs the project's QA procedure against the product reference
  (`docs/product/`, what every screen and flow should do), files an issue per
  confirmed bug, investigates to root cause, and proposes the fix as a spec
  PR. Never implements, never edits a product page.
- **Spec writer** takes a filed bug with no spec, confirms the root cause in
  the code, and opens the spec PR. It exists so that bug fixes never wait on
  a human to write their spec.
- **Patrol** is shell, and only ever talks to the Foreman and to your phone.
  It nudges the Foreman about bugs that need a spec, spec PRs awaiting a
  merge decision, ready issues, unreviewed PRs, freshly merged specs and
  merged work that has not shipped; restarts a dead Foreman; watches for a
  stalled task, an exhausted usage limit and an expiring login. It slows to
  hourly when nothing is happening, costs zero tokens when idle, and can be
  switched off per project by telling the Foreman.
- **Ship step** is shell the Foreman runs after each implementation merge:
  production migration, then per channel a clean build, a check that the
  artifact carries that channel's configuration, and the publish. Merging
  publishes nothing by itself.

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

1. Install the ntfy app and subscribe to your topic, or the patrol's alerts
   go nowhere. (`install.sh` sets `remoteControlAtStartup` for you, so every
   session on the machine is reachable from the Claude app.)
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
  → patrol: "Needs a spec"; Foreman dispatches
    a spec writer, which confirms the root cause
  → a SPEC PR, titled "spec: …", saying Refs #n   status:needs-spec
      Part 1, for the driver: what is wrong, what changes,
              how we will know. No code identifiers.
      Part 2, for the worker: root cause at file:line,
              acceptance criteria, evidence required.
  → the spec gate, by kind (default):
      plain bug fix, obvious approach → the Foreman merges
      new feature, architecture, product-impacting
      deviation, open questions, production data → YOU merge
      a change a second driver owns → they merge
  → patrol sees the merge; Foreman relabels       status:ready
  → Foreman creates a task, dispatches a worker
    into its own worktree (at most 5 at once)     status:in-progress
  → worker opens a PR containing "Closes #n", and
    updates the docs/product/ pages the spec names
  → Foreman dispatches a reviewer (never the worker itself)
  → reviewer re-runs the gates, reproduces the
    acceptance criteria, checks the page matches the code,
    posts inline findings,
    labels the PR ai-approved | ai-changes-requested
  → worker addresses findings; reviewer goes again
  → the code gate (default: per spec)
    review: human → you merge
    review: auto   → the Foreman merges
  → issue closes on merge; Foreman runs the ship step,
    then the retro
```

With the default gates you are in this loop for the specs that change the
product, and for the code of any spec you marked `review: human`. A clear
bug fix runs from issue to shipped with nobody waiting on you. Both gates can
be loosened or tightened (see "Standing rules"). Everything else is driven by
the patrol.

Specs are written for every change, whoever merges them: the spec is the
worker's goal and the reviewer's oracle. A spec PR says `Refs #n`, never
`Closes #n`; merging a spec is approval, not a fix.

Two fields in each spec belong to whoever drives the change, never a worker:

```
review: auto             # who approves the implementation PR; auto by default
budget: 6                # iteration cap that stops a grinding worker
```

`review: auto` means "the intent was approved; nobody needs to see the code."
The spec is where a human decides, so `auto` is the default; write `human` on
the one spec whose code you want to see. `budget:` has defaults by kind of
change in the config (a one-screen change, a multi-screen flow, anything
touching data or sync).

### The product reference

`docs/product/` is one page per screen or flow saying what the product does,
as built, in product terms. It is the product truth; design documents and
specs are snapshots. Every spec names the pages it affects
(`product-reference:` in its header), the worker updates them in the same PR,
the reviewer blocks a behaviour change with no page update or a page update
the code does not match, and QA reads the pages before a pass and treats a
contradiction as a finding. Where a page may be wrong, an issue labelled
`product-doc-drift` decides; nobody edits a page to match silently. Without
this, every agent decides "correct" from one spec at a time or its own
judgement, and QA cannot tell a regression from a feature.

The first version is written by workers in three documentation PRs after
onboarding, each reviewed against the code; the `onboard-repo` skill proposes
it as the first issue.

## Standing rules

[docs/factory-config.md](docs/factory-config.md) holds the rules the Foreman
runs by. The shipped defaults are the safe ones:

| Setting | Default | Meaning |
|---|---|---|
| `spec_gate` | `by-kind` | you merge specs for features, architecture and product-impacting change; the Foreman merges plain bug-fix specs; a configured second driver merges theirs. `human` puts you in front of every spec; `auto` lets the reviewer agent approve them |
| `code_gate` | `per-spec` | each spec's `review:` field decides whether you or the Foreman merges the code |
| `default_review` / `default_budget` | `auto` / `15` | what an agent drafting a spec starts from; the config also carries budget defaults by kind of change |
| `max_parallel_workers` | `5` | all agents share one usage window |
| `ship_channels`, `ship_expect_<channel>` | unset | what a merge ships to, and the configuration each channel's artifact must carry before it is published |

The two gates are independent, so you choose where a human is required: at
the spec, at the code, at both, or at neither. With `spec_gate: auto` and
`code_gate: auto` a change runs from issue to merge between agents with no
human gate at all; the reviewer agent still reviews every spec and every PR.
The Foreman labels each PR `human-review` or `auto-merge`, so
`gh pr list --label human-review` is always your to-do list. Whatever the
gates say, a spec with open questions, or anything on the config's "always
escalates" list, comes to you.

The by-kind default exists because a single "the owner merges every spec"
gate stalled a real project for a month with 28 spec PRs unread, most of them
bug fixes nobody needed to weigh in on. Specs for product changes are worth
your time; specs for clear bug fixes are not, and under `by-kind` they do not
wait for it.

**Shipping is a step, not a side effect.** Merging an implementation PR
publishes nothing. The Foreman runs `scripts/ship.sh` right after each merge;
it migrates production and asserts the migration applied, builds each channel
from a clean worktree at `origin/main`, refuses to publish an artifact that
does not carry that channel's configuration, records the shipped commit, and
only then announces. The patrol alerts when `main` is ahead of the last
shipped commit. Details: [docs/OPERATIONS.md](docs/OPERATIONS.md).

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

- Merge whatever is labelled `human-review`: by default, the specs for
  features, architecture and product-impacting change (the Foreman merges
  plain bug-fix specs), and the code PRs whose spec says `review: human`.
- Confirm the device smoke when the Foreman asks, if the project ships native
  builds.
- Answer escalations: one specific question each.
- Review the proposal queue when the count bothers you.
- **About once a month, run `claude auth login` on the machine.** The login
  behind Remote Control expires and cannot be renewed from the phone. The
  patrol warns 72 hours ahead. See [docs/OPERATIONS.md](docs/OPERATIONS.md).

## Read this before building

**[docs/FINDINGS.md](docs/FINDINGS.md)** — what was wrong in the original design
and what is true but undocumented. It will save you a day.

**[docs/OPERATIONS.md](docs/OPERATIONS.md)** — the runbook: Remote Control
setup, the monthly login expiry, usage-limit pauses, restarting things, the
ship step, running two Foreman sessions at once.

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
- The human gates are enforced by the Foreman's instructions, not by GitHub.
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
