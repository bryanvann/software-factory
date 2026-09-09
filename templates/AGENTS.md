# AGENTS.md — <project>

Rules for agents working in this repo. **Human-curated: agents propose, they do
not edit this file.** Proposals go to `docs/agents-md-proposals.md`; a human
approves them line by line.

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
- Never edit this file.
