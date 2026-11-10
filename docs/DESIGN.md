<!--
The design document. It began as the original plan and has been revised to
match what was actually built and run. Where the original was wrong, the
correction is here and the story of how it was found is in docs/FINDINGS.md.
The reasoning is original; the mechanics are current.
-->

# Minimalist Software Factory on a Mac Studio

Goal: fire off a spec, have it completed without babysitting, get pushed only on escalations, review PRs on a per-feature basis, and have the whole thing survive restarts. Runs on native Claude Code plus about 500 lines of shell glue. No Gastown, no third-party orchestrator, no Agent Teams (see "What we're deliberately not using").

Verdict: every requirement is achievable today. Mobile session initiation and push notifications are native features you turn on. The patrol, escalation fallback, and per-feature merge policy need small glue. One rough edge: permission modes can't be changed from the phone, so workers launch in their final mode.

---

## Architecture at a glance

```
Phone (Claude app, Code tab)
        │  Remote Control bridge (outbound-only from Mac, via Anthropic API)
        ▼
Mac Studio (always on; one factory per macOS account)
├── launchd: one claude remote-control spawner per project  ← phone can start new sessions
├── Foreman session (persistent, tmux, one per active project)
├── Worker sessions (spawned by Foreman, worktree-isolated, /goal-driven)
├── Shared task list on disk (~/.claude/tasks/<project>/)   ← survives restarts
├── Patrol (launchd, every 15 min, ephemeral)   ← watcher and trigger
└── Hooks: quality gates + ntfy escalation fallback
        │
        ▼
GitHub: PR per task → reviewer agent (verdict label) ↔ worker comment loop
        → Foreman merges if spec says so, else waits for you
```

---

## 1. The layer map: what lives where

**Machine (once, admin).** `sudo pmset -a sleep 0 disablesleep 1` so the Mac never sleeps. That's it; everything else is per-account.

**macOS account = one factory.** You run work and personal as separate Mac accounts; keep that. Each account is a complete, independent factory:
- Its own Claude login (work account vs personal account), which means its own Remote Control registration, its own push notifications, and its own rate limit pool.
- Its own LaunchAgents (`~/Library/LaunchAgents/`): an RC spawner and a patrol per project, and the boot recovery script.
- Its own tmux server and sessions.
- Its own `~/.claude`: the agent definitions (`~/.claude/agents/{worker,reviewer,qa}.md`), the Foreman role file, the `onboard-repo` skill, and the gate hooks that apply to every repo.

macOS keeps background processes running under fast user switching, so both factories run at once. Nothing needs to be duplicated *within* an account; nothing is shared *across* accounts except pmset and the hardware.

**Repo.** Per project:
- `.claude/settings.json` with the shared task list ID
- `AGENTS.md` — golden principles (human-curated, see section 8)
- `docs/specs/` — the spec per feature
- `docs/factory-config.md` — standing rules: the two human gates, worker cap, decision boundaries
- `docs/proposals.md` and `docs/review-checklist.md` — the feedback loop's queue and one of its targets
- `.claude/skills/qa-procedure/` — how to bring up, drive and assert this app
- `.githooks/pre-commit` — the gate pyramid, with the project's own typecheck and test commands
- `.worktreeinclude` — which gitignored files (`.env` etc.) get copied into worktrees
- The `ai-approved` / `ai-changes-requested` / `status:` labels

Adding a repo to the factory = `install.sh --project`, then the `onboard-repo` skill (section 8). Everything else is inherited from the account layer.

**Worktree.** Nothing configured. Claude Code creates one automatically per worker (`isolation: worktree`), the worker gets its own branch and directory, and the worktree is destroyed after merge. Worktrees share the repo's config and `.claude`, so they inherit everything. Don't pre-create them, don't manage them.

## 2. Remote access from your phone (native)

Remote Control bridges the Claude app / claude.ai/code to sessions running on the Studio. Sessions run locally the whole time; the phone is a window. Requires Pro/Max with the interactive OAuth login.

- **Start new sessions from the phone:** one spawner per project, `claude remote-control --spawn same-dir --name <project>`, under launchd with the project as its working directory. The directory is the "environment" the phone shows; there is no directory picker. (`--spawn session`, the original choice, is single-session mode and fights `KeepAlive`.)
- **See and enter every session from the phone:** set `"remoteControlAtStartup": true` in `~/.claude/settings.json` so each interactive session registers at launch. That is what makes the Foreman, which is started by a boot script rather than from the phone, reachable. Session names drift with conversation content; identify the Foreman by its tmux session, not by the app's list.
- **Push notifications:** native with the Claude app on the same account. Claude pushes when a long task finishes or it needs a decision.
- **The login expires about monthly.** Remote Control rides on the claude.ai login, which lapses roughly a month after `claude auth login` with no warning. The patrol warns 72 hours ahead. Re-login needs hands on the machine, and spawners must be restarted afterwards. The one-year `claude setup-token` token cannot do Remote Control. See OPERATIONS.md.
- **Known gap:** permission modes can't be changed from the phone mid-session. Launch workers in their final mode (`acceptEdits` + tool allowlist) so it never matters.

