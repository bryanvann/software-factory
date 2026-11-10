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
landing: per-spec
max_parallel_workers: 5
default_review: human
default_budget: 15
data_policy: preserve
```

| Key | Values | Meaning |
|---|---|---|
| `landing` | `per-spec` \| `autonomous` | Who merges an implementation PR once the reviewer has labelled it `ai-approved`. `per-spec`: the spec's `review:` field is honored: `human` waits for the operator, `auto` is merged by the Foreman. `autonomous`: the Foreman merges every approved PR, whatever the spec says. |
| `max_parallel_workers` | integer | Hard cap on workers in flight. The Foreman queues beyond it; the patrol alerts if `status:in-progress` issues exceed it. All agents share one subscription's usage window, and exhausting it stops the whole factory until it resets. |
| `default_review` | `human` \| `auto` | What an agent drafting a spec writes in `review:`. The operator can change it per spec in the spec PR. |
| `default_budget` | integer | What an agent drafting a spec writes in `budget:`. |
| `data_policy` | `preserve` \| `regenerable` | `preserve`: all existing data is treated as precious; any change that could lose or rewrite it (migration, backfill, reset, deletion) escalates. `regenerable`: data may be dropped and rebuilt without asking, **except** what is listed under "Protected data". |

### The defaults are the safe ones

The shipped values keep a human in front of every merge that a spec marks
`review: human`, and in front of anything that could lose data. They are the
right starting point for a codebase with users, and deliberately conservative
for one without.

A deployment may override them. The reference deployment, a pre-release app
with no users beyond its operator, ran with `landing: autonomous` and
`data_policy: regenerable`: the operator approved intent by merging the spec
and did not want to be in the loop again. That is a legitimate setting. It is
also one that must be chosen in writing, here, by the operator, and revisited
when the first real user arrives.

Specs are reviewed by the operator under every setting. `landing` only
governs implementation PRs.

## Protected data

Used when `data_policy: regenerable`. List what must survive anyway, in the
operator's words. Anything on this list escalates exactly as it would under
`preserve`.

- (none listed)

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
- Anything touching data covered by `data_policy` or "Protected data".
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
