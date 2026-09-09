<!--
Original design document, lightly sanitised.

Read docs/FINDINGS.md alongside this: several specifics below were found to be
wrong when built (notably `--spawn session`, launching the Foreman with the role
as a first user message, and the claim that no task tooling exists). The
*reasoning* here still holds; some of the mechanics do not.
-->

# Minimalist Software Factory on a Mac Studio

Goal: fire off a spec, have it completed without babysitting, get pushed only on escalations, review PRs on a per-feature basis, and have the whole thing survive restarts. Runs on native Claude Code plus ~100-150 lines of shell glue. No Gastown, no third-party orchestrator, no Agent Teams (see "What we're deliberately not using").

Verdict: every requirement is achievable today. Mobile session initiation and push notifications are native features you turn on. The patrol, escalation fallback, and per-feature merge policy need small glue. One rough edge: permission modes can't be changed from the phone, so workers launch in their final mode.

---

## Architecture at a glance

```
Phone (Claude app, Code tab)
        │  Remote Control bridge (outbound-only from Mac, via Anthropic API)
        ▼
Mac Studio (always on; one factory per macOS account)
├── launchd: claude remote-control server mode  ← phone can start new sessions
├── Foreman session (persistent, tmux, one per active project)
├── Worker sessions (spawned by Foreman, worktree-isolated, /goal-driven)
├── Shared task list on disk (.claude/tasks/)   ← survives restarts
├── Patrol (launchd, every 15 min, ephemeral)   ← anti-stuck watcher
└── Hooks: quality gates + ntfy escalation fallback
        │
        ▼
GitHub: PR per task → reviewer (claude-code-action) ↔ worker comment loop
        → auto-merge if spec says so, else waits for you
```

---

## 1. The layer map: what lives where

**Machine (once, admin).** `sudo pmset -a sleep 0 disablesleep 1` so the Mac never sleeps. That's it; everything else is per-account.

**macOS account = one factory.** You run work and personal as separate Mac accounts; keep that. Each account is a complete, independent factory:
- Its own Claude login (work account vs personal account), which means its own Remote Control registration, its own push notifications, and its own rate limit pool.
- Its own LaunchAgents (`~/Library/LaunchAgents/`): the RC server, the patrol, the boot recovery script.
- Its own tmux server and sessions.
- Its own `~/.claude`: global CLAUDE.md, the worker agent definition (`~/.claude/agents/worker.md`), the Foreman role file, shared skills, and the gate hooks that apply to every repo.

macOS keeps background processes running under fast user switching, so both factories run at once. Nothing needs to be duplicated *within* an account; nothing is shared *across* accounts except pmset and the hardware.

**Repo.** Per project:
- `.claude/settings.json` with the shared task list ID
- `AGENTS.md` (human-curated, see section 8)
- `docs/specs/` — the spec per feature
- Repo-specific skills and hooks (project test commands, domain checks)
- `.worktreeinclude` — which gitignored files (`.env` etc.) get copied into worktrees
- GitHub branch protection + the claude-code-action reviewer

Adding a repo to the factory = set a task list ID, write an AGENTS.md, wire branch protection. Everything else is inherited from the account layer.

**Worktree.** Nothing configured. Claude Code creates one automatically per worker (`isolation: worktree`), the worker gets its own branch and directory, and the worktree is destroyed after merge. Worktrees share the repo's config and `.claude`, so they inherit everything. Don't pre-create them, don't manage them.

## 2. Remote access from your phone (native)

Remote Control bridges the Claude app / claude.ai/code to sessions running on the Studio. Sessions run locally the whole time; the phone is a window. Requires Pro/Max with OAuth login, Claude Code v2.1.51+.

- **Start new sessions from the phone:** run server mode: `claude remote-control --spawn session --name studio`. The Code tab can then spawn brand-new sessions on the Studio. Runs under launchd (below) so it's always available.
- **See and enter every session from the phone:** enable "Remote Control by default" so each interactive process registers a remote session. Foreman and workers all appear in the Code tab; tap any of them to talk to it directly. No terminal needed.
- **Push notifications:** native with v2.1.110+ and the Claude app on the same account. Claude pushes when a long task finishes or it needs a decision; you can also request notifications explicitly in prompts.
- **Known gap:** permission modes can't be changed from the phone mid-session. Launch workers in their final mode (`acceptEdits` + tool allowlist) so it never matters.

launchd plist (`~/Library/LaunchAgents/com.${FACTORY_PREFIX}.claude-rc.plist`) — install one per macOS account:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.${FACTORY_PREFIX}.claude-rc</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string><string>-lc</string>
    <string>claude remote-control --spawn session --name studio</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
