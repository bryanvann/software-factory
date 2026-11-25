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
spec_gate: by-kind
code_gate: per-spec
default_review: auto
default_budget: 15
max_parallel_workers: 5
spec_skip_labels: product-doc-drift
```

### The two human gates

A change passes two points where a human may be required: when its **spec**
is approved, and when its **code** is merged. Each gate is set separately.

| Key | Values | Meaning |
|---|---|---|
| `spec_gate` | `by-kind` \| `human` \| `auto` | Who approves a spec PR. `by-kind`: depends on what the spec is (next section). `human`: the operator reads Part 1 and merges every one. `auto`: the Foreman dispatches the reviewer agent against the spec PR and merges it on `ai-approved`. |
| `code_gate` | `per-spec` \| `human` \| `auto` | Who merges an implementation PR after the reviewer agent has approved it. `per-spec`: the spec's own `review:` field decides, change by change. `human`: always the operator. `auto`: always the Foreman. |
| `default_review` | `human` \| `auto` | What an agent drafting a spec writes in its `review:` field. Only matters under `code_gate: per-spec`. |

Which gives every combination:

| `spec_gate` | `code_gate` | You are needed for |
|---|---|---|
| `human` | `human` | every spec and every merge |
| `human` | `per-spec` | every spec, and the merges whose spec says `review: human` |
| `human` | `auto` | every spec; approved code lands without you |
| `by-kind` | `per-spec` | specs for features, architecture and product-impacting change, and the merges whose spec says `review: human` **(shipped default)** |
| `by-kind` | `auto` | those specs only; all approved code lands without you |
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

The shipped defaults keep you in front of every spec that changes what the
product does, and every merge a spec marks `review: human`; plain bug-fix
specs are the Foreman's. A single "the operator merges every spec" gate
stalled one factory for a month with 28 spec PRs unread, most of them bug
fixes nobody needed to weigh in on. Set `spec_gate: human` here, in writing,
if you want every spec regardless; loosen further when the reviewer has
earned it.

### Who merges a spec under `by-kind`

A spec is written for every change, because it is the worker's goal and the
reviewer's oracle. Who merges its PR depends on what it is:

| The spec is | Who merges |
|---|---|
| a new feature, a big architectural choice, a deviation that changes what the product does or looks like, anything with open questions, anything with an irreversible production-data step | the operator (or the driver named below for that kind of change) |
| a plain bug fix whose approach is clear and obvious | the Foreman, after checking Part 1 is complete, "Open questions" is "None." and the PR merges cleanly |
| a change a second configured driver owns (`driver:` in the spec header) | that driver's session, on their own say-so; a technical question inside it goes to the operator as one question and never blocks the merge |

Spec PRs say `Refs #<n>`, never `Closes #<n>`. Merging a spec is approval,
not a fix; `Closes` on a spec PR closes an issue nobody has fixed.

Bugs never wait on a human for their spec: the patrol lists triage and
needs-spec issues with no spec PR, the Foreman dispatches a spec writer, and
the Foreman merges the result when it is a plain bug fix. `spec_skip_labels`
names labels whose issues are left out of that list: product-design work
and doc-drift decisions are decided on the issue before anyone specs them.
Space-separated.

**Drivers.** Who drives which kind of change. Filled in at onboarding.

- Operator: <name or handle>. Technical and infrastructure decisions; merges
  specs for features and architecture.
- Product driver (optional): <name or handle>. Designs product changes from
  their own sessions, merges the specs they drive (`driver: <handle>`), never
  sees code, PRs or logs. Delete this line if there is no second driver.

### Other settings

| Key | Values | Meaning |
|---|---|---|
| `default_budget` | integer | What an agent drafting a spec writes in `budget:` when none of the kinds below fits: the iteration cap that stops a grinding worker. |
| `max_parallel_workers` | integer | Hard cap on workers in flight. The Foreman queues beyond it; the patrol alerts if `status:in-progress` issues exceed it. All agents share one subscription's usage window, and exhausting it stops the whole factory until it resets. |
| `spec_skip_labels` | labels | Issues carrying any of these labels are not offered as "Needs a spec". |

**Budget defaults by kind of change.** `budget:` is set by the driver, never
by a worker. An agent drafting a spec writes the default for the kind and
says so in the PR body; the driver changes it when they merge.

| Kind of change | `budget:` |
|---|---|
| one screen: copy, a visual change, one control | 3 |
| a flow across several screens | 6 |
| anything touching data, sync or storage | 10 |

## Ship step

What a merge to the default branch publishes, and what each published
artifact must carry. `scripts/ship.sh` reads this block; the commands it
runs are the `ship_*` functions at the top of that script, filled in at
onboarding. Leave the block empty if a merge publishes nothing.

```
ship_channels:
ship_skip_paths: docs/
```

| Key | Meaning |
|---|---|
| `ship_channels` | Space-separated channel names, in publish order, e.g. `development preview production`. Empty: the ship step refuses to run. |
| `ship_expect_<channel>` | One line per channel: the configuration its artifact must carry, exactly as `ship_artifact_config` prints it (for example the backend host, or several values space-separated and sorted). The ship step refuses to publish a channel whose artifact prints anything else, or which has no line here. |
| `ship_skip_paths` | Path prefixes; a merge that changes only files under these advances the shipped stamp without a publish. |

**Migrations.** <Does the project have a production migration step? Which
tool, and does it read the folder git tracks or a different one? If
different, `ship_prepare_worktree` mirrors the tracked folder into it; write
that convention here so it is not rediscovered.>

**Device-build smoke.** <For projects with native builds: the two-minute
smoke on a real device that must pass before a new build is offered to
testers, as numbered steps, and where the result is recorded.> A new build is
never offered on "it built".

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
