# Factory config

The standing rules for this project's factory. The Foreman reads this file on
every cold start and before every dispatch and merge; the patrol reads the
settings block. **If a rule is not written here, it does not exist.** A rule
that lives only in the Foreman's conversation is lost at the next restart or
compaction, silently, and the factory reverts to the defaults below without
telling anyone.

This file is the operator's. Agents propose changes through
[proposals.md](proposals.md) (target `[config]`); they do not edit it on their
own judgement. The one exception is recording a rule the operator has just
stated, described under "Standing rules".

## Settings

One `key: value` per line. The patrol parses this block, so keep the format.

```
spec_gate: human
code_gate: per-spec
default_review: human
default_budget: 15
max_parallel_workers: 5
```

### The two human gates

A change passes two points where a human may be required: when its **spec**
is approved, and when its **code** is merged. Each gate is set separately.

| Key | Values | Meaning |
|---|---|---|
| `spec_gate` | `human` \| `auto` | Who approves a spec PR. `human`: the operator reads Part 1 and merges it. `auto`: the Foreman dispatches the reviewer agent against the spec PR and merges it on `ai-approved`. |
| `code_gate` | `per-spec` \| `human` \| `auto` | Who merges an implementation PR after the reviewer agent has approved it. `per-spec`: the spec's own `review:` field decides, change by change. `human`: always the operator. `auto`: always the Foreman. |
| `default_review` | `human` \| `auto` | What an agent drafting a spec writes in its `review:` field. Only matters under `code_gate: per-spec`. |

Which gives every combination:

| `spec_gate` | `code_gate` | You are needed for |
|---|---|---|
| `human` | `human` | every spec and every merge |
| `human` | `per-spec` | every spec, and the merges whose spec says `review: human` **(shipped default)** |
| `human` | `auto` | every spec; approved code lands without you |
| `auto` | `human` | every merge; specs are agent-reviewed |
| `auto` | `per-spec` | only merges whose spec says `review: human` |
| `auto` | `auto` | nothing: issue to merge runs end to end between agents |

The reviewer agent reviews every implementation PR under every setting. The
gates decide where a human is *also* required, never whether review happens.

**Two things always get a human, whatever the gates say:**

- a spec with anything under "Open questions";
- anything on the "Always escalates" list below.

**The Foreman marks every PR with who it is waiting on**, so you can see it
from a phone without opening the spec: `human-review` (it will not land
until you merge it) or `auto-merge` (the Foreman will land it once the
reviewer approves). `gh pr list --label human-review` is your to-do list.

The shipped defaults keep you in front of every spec and every merge a spec
marks `review: human`. They are the right start for a codebase with users,
and for any factory whose reviewer has not yet earned trust. Loosen a gate
here, in writing, when it has.

### Other settings

| Key | Values | Meaning |
|---|---|---|
| `default_budget` | integer | What an agent drafting a spec writes in `budget:`: the iteration cap that stops a grinding worker. |
| `max_parallel_workers` | integer | Hard cap on workers in flight. The Foreman queues beyond it; the patrol alerts if `status:in-progress` issues exceed it. All agents share one subscription's usage window, and exhausting it stops the whole factory until it resets. |

## Decision boundaries

What agents may decide for themselves and what goes to the operator. The
Foreman's escalation triage starts from this list. Filled in during
onboarding and extended whenever the operator answers the same kind of
question a second time.

**Agents decide:**

- Sequencing and priority among `status:ready` issues.
- Interpretation questions the spec already answers.
- Splitting an issue into child issues that stay within its approved spec.

**Always escalates:**

- A product decision or trade-off the spec is silent on.
- Anything that could lose or rewrite existing data: a migration, backfill,
  reset or deletion.
- Anything that spends money, changes credentials, or reaches a system
  outside this repository.
- Changing a spec's approved Part 1.

## Standing rules

Rules the operator has given that are not captured by a setting above. One
line each, imperative, dated, in the operator's own words where possible.

- (none yet)

**Recording a verbal rule.** When the operator tells the Foreman something
that is meant to hold from now on ("always…", "never…", "from now on…",
"stop asking me about…"), the Foreman:

1. follows it immediately;
2. opens a PR titled `docs: standing rule — <summary>` adding the line here,
   quoting the operator's message as the evidence; and
3. tells the operator the PR exists.

The rule is in force from the moment it was given. The PR is what makes it
survive the session. If the Foreman is ever unsure whether a remark was a
standing rule or a one-off, it asks once.
