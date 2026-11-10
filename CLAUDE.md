# Software Factory — working agreements

This repo *is* a factory instance as well as the template for one. Changes here
go through the same flow they describe. If a convention is too annoying to
follow in this repo, that is evidence it is too annoying to ship.

## Ledger

GitHub Issues are intake; issue labels are state:

| Label | Meaning |
|---|---|
| `status:triage` | Filed, not yet assessed |
| `status:needs-spec` | Agreed real; needs `docs/specs/<name>.md` before dispatch |
| `status:ready` | Spec linked, no open questions, deps merged — dispatchable |
| `status:in-progress` | Worker assigned, PR open |
| `status:blocked` | Open question or unmerged dependency; reason in a comment |

Exactly one `status:` label per issue. The Foreman turns `status:ready` issues
into tasks. Flow is one-way — never sync backwards.

## Specs

Proposed in their own PR containing only the spec. Merging the spec PR is the
approval; only then does the issue become `status:ready`.

`review:` and `budget:` are the operator's decision, never guessed.
Acceptance criteria must be mechanically checkable — they become the worker's
`/goal` verbatim.

The template has two parts. Part 1 is for the operator: product and system
design, no code identifiers; it is what merging approves. Part 2 is the
worker's implementation plan. Where they disagree, Part 1 wins.

## Pull requests

Implementation PRs link the spec and contain `Closes #<n>`.

Title prefixes are load-bearing: the patrol reads them to decide what needs a
reviewer.

| Prefix | What it is | Who reviews |
|---|---|---|
| `spec:` | a spec, and nothing else | the operator; merging is the approval |
| `qa:` | QA records and evidence | the operator |
| `docs:` | documentation, approved proposals, config | the operator |
| anything else | implementation | the reviewer agent, then per `review:` |

## Standing rules

`docs/factory-config.md` holds the factory's standing rules: landing policy,
worker cap, data policy, decision boundaries. It is the operator's file. A
rule the operator states in conversation is written there the same day; a rule
that exists only in a session's context does not exist.

## No secrets, ever

This repo is intended to be publishable. Nothing account-specific belongs in
it: no API keys, no usernames, no absolute home paths, no hostnames, no ntfy
topics, no project names from other repos. Use the template placeholders
(`__HOME__`, `__PREFIX__`, `__PROJECT__`, `__NTFY_TOPIC__`).

Before committing, run:

```
grep -rniE '<your-username>|/Users/[a-z]|ntfy\.sh/[a-z-]+' . --exclude-dir=.git
```

## Instructions change through proposals

`AGENTS.md` (golden principles), `docs/review-checklist.md`, the
`qa-procedure` skill, `docs/specs/_TEMPLATE.md` and `docs/factory-config.md`
are the factory's instructions. None of them is edited on an agent's own
judgement. Lessons are routed by the Foreman into `docs/proposals.md`, each
line tagged with its target, and the operator approves line by line. See
`docs/FEEDBACK.md`.

Only a human edits `AGENTS.md`.