Two one-time prompts cannot be answered by launchd and must be done by hand: Remote Control consent (per machine) and workspace trust (per directory). The plist is `launchd/rc-server.plist.template`.

(launchd is macOS's service manager, systemd + cron equivalent. A plist is the XML file declaring a job. `RunAtLoad` starts it at login, `KeepAlive` restarts it on crash. That pair is most of the restart-resilience story.)

## 3. Spec → task → worker flow

**Intake.** GitHub Issues are intake and the durable record; a `status:` label is each issue's state (`triage` → `needs-spec` → `ready` → `in-progress`, or `blocked`). Flow is one-way, issues to tasks.

**Specs.** `docs/specs/<feature>.md`, proposed in a PR of its own titled `spec: …`. Merging that PR is your approval and the only gate between an idea and a dispatched worker. The template has two parts. Part 1 is for you: what is wrong, what will change, how we will know, in product and system-design terms with no code identifiers. Part 2 is the worker's plan: root cause, requirements, pinned interfaces, mechanically checkable acceptance criteria. Two header fields are yours alone:

```
review: human | auto      # who approves the implementation PR
budget: <max iterations>  # kill criterion
```

**Task ledger.** Claude Code's native task system: tasks persist as JSON under `~/.claude/tasks/<list-id>/`, survive restarts, support dependencies. Shared list per repo:

```json
// .claude/settings.json
{ "env": { "CLAUDE_CODE_TASK_LIST_ID": "<project>" } }
```

You do not tell the Foreman to dispatch. Merging the spec PR is the signal: the patrol sees the merge, the Foreman moves the issue to `status:ready`, creates a task and dispatches. Adopt Beads later only if the backlog outgrows this (multi-machine, heavy cross-project grooming). Don't start there.

**Workers.** `~/.claude/agents/worker.md` (account level — same worker everywhere), a subagent definition with `isolation: worktree`, `background: true`, `permissionMode: acceptEdits`. It reads the issue and its spec, implements only what the spec asks, opens a PR containing `Closes #<n>`, and polls for the reviewer's verdict label, addressing comments until it is `ai-approved`. It never merges, never spawns its own reviewer, and never edits AGENTS.md. Blocked → label the issue `status:blocked`, say why, stop.

Workers are spawned by the Foreman as background subagents — Claude Code manages them; no tmux involved. At most `max_parallel_workers` run at once (default 5): they share one usage window.

## 4. The Foreman

One persistent interactive session per active project, running in tmux in the repo root. tmux exists solely to keep this session alive with no terminal attached and give the patrol a trivial liveness check; phone-spawned sessions and workers don't use it.

**Where its role is defined:** a markdown role file at the account level (e.g. `~/.claude/foreman.md`, or packaged as a `/foreman` command) so every project's Foreman behaves identically. The repo's CLAUDE.md and AGENTS.md supply project context on top. It is *not* a subagent definition — it's a normal session launched with the role as its **system prompt**, cold, by the boot script:

```bash
tmux new-session -d -s foreman-<project> -c $PROJECT_DIR \
  "claude --append-system-prompt \"$(cat ~/.claude/foreman.md)\" --model <strongest>"
```

A role passed as the first user message can be diluted or compacted away over a multi-day session; a system prompt cannot.

**The role, in short:**
- Never writes code. Turns `status:ready` issues into tasks on the shared list; dispatches one worker per task, deriving each worker's /goal from the spec's acceptance criteria plus the standard finish line (gates green, PR open, reviewer approved) and its iteration cap from the spec's budget field.
- Answers your status questions with global state.
- Dispatches a reviewer for each implementation PR, lands approved PRs according to the configured gates, and dispatches QA on request.
- Handles worker escalations: decides what it can, escalates to you what it can't (push notification with the specific question).
- Reads its standing rules from `docs/factory-config.md` at start and before each dispatch and merge, and writes any rule you give it verbally into that file. Its context is working memory, not storage.
- Owns the proposal queue (section 8); applies only what you approve, verbatim, AGENTS.md included.

You never type /goal or /loop yourself. Acceptance criteria in the spec are your entire contribution to the goal; the Foreman does the wiring. (/goal = declarative finish line checked by an evaluator every time the agent tries to stop; /loop = imperative repeat-until, occasionally useful *inside* a worker for grindy convergence like burning down lint errors. /goal is the lifecycle mechanism; /loop is incidental.)

## 5. Keeping things moving, and escalating when they can't

The blocked-on-human problem is mostly *prevented*, not caught:

0. **Permissions config.** Workers launch in `acceptEdits` with a pre-approved tool allowlist, so approval prompts mostly never fire. What still fires surfaces as a push notification (a waiting worker pings you rather than sitting silently).
1. **/goal with deterministic done criteria** kills "stopped at 80%." The evaluator rejects the stop until the finish line is met or the cap hits.
2. **Iteration caps + forced reflection.** Before each retry the worker answers: what failed, what specific change fixes it, am I repeating myself. Three stuck iterations on the same error → kill, mark blocked, hand the reflection log to the Foreman. (Highest-leverage anti-stuck mechanism in every practitioner report.)
3. **The patrol** catches "wedged silently" and is also what makes the factory self-starting. Ephemeral: launchd fires it every 15 minutes, it runs one pass and exits. Deterministic-first: everything below is shell, and a model (the cheapest) is called only to judge a task that looks stalled, so a healthy factory costs zero tokens per patrol.
   - Restarts a dead Foreman; checks Remote Control spawner liveness and login expiry, 72 hours ahead. Alerts go to ntfy, once per condition.
   - Nudges the Foreman (`tmux send-keys`) with `status:ready` issues, implementation PRs with no verdict label, and spec PRs merged since the last pass. Nothing else triggers a persistent session.
   - Detects a usage-limit 429, pauses until the reset, then nudges once to resume.
   - Alerts when in-progress issues exceed the worker cap.
   - Backs off to hourly when nothing is in flight, and can be paused entirely by telling the Foreman.

**Escalation to your phone, two channels:** native Remote Control push from the Foreman (primary), plus a task-blocked hook posting to ntfy.sh as a bridge-independent fallback: `curl -d "ESCALATION: $TASK - $REASON" ntfy.sh/${NTFY_TOPIC}`. Either way: open the Claude app, tap the Foreman or the blocked worker, answer.

## 6. PR review loop with per-feature merge policy

The reviewer is a local agent, dispatched by the Foreman into its own worktree when a worker reports its PR open. It is never spawned by the worker. (The original design put the reviewer in a GitHub Action. That path never produced a review; see FINDINGS.md, "Review", and REVIEW.md for the optional Action that remains.)

- **Reviewer:** `agents/reviewer.md`. Separate context from the writer, which is the point (~75% useful findings for a separate reviewer vs <50% for self-review). It re-runs the gates, reproduces the spec's acceptance criteria including device-level ones, and posts inline comments to the PR, which is the durable record.
- **Verdict is a label,** `ai-approved` or `ai-changes-requested`. All agents share one GitHub account and GitHub rejects self-approval, so a formal approval is impossible on this path.
- **The settle-down loop:** driven by the worker (its /goal includes "reviewer approved"): poll `gh pr view --json labels`, address comments, push, ask the Foreman for re-review, repeat. The patrol backstops it by listing implementation PRs with no verdict label.
- **Two human gates, set independently** in `docs/factory-config.md`:
  - `spec_gate: human | auto` — who approves a spec. `auto` sends the spec PR to the reviewer agent and the Foreman merges it on approval.
  - `code_gate: per-spec | human | auto` — who merges approved code. `per-spec` defers to each spec's `review:` field.
  - Both `auto` is a fully automated run from issue to merge. The shipped default is `human` / `per-spec`. A spec with open questions, or a change on the "always escalates" list, gets a human regardless.
  - The Foreman labels each PR `human-review` or `auto-merge` so you can see which it is. Nothing acts on those labels; the Foreman does the merging.
- `review: human` is a convention the Foreman follows, not something GitHub enforces. Enforcement needs branch protection plus a reviewer with a separate identity (REVIEW.md, Path B).
- Local gate pyramid regardless of policy, as pre-commit hooks so garbage never reaches the PR: secret scan → diff-size guard → the project's typecheck and tests.

## 7. Restart resilience

- launchd (`RunAtLoad` + `KeepAlive`) revives the RC spawners; the patrol runs on an interval.
- Tasks are on disk, work-in-progress is in git worktrees, specs are in the repo. Standing rules are in `docs/factory-config.md`. Nothing important lives only in a context window — including the Foreman's, which is the one that will tempt you.
- A boot script (third launchd job) recreates tmux and **cold-starts** each project's Foreman from its role file (not `--continue`, which resumes whatever session was most recent in the directory); the Foreman rebuilds from the ledger, and the patrol flags in_progress tasks whose workers died. Workers restart from task + spec + branch state, not memory.

## 8. The self-improvement loop

Full mechanism in FEEDBACK.md. In short:

- **Sources:** your PR comments, your escalation answers, reviewer findings, the worker's reflection (a PR comment), and the "why this escaped" note on each bug QA files.
- **Per merged PR:** the Foreman's retro routes each lesson by what it *is*. Golden principles (durable judgement) are proposed to `AGENTS.md`. Tactical hardening (mechanical, enforceable) is proposed to the artifact that enforces it: a new test, the review checklist, the `qa-procedure` skill, the spec template, or the factory config.
- **One queue:** `docs/proposals.md`, each line tagged with its target and carrying one line of evidence. The Foreman states the pending count in every status answer so the queue cannot silently rot.
- **Weekly-ish:** you review proposals with the Foreman and approve line by line. Approved instruction edits are applied in one PR you merge; approved test proposals become tasks.
- **Iteration zero:** onboarding a repo (the `onboard-repo` skill) is the same loop run for the first time: one PR with a draft `AGENTS.md`, a draft `qa-procedure` and the config, approved line by line before anything is dispatched.

The approval gate is not ceremony: ETH Zurich found agent-written context files provide no benefit and slightly reduce success while raising cost ~20%; human-curated ones help. Your PR comments and escalation answers are the highest-value signal in the system; the retro converts them into permanent behavior.

## 9. What we're deliberately not using

- **Agent Teams** (experimental multi-session coordination: shared task list, peer messaging, file locking). Built for work whose interfaces are still moving mid-flight — teammates negotiating contracts as they build. Your motion is pin-the-contract-in-the-spec-first, which makes tasks independent and the coordination fabric unnecessary. Also: no session resumption (conflicts with restart resilience), status lag, experimental. Revisit only for a feature you genuinely can't slice into independent tasks — and even then, prefer a design spike that produces a spec.
- **Gastown / orchestrator frameworks.** Philosophy conflict: throughput over correctness, lost work by design, yolo-mode defaults. You want the opposite bargain.
- **Beads on day one.** Native task system covers a single-project ledger. Upgrade trigger: backlog spanning machines/projects.

## 10. Custom code inventory

Everything else is config (plists, JSON, YAML, markdown). The actual code is about 500 lines of shell, plus a 240-line installer:

1. Patrol (~300 lines): the deterministic checks, the nudge, the usage-limit detector, and one headless `claude -p` call. It grew sixfold from the original estimate; every addition is a FINDINGS entry.
2. Boot recovery (~65 lines): recreate tmux, cold-start Foremen.
3. Hook scripts (~90 lines): pre-commit gate pyramid, secret scan, diff-size guard, ntfy escalation.

The real time cost is the non-code: AGENTS.md, the QA procedure, the spec template, and the Foreman's judgment. That's where the weeks go and where fire-and-forget is actually won. The `onboard-repo` skill exists to front-load it.

## 11. Build order

1. Machine + account prep: pmset, `./install.sh`, `remoteControlAtStartup`, verify the phone can spawn a session. (~1 hour)
2. One project: `./install.sh --project`, then the `onboard-repo` skill. Merge its PR only after reading every line.
3. One spec through one worker and one reviewer, by hand, watching. `review: human`.
4. Start the Foreman and the patrol. 2-3 tasks in parallel.
5. QA agent, once the `qa-procedure` skill has been run by a human at least once.
6. Retro loop. This is when it becomes a factory instead of a fleet. Keep both human gates at their defaults until the reviewer has earned trust.

## 12. Rough edges and honest limits

- **Mobile permission modes** can't change mid-session. Launch workers in final mode.
- **RC connection drops** reported overnight; the local process survives (launchd/tmux) and reconnects, but expect occasional spinner-and-reopen on the phone.
- **The monthly login expiry** is the one maintenance task that cannot be automated or done from the phone.
- **`review: human` is a convention, not enforcement.** The Foreman honors it; GitHub does not know about it. Enforcement needs branch protection and a reviewer with its own identity.
- **Rate limits are the real parallelism ceiling**, pooled per Claude account (one reason the two-account split is convenient). Sonnet for workers, Opus where it earns it.
- **Reliability compounds down:** ~95% per agent → ~77% across five chained steps; handoffs degrade context 39-70%. Keep the pipeline shallow: spec → worker → reviewer, nothing in between.
- **Cost:** multi-agent runs 2-5x tokens for equivalent output. The spec's `budget:` field and the parallel-worker cap are the controls; when the usage window is exhausted anyway, the patrol pauses the factory until it resets.
- **The bottleneck stays where you predicted: spec quality.** Vague specs don't fail loudly; they produce scope creep caught late by the diff guard and reviewer. Time in the spec is the cheapest quality gate in the system.
