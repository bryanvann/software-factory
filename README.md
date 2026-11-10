# Software Factory

A minimalist software factory on a Mac: fire off a spec, have it implemented
without babysitting, get pushed only on escalations, review PRs per feature, and
have the whole thing survive a reboot.

Native Claude Code plus roughly 150 lines of shell. No orchestrator framework,
no third-party agent runtime.

```
Phone (Claude app, Code tab)
        │  Remote Control (outbound-only from the Mac)
        ▼
Mac (always on; one factory per macOS account)
├── launchd: one RC server per project   ← phone picks a project by environment
├── Foreman (persistent, tmux, one per project, never writes code)
├── Workers (spawned by Foreman, worktree-isolated, one issue each)
├── Task list (~/.claude/tasks/<project>/, on disk, survives restarts)
├── Patrol (launchd, 15 min, deterministic-first)
└── Hooks: gate pyramid + escalation fallback
        │
        ▼
GitHub: issue → spec PR → code PR → reviewer agent (verdict label) → merge
```

## The fleet

| Process | Lifecycle | Started by | Runs from | Model |
|---|---|---|---|---|
| RC server | always on | launchd | one per project dir | n/a |
| Foreman | always on | launchd → tmux | project root | strongest |
| Workers | per task | Foreman | own worktree | mid-tier |
| Reviewer | per PR | Foreman | own worktree | strongest |
| QA | on request / schedule | Foreman | own worktree | strongest |
| Patrol | every 15 min | launchd | project root | cheapest |

Roles are **system prompts**, not first user messages. Skills are *procedures*
any session can invoke. `CLAUDE.md` holds rules every session must load. Keep
those three separate — see [docs/ROLES.md](docs/ROLES.md).

## Install

```sh
sudo pmset -a sleep 0 disablesleep 1      # machine level, once

./install.sh                              # account level
./install.sh --project ~/code/myproject   # per project
```

Then follow the printed steps: accept the one-time Remote Control consent, load
the launchd jobs, add the project to `boot.sh`, and create the labels.

## How work flows

```
QA finds a bug
  → files a GitHub issue immediately              status:triage
  → investigates to root cause
  → opens a SPEC PR: evidence, root cause at
    file:line, proposed fix, what it did not test status:needs-spec
  → YOU merge the spec PR  ← the one approval gate status:ready
  → Foreman creates a task, dispatches a worker
    into its own worktree
  → worker opens a PR containing "Closes #n"      status:in-progress
  → Foreman dispatches a reviewer (never the worker itself)
  → reviewer re-runs the gates, reproduces the
    acceptance criteria, posts inline findings,
    labels the PR ai-approved | ai-changes-requested
  → review: human → you merge
    review: auto   → the Foreman merges
  → issue closes on merge
```

You are in this loop exactly twice: merging the spec, and merging the code when
the spec says `review: human`. Everything else is driven by the patrol, which
nudges the Foreman about dispatchable issues and unreviewed PRs.

Two fields in each spec are yours alone, never guessed by an agent:

```
review: human | auto     # who approves the implementation PR
budget: 15               # iteration cap that stops a grinding worker
```

Specs are always human-reviewed. `review: auto` means "you already approved the
intent; you don't need to see the code."

## Read this before building

**[docs/FINDINGS.md](docs/FINDINGS.md)** — what was wrong in the original design
and what is true but undocumented. It will save you a day.

**[docs/REVIEW.md](docs/REVIEW.md)** — how review works: a local reviewer agent
that runs the code and signals its verdict with a label, and the optional
GitHub Action for when you need an off-machine review or a formal approval.

**[docs/DESIGN.md](docs/DESIGN.md)** — the reasoning: why per-project Foremen,
why no orchestrator framework, what is deliberately not used.

## Deliberately not used

- **Orchestrator frameworks** — throughput over correctness, lost work by
  design, yolo defaults. The opposite bargain from this one.
- **Multi-session agent teams** — built for work whose interfaces move
  mid-flight. If you pin contracts in the spec first, tasks are independent and
  the coordination fabric is unnecessary.
- **A dedicated backlog tool on day one** — GitHub Issues plus the native task
  list covers a single project. Upgrade when the backlog spans machines.

## Honest limits

- Mobile cannot change permission modes mid-session; launch workers in their
  final mode.
- `review: human` is enforced by convention, not by GitHub — branch protection
  is per-branch, not per-PR.
- Multi-agent runs cost several times the tokens of equivalent single-agent
  output. The `budget:` field is the cap.
- Reliability compounds downward across chained steps. Keep the pipeline
  shallow: spec → worker → reviewer.
- **Spec quality is the bottleneck.** Vague specs do not fail loudly; they
  produce scope creep caught late. Time in the spec is the cheapest quality
  gate in the system.