```

(launchd is macOS's service manager, systemd + cron equivalent. A plist is the XML file declaring a job. `launchctl load` once; `RunAtLoad` starts it at login, `KeepAlive` restarts it on crash. That pair is most of the restart-resilience story.)

## 3. Spec → task → worker flow

**Specs.** `docs/specs/<feature>.md`, written with Claude in a planning session: requirements, technical design, acceptance criteria, non-goals. Two required header fields:

```
review: human | auto      # who approves the PR
budget: <max iterations>  # kill criterion
```

**Task ledger.** Claude Code's native task system: tasks persist as JSON in `.claude/tasks/`, survive restarts, support dependencies. Shared list per repo:

```json
// .claude/settings.json
{ "env": { "CLAUDE_CODE_TASK_LIST_ID": "<project>" } }
```

When a spec is done, tell the Foreman: "Create tasks for docs/specs/feature-x.md and dispatch." Adopt Beads later only if the backlog outgrows this (multi-machine, heavy cross-project grooming). Don't start there.

**Workers.** `~/.claude/agents/worker.md` (account level — same worker everywhere):

```yaml
---
model: sonnet            # opus for complex tasks
isolation: worktree
background: true
permissionMode: acceptEdits
---
Read the task and its linked spec before writing code. Implement only what
the spec asks. Commit atomically. Open a PR when acceptance criteria pass.
After opening the PR, poll `gh pr view --json reviews,comments`; address
every reviewer comment and push until the reviewer approves.
If blocked, mark the task blocked with a note on what you tried, message
the Foreman, and stop. Never edit AGENTS.md.
```

Workers are spawned by the Foreman as background processes — Claude Code manages them; no tmux involved. With Remote Control by default on, each still shows up in your Code tab.

## 4. The Foreman

One persistent interactive session per active project, running in tmux in the repo root. tmux exists solely to keep this session alive with no terminal attached and give the patrol a trivial liveness check; phone-spawned sessions and workers don't use it.

**Where its role is defined:** a markdown role file at the account level (e.g. `~/.claude/foreman.md`, or packaged as a `/foreman` command) so every project's Foreman behaves identically. The repo's CLAUDE.md and AGENTS.md supply project context on top. It is *not* a subagent definition — it's a normal session launched with the role as its opening prompt:

```bash
tmux new-session -d -s foreman-<project> -c $PROJECT_DIR \
  "claude \"$(cat ~/.claude/foreman.md)\""
