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
GitHub: issue → spec PR → code PR → AI review → merge
```

## The fleet

| Process | Lifecycle | Started by | Runs from | Model |
|---|---|---|---|---|
| RC server | always on | launchd | one per project dir | n/a |
| Foreman | always on | launchd → tmux | project root | strongest |
| Workers | per task | Foreman | own worktree | mid-tier |
| Patrol | every 15 min | launchd | project root | cheapest |
| Reviewer | per PR | GitHub Actions | GitHub runner | strongest |

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
the launchd jobs, add the project to `boot.sh`, add `ANTHROPIC_API_KEY` as a
repo secret, and create the `status:` labels.

## How work flows

```
issue (status:triage)
  → status:needs-spec
  → spec PR (docs/specs/<name>.md)   ← you review; merging IS the approval
  → status:ready
  → Foreman creates a task, dispatches a worker into its own worktree
  → worker opens a PR, "Closes #n"
  → AI reviewer comments; worker addresses until approved
  → review: human → you merge   |   review: auto → auto-merge when green
  → issue closes
```

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
