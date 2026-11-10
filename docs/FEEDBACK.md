# The feedback loop

A fleet of agents that repeats its mistakes is not a factory. This is the
mechanism that turns each mistake into a permanent change in behaviour, and
keeps a human in front of every such change.

## Where lessons come from

| Source | Why it matters |
|---|---|
| The operator's PR comments | A human spending attention on this specific code. The highest-value signal in the system. |
| Escalation answers | A decision made once should not need making twice. |
| Reviewer findings | Especially ones the worker argued with, or that recur across PRs. |
| The worker's reflection | What surprised it; what would have made the task easier. |
| Bugs QA finds | Each one escaped something. What should have caught it? |

## Route by what the lesson is, not where it came from

A lesson's source says nothing about where it belongs. An operator comment
may be a mechanical check; a QA bug may expose a missing principle. Ask what
kind of thing was learned.

**Golden principles** are durable judgement: architectural rules, invariants,
the project's philosophy of scope. They cannot be enforced mechanically,
which is why they must be few and exact. They go to `AGENTS.md`.

**Tactical hardening** is mechanical and enforceable. It goes to the artifact
that enforces it, so that the lesson does not depend on any agent remembering
it:

| What was learned | Target | Tag |
|---|---|---|
| A rule of judgement an agent got wrong | `AGENTS.md` | `[AGENTS.md]` |
| A class of bug that reached review or `main` | a new test | `[test]` |
| A finding the reviewer missed, or keeps making | `docs/review-checklist.md` | `[review-checklist]` |
| Something QA could not see or reach | the `qa-procedure` skill | `[qa-procedure]` |
| A spec ambiguity that has recurred | `docs/specs/_TEMPLATE.md` | `[spec-template]` |
| A decision the operator has now made twice | `docs/factory-config.md` | `[config]` |

When in doubt, prefer the most mechanical target that would have worked. A
test beats a checklist item, a checklist item beats a line in `AGENTS.md`.
`AGENTS.md` is loaded into every task and every line in it dilutes the rest.

Two things are not proposals:

- **A description of what happened.** If the line would not have changed what
  an agent did, leave it out.
- **A one-off.** A problem with one spec is fixed in that spec. It becomes a
  `[spec-template]` proposal when it recurs.

## One queue

Everything goes to [proposals.md](proposals.md): one bullet per proposal,
tagged with its target, with one line of evidence. One file, so there is one
place to look and one number to report.

The Foreman is the only writer. Workers put their reflection in a PR comment,
the reviewer flags patterns in its summary, QA records why each bug escaped
in its issue; the Foreman's retro reads all of them and does the routing. A
PR that only appends to `## Pending` changes nobody's behaviour, so the
Foreman merges that one itself.

**The queue must not rot.** A problem written into a queue is not a problem
raised: the reference deployment's Foreman recorded a broken reviewer in its
first retro, and it stayed broken for five weeks. So the Foreman states the
pending count in every status answer, and says how old the oldest entry is
when it passes two weeks.

## Approval and what follows

The operator reviews pending proposals with the Foreman and decides each line
separately: approve, reject (with a reason), or reword. Always line by line,
never as a batch. This gate is the reason the loop helps at all:
agent-written context files have been measured to slightly reduce success
while raising cost, and human-curated ones help.

The Foreman then opens one PR, `docs: apply approved proposals`, which:

- applies approved `[AGENTS.md]`, `[review-checklist]`, `[qa-procedure]`,
  `[spec-template]` and `[config]` edits to their targets, verbatim;
- for each approved `[test]` proposal, files an issue and adds a short spec
  for the test, so that merging the PR makes it a dispatchable task like any
  other;
- moves every decided line from `## Pending` to `## Decided`, with the reason
  for each rejection so it is not proposed again.

The operator merges that PR. It is never merged by an agent, under any
gate setting: it changes the instructions every later agent runs on.

`AGENTS.md` gets no special handling in the mechanics, only in the standard:
the Foreman writes the approved line and nothing else. No agent adds, rewords
or tidies anything in that file on its own judgement.

## Iteration zero

Onboarding a repository is this same loop run for the first time, with the
repository and the operator's head as the source of lessons instead of merged
PRs. The `onboard-repo` skill produces the first `AGENTS.md`, the first
`qa-procedure` and the first config as one PR that the operator approves line
by line. Nothing afterwards works differently; the batches just get smaller.

## Lessons about the factory itself

Some lessons are not about the project. They are about the Foreman role, an
agent definition, the patrol or this document. Those artifacts are installed
from the factory template repository, not from the project. Record the lesson
in the project's queue with the closest tag and the words "upstream:" at the
start of the evidence line, so the operator can carry it to the template.
