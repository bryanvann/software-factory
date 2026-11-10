# Roles, skills, and repo rules

Three different mechanisms, routinely confused. Putting content in the wrong
one is the most common structural mistake in this design.

| | Where | Loaded when | Use for |
|---|---|---|---|
| **Repo rules** | `CLAUDE.md` in the repo | every session, automatically | conventions every agent must follow |
| **Role** | `roles/<name>.md` → `--append-system-prompt` | session launch | identity of a long-lived session |
| **Subagent** | `~/.claude/agents/<name>.md` | when spawned | agents another session spawns |
| **Skill** | `.claude/skills/<name>/SKILL.md` | on invocation | a repeatable procedure |

## Role vs subagent

A **subagent definition** has YAML frontmatter (`model`, `isolation`,
`background`, `permissionMode`) because *something else launches it*. The
worker is a subagent: the Foreman spawns it.

A **role** is for a session that drives itself. The Foreman is not a subagent —
it is a normal session launched with its role as a system prompt. If you find
yourself wanting frontmatter for a role, ask who is spawning it. If the answer
is "nobody, I start it," it is a role.

## Role vs skill

**Role = who you are. Skill = how to perform a procedure.**

A QA agent is a good test of this. Its *identity* ("you are a tester, not a
developer; report honestly including what you did not cover") is a role. Its
*method* (bring up two simulators, seed accounts, assert each hop, capture
evidence) is a skill, invocable by any session that needs to QA something.

Keeping them separate means the procedure survives independently of the agent,
and any session can run it. Here that is literal: `agents/qa.md` is the role
and is the same for every project; `.claude/skills/qa-procedure/` is the
method and is written per project against a fixed six-section contract. The
reviewer and the workers invoke the same skill when they need the running app.
See [QA-REFERENCE.md](QA-REFERENCE.md).

## What belongs in CLAUDE.md

Rules that apply to **every** agent in the repo: branch and merge conventions,
the ledger's state labels, what must appear in a PR body, which files are
human-only. If you put these in one agent's role or skill, only that agent
learns them — and a fresh session of a *different* agent will violate them.

A useful test: if a worker, a QA agent, and an ad-hoc session all need to know
it, it belongs in `CLAUDE.md`.

## What belongs in AGENTS.md

Curated, hard-won conventions specific to this codebase. **Human-curated only**
— agents propose to `docs/agents-md-proposals.md` and a human approves line by
line. Agent-written context files have been measured to slightly *reduce*
success while raising cost; the approval gate is load-bearing, not ceremony.