```

**The role, in short:**
- Never writes code. Decomposes specs into tasks on the shared list; dispatches one worker per task, deriving each worker's /goal from the spec's acceptance criteria plus the standard finish line (gates green, PR open, reviewer approved) and its iteration cap from the spec's budget field.
- Answers your status questions with global state.
- Handles worker escalations: decides what it can, escalates to you what it can't (push notification with the specific question).
- Owns the AGENTS.md/skills proposal queue (section 8); applies only what you approve.

You never type /goal or /loop yourself. Acceptance criteria in the spec are your entire contribution to the goal; the Foreman does the wiring. (/goal = declarative finish line checked by an evaluator every time the agent tries to stop; /loop = imperative repeat-until, occasionally useful *inside* a worker for grindy convergence like burning down lint errors. /goal is the lifecycle mechanism; /loop is incidental.)

## 5. Keeping things moving, and escalating when they can't

The blocked-on-human problem is mostly *prevented*, not caught:

0. **Permissions config.** Workers launch in `acceptEdits` with a pre-approved tool allowlist, so approval prompts mostly never fire. What still fires surfaces as a push notification (a waiting worker pings you rather than sitting silently).
1. **/goal with deterministic done criteria** kills "stopped at 80%." The evaluator rejects the stop until the finish line is met or the cap hits.
2. **Iteration caps + forced reflection.** Before each retry the worker answers: what failed, what specific change fixes it, am I repeating myself. Three stuck iterations on the same error → kill, mark blocked, hand the reflection log to the Foreman. (Highest-leverage anti-stuck mechanism in every practitioner report.)
3. **The patrol** catches "wedged silently." Ephemeral: launchd fires it every 15 minutes, it runs one headless pass and exits — nothing persistent, nothing to resume:

```
claude -p "Review the shared task list. For each in_progress task, verify
recent activity (commits/log). Nudge stalled workers. Verify the foreman
tmux session is alive; alert if not. Escalate any task blocked >30 min."
```

**Escalation to your phone, two channels:** native Remote Control push from the Foreman (primary), plus a task-blocked hook posting to ntfy.sh as a bridge-independent fallback: `curl -d "ESCALATION: $TASK - $REASON" ntfy.sh/${NTFY_TOPIC}`. Either way: open the Claude app, tap the Foreman or the blocked worker, answer.

## 6. PR review loop with per-feature merge policy

Reviewer runs in GitHub, not on the Mac: decoupled from the machine, triggers on every PR, comment thread is the durable record.

- **Reviewer:** claude-code-action on PR open/update, reviewing the diff against the spec linked in the PR description. Separate context from the writer — that's the point (~75% useful findings for a separate reviewer vs <50% for self-review).
- **The settle-down loop:** driven by the worker (its /goal includes "reviewer approved"): poll `gh pr view`, address comments, push, repeat.
- **Per-feature policy from the spec's `review:` field:**
  - `auto` → worker labels the PR `auto-merge`; branch protection requires the AI review check; `gh pr merge --auto --squash` lands it when green.
  - `human` → branch protection also requires your approval; Foreman notifies you it's ready.
- Local gate pyramid regardless of policy, as pre-commit/TaskCompleted hooks so garbage never reaches the PR: format → lint → typecheck → secret scan → tests → diff-size guard.

## 7. Restart resilience

- launchd (`RunAtLoad` + `KeepAlive`) revives the RC server and patrol per account.
- Tasks are on disk, work-in-progress is in git worktrees, specs are in the repo. Nothing important lives only in a context window.
- A boot script (third launchd job) recreates tmux and resumes each project's Foreman (`claude --resume`); the patrol re-dispatches any in_progress tasks whose workers died. Workers restart from task + spec + branch state, not memory.

## 8. The self-improvement loop

- **Per task:** worker writes REFLECTION.md — what surprised me, one AGENTS.md candidate, one prompt/spec improvement.
- **Per merged PR:** Foreman retro — mine reviewer comments, your PR comments, and escalations for generalizable lessons; append to `docs/agents-md-proposals.md`.
- **Weekly-ish:** you review proposals with the Foreman, approve line by line. Only approved lines enter AGENTS.md or become skills.

The approval gate is not ceremony: ETH Zurich found agent-written context files provide no benefit and slightly reduce success while raising cost ~20%; human-curated ones help. Your PR comments and escalation answers are the highest-value signal in the system; the retro converts them into permanent behavior. Missing verification checks become proposed SKILL.md files through the same door.

## 9. What we're deliberately not using

- **Agent Teams** (experimental multi-session coordination: shared task list, peer messaging, file locking). Built for work whose interfaces are still moving mid-flight — teammates negotiating contracts as they build. Your motion is pin-the-contract-in-the-spec-first, which makes tasks independent and the coordination fabric unnecessary. Also: no session resumption (conflicts with restart resilience), status lag, experimental. Revisit only for a feature you genuinely can't slice into independent tasks — and even then, prefer a design spike that produces a spec.
- **Gastown / orchestrator frameworks.** Philosophy conflict: throughput over correctness, lost work by design, yolo-mode defaults. You want the opposite bargain.
- **Beads on day one.** Native task system covers a single-project ledger. Upgrade trigger: backlog spanning machines/projects.

## 10. Custom code inventory

Everything else is config (plists, JSON, YAML, markdown). The actual code, ~100-150 lines of shell total:

1. Patrol wrapper (~20 lines): the headless `claude -p` call + tmux/task liveness checks.
2. Boot recovery (~30 lines): recreate tmux, resume Foremen, let patrol re-dispatch orphans.
3. Hook scripts: secret scan, diff-size guard (~5 lines), ntfy escalation (1 line).
4. Optional: harden the worker's PR-polling loop from instructions into a script the first time it misbehaves.

Claude writes all of this in an afternoon. The real time cost is the non-code: AGENTS.md, verification skills, the spec template, and the Foreman's judgment. That's where the weeks go and where fire-and-forget is actually won.

## 11. Build order

1. Machine + account prep: pmset, launchd RC server, verify phone can spawn a session. (~1 hour)
2. One project: task list ID, worker definition, hook pyramid. One spec through one worker with /goal. No Foreman yet.
3. Add the Foreman + dispatch flow. 2-3 tasks in parallel.
4. GitHub Action reviewer + merge policy. First few features `review: human` until the reviewer earns trust.
5. Patrol + ntfy fallback.
6. Retro loop. This is when it becomes a factory instead of a fleet.

## 12. Rough edges and honest limits

- **Mobile permission modes** can't change mid-session. Launch workers in final mode.
- **RC connection drops** reported overnight; the local process survives (launchd/tmux) and reconnects, but expect occasional spinner-and-reopen on the phone.
- **Rate limits are the real parallelism ceiling**, pooled per Claude account (one reason the two-account split is convenient). Sonnet for workers, Opus where it earns it.
- **Reliability compounds down:** ~95% per agent → ~77% across five chained steps; handoffs degrade context 39-70%. Keep the pipeline shallow: spec → worker → reviewer, nothing in between.
- **Cost:** multi-agent runs 2-5x tokens for equivalent output. Budget field + auto-pause at 85% are the caps.
- **The bottleneck stays where you predicted: spec quality.** Vague specs don't fail loudly; they produce scope creep caught late by the diff guard and reviewer. Time in the spec is the cheapest quality gate in the system.
