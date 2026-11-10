# AGENTS.md — <project>

Golden principles for agents working in this repo. **Human-curated: every line
here was approved by the operator.** Agents propose to `docs/proposals.md`; the
operator approves line by line; the Foreman writes approved lines in verbatim.
No agent changes this file on its own judgement.

Every line here should be a rule an agent would otherwise get wrong. Delete
anything that stops earning its place — a bloated file costs tokens on every
task and dilutes the rules that matter.

## Project shape

<!-- What this is, what stack, and which directory is the dangerous one. -->

## Gates

Run before every commit:

```
<!-- typecheck command -->
<!-- test command -->
```

<!-- Do not enable a gate the repo cannot currently pass. Fix the baseline
     first, or every worker is blocked on failures it did not cause. -->

## Conventions

<!-- Fill in from real review comments as they accumulate. Do not let agents
     populate this section; that is what the proposals file is for. -->

## Hard rules

- Never commit secrets or `.env*` files.
- Never edit this file except to apply a line the operator approved.
