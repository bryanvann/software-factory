# <Feature name>

review: human          # human | auto  — who approves the PR
budget: 15             # max worker iterations before forced stop

## Problem

What is broken or missing, and who feels it. Written so someone with no context
on this conversation understands why this work exists.

## Requirements

Numbered, testable statements. Each one should be something a reviewer can point
at the diff and say yes or no to.

1.
2.

## Technical design

The approach, and the contract. **If this work touches more than one component,
pin the interface here** — the exact shape of the API, the schema, the event, the
file format. Workers do not talk to each other; this section is how they agree.

Name the files you expect to change. If you don't know them, that's a signal the
spec isn't ready.

## Acceptance criteria

The finish line. The Foreman turns these directly into the worker's `/goal`, so
they must be **mechanically checkable** — a command that exits zero, a test that
passes, an observable behaviour. Not "works well" or "is robust".

- [ ]
- [ ]

## Non-goals

What this deliberately does not do. This is the scope-creep fence: anything a
worker thinks is missing, but which appears here, stays out of the diff.

-

## Open questions

Anything unresolved. **A spec with open questions is not dispatchable** — resolve
them or move them to non-goals first. Listed here so they're visible during
review rather than discovered by a blocked worker.

-
