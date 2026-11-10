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
| `[AGENTS.md]` | `AGENTS.md`: a golden principle | the Foreman applies it |
| `[test]` | a new test for a bug class that escaped | becomes an issue and a task |
| `[review-checklist]` | `docs/review-checklist.md` | the Foreman applies it |
| `[qa-procedure]` | `.claude/skills/qa-procedure/SKILL.md` | the Foreman applies it |
| `[spec-template]` | `docs/specs/_TEMPLATE.md` | the Foreman applies it |
| `[config]` | `docs/factory-config.md` | the Foreman applies it |

A proposal must be something that **would have changed behaviour**. A
description of what happened is noise; leave it out.

Count of pending proposals (the Foreman reports this in every status answer):

```
awk '/^## Pending/{p=1;next} /^## /{p=0} p&&/^- \[/{n++} END{print n+0}' docs/proposals.md
```

## Pending

- [spec-template] Under "Acceptance criteria": name the exact command that runs each test, and confirm that command actually selects it.
  Evidence: reference deployment — a criterion invoked a test file the default test command excludes, so it exited 1 whatever the code did.
- [spec-template] Under "Acceptance criteria": when a criterion says a test fails without the fix, say which test guards which change, and require the failure at run time, not at compile time.
  Evidence: reference deployment, two PRs — a revert "failed" only because it no longer compiled; another spec overclaimed which tests would fail and confused the reviewer.
- [spec-template] Under "Decisions already made": a requirement the operator adds in a spec-PR comment is binding and is written into the spec before it merges.
  Evidence: reference deployment — an operator rule given in a PR comment was applied to one of two code paths; the spec on main never mentioned it.
- [review-checklist] A test that asserts ordering must record its marker when the awaited work resolves, not when it is called; revert the `await` to check.
  Evidence: reference deployment — a call-time marker passed whether or not the production code awaited; found only on the third review round.
- [review-checklist] Evidence in a PR body must describe state the reviewer can still observe, or say that the environment was reset after capture.
  Evidence: reference deployment — a PR body claimed data existed that a later reset had wiped.

## Decided

Approved lines are moved here with the PR that applied them. Rejected lines
are moved here with the reason, and stay, so they are not proposed again.

- [AGENTS.md] Point the header at `docs/proposals.md` and state the approved-lines-only rule — approved 2026-11-10 by the operator in conversation, applied directly.

<!--
- [review-checklist] <line> — approved 2026-01-15, applied in #123
- [test] <line> — approved 2026-01-15, issue #124
- [config] <line> — rejected 2026-01-15: <the operator's reason>
-->
