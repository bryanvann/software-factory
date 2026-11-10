# <Short name, in plain words>

review: human          # human | auto  — who approves the implementation PR
budget: 15             # max worker iterations (attempt → gate failure → fix) before forced stop

<!--
`review:` and `budget:` are the operator's decision. An agent drafting this
spec fills in the defaults from docs/factory-config.md and says in the PR body
why it would or would not change them.

Two parts, two audiences.

PART 1 is for the human reviewer. Assume an expert system designer who knows
this system's architecture intimately: they chose the components, designed how
the pieces fit together, and know how it is supposed to work conceptually.
They have not read the code. So Part 1 is a product spec plus a system-design
note: it may and should talk about components, data flows, queues, storage,
permissions, state machines and trade-offs. It must not contain code-level
identifiers: no file paths, function or variable names, field, column or
table names, log-event names, flags, or anything lifted from the source. If a
sentence only makes sense to someone who has read the code, it belongs in
Part 2. Part 1 is the only part the reviewer reads. Merging the PR approves
Part 1.

PART 2 is for the worker that implements it. It can be as technical as needed:
root cause with file:line, interfaces, schema, exact commands. It must agree
with Part 1; where they differ, Part 1 is the intent and Part 2 is wrong.

Title the PR that proposes this file `spec: <short name> (#<issue>)`. The
patrol uses that prefix to tell spec PRs from implementation PRs.
-->

---

# Part 1 — For the reviewer

## What is wrong

Describe the problem as a user or operator experiences it, and what in the
system's design lets it happen, at the level of components and data flow.
Think "the second device never shows the record, because the upload step
sends an empty body to storage and still reports success", not "the blob
branch in the upload helper passes the wrong type to the client library".
Say who feels it and how often.

## Why it matters

One short paragraph: consequence if left alone, and what it blocks.

## What we will change

The fix as a design decision, in product and system-architecture terms:
which component changes, what new contract or flow results, what stays the
same. If there are alternatives, say which one we chose and why in a
sentence. If the change touches data that exists today (migration, backfill,
re-sync), say what happens to that data and what is preserved.

## How we will know it worked

The observable outcome a product person would accept as proof, in plain
words. Example: "after the fix, a record created on device A appears on
device B with its real contents, and every record uploaded before the fix has
been re-sent." The mechanical checks that enforce this live in Part 2.

## What we are deliberately not doing

Scope fence, in plain words. Related problems that stay out of this change,
with their issue numbers if they exist.

## Decisions already made

Product calls the reviewer made during spec review, and any standing rule from
`docs/factory-config.md` that this spec relies on. A requirement the reviewer
adds in a comment on the spec PR is binding and is written here before the PR
merges, so the spec on `main` matches what was approved. Blank if none.

## Open questions

Anything that still needs the reviewer's answer. **A spec with open questions
is not dispatchable.** Write "None." when there are none.

---

# Part 2 — Implementation plan

## Root cause

Where in the code the problem lives and why, with file:line references and
the evidence (log lines, assertions, test output) that proves this is the
cause and not a nearby hypothesis. For new work rather than a bug, describe
the current state of the code the change builds on.

## Requirements

Numbered, testable statements a reviewer can point at the diff and answer
yes or no to.

1.
2.

## Technical design

The approach and the contract. **If this touches more than one component,
pin the interface here** — exact API shape, schema, event, file format.
Workers never talk to each other; this section is how they agree. Name the
files expected to change. If you don't know them, the spec is not ready.

## Acceptance criteria

The finish line. The Foreman turns these directly into the worker's `/goal`,
so each must be **mechanically checkable**: a command that exits zero, a named
test that passes, an assertion on real state. Never "works correctly". Every
Part 1 "how we will know" claim must map to at least one criterion here.

Name the exact command that runs each test, and confirm that command actually
selects it. Where a criterion says a test fails without the fix, say which
test guards which change, and require the failure at run time, not at compile
time.

Anything that runs against the live app is brought up with the project's
`qa-procedure` skill; state the accounts, fixtures and starting state the
criterion assumes. Never require something an agent cannot do, such as
handling a physical device.

- [ ]
- [ ]

## Evidence the PR must include

What the worker pastes into the implementation PR body: the raw output of
the criteria above, and for anything user-visible a capture plus the state
assertion behind it.

## Non-goals (technical)

The code-level scope fence: files, modules and behaviours that must not
change, including anything another open issue owns.

## Dependencies

Issues or PRs that must merge first, and issues that depend on this one.
