# Proposals

The factory's one queue of proposed changes to its own instructions. The
Foreman appends here during its retro; nothing below is in force until the
operator approves it, line by line. How lessons are routed, and what happens
after approval, is in [FEEDBACK.md](FEEDBACK.md).

Format: one proposal per bullet. The tag names the artifact that would change.
The first line is the edit itself, written as it would appear there. The
second line is the evidence, in one line.

```
- [target] The imperative line, exactly as it would read in the target.
  Evidence: PR #37 — reviewer flagged it twice; the worker's reflection agrees.
```

| Tag | Target artifact | On approval |
|---|---|---|
| `[AGENTS.md]` | `AGENTS.md`: a golden principle | the operator adds the line |
| `[test]` | a new test for a bug class that escaped | becomes an issue and a task |
| `[review-checklist]` | `docs/review-checklist.md` | the Foreman applies it |
| `[qa-procedure]` | `.claude/skills/qa-procedure/SKILL.md` | the Foreman applies it |
| `[spec-template]` | `docs/specs/_TEMPLATE.md` | the Foreman applies it |
| `[config]` | `docs/factory-config.md` | the Foreman applies it |

A proposal must be something that **would have changed behaviour**. A
description of what happened is noise; leave it out.

Count of pending proposals (the Foreman reports this in every status answer):

```
awk '/^## Pending

## Decided

Approved lines are moved here with the PR that applied them. Rejected lines
are moved here with the reason, and stay, so they are not proposed again.

<!--
- [review-checklist] <line> — approved 2026-01-15, applied in #123
- [AGENTS.md] <line> — approved 2026-01-15, awaiting the operator's edit
- [test] <line> — approved 2026-01-15, issue #124
- [config] <line> — rejected 2026-01-15: <the operator's reason>
-->
