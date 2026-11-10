# AGENTS.md — <project>

Golden principles for agents working in this repo. **Human-curated: every line
here was approved by the operator.** Agents propose to `docs/proposals.md`; the
operator approves line by line; the Foreman writes approved lines in verbatim.
No agent changes this file on its own judgement.

Every line here should be a rule of judgement an agent would otherwise get
wrong. Anything a test, a lint rule or the review checklist can enforce
belongs there instead. Delete what stops earning its place: a bloated file
costs tokens on every task and dilutes the rules that matter.

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

## Principles

<!-- The architectural rules that must never be violated, each with its
     reason in a clause. In the operator's words. -->

## Patterns

<!-- Which existing patterns are intent and which are debt:
     "follow X; do not extend Y". -->

## Failure-prone areas

<!-- Where an agent is most likely to do damage or be fooled, and what to do
     differently there. -->

## Hard rules

- Never commit secrets or `.env*` files.
- Never edit this file except to apply a line the operator approved.
