# Software Factory — working agreements

This repo *is* a factory instance as well as the template for one. Changes here
go through the same flow they describe. If a convention is too annoying to
follow in this repo, that is evidence it is too annoying to ship.

## Ledger

GitHub Issues are intake; issue labels are state:

| Label | Meaning |
|---|---|
| `status:triage` | Filed, not yet assessed |
| `status:needs-spec` | Agreed real; needs `docs/specs/<name>.md` before dispatch |
| `status:ready` | Spec linked, no open questions, deps merged — dispatchable |
| `status:in-progress` | Worker assigned, PR open |
| `status:blocked` | Open question or unmerged dependency; reason in a comment |

Exactly one `status:` label per issue. The Foreman turns `status:ready` issues
into tasks. Flow is one-way — never sync backwards.

## Specs

Proposed in their own PR containing only the spec. Merging the spec PR is the
approval; only then does the issue become `status:ready`.

`review:` and `budget:` are the operator's decision, never guessed.
Acceptance criteria must be mechanically checkable — they become the worker's
`/goal` verbatim.

## Implementation PRs

Link the spec, contain `Closes #<n>`.

## No secrets, ever

This repo is intended to be publishable. Nothing account-specific belongs in
it: no API keys, no usernames, no absolute home paths, no hostnames, no ntfy
topics, no project names from other repos. Use the template placeholders
(`__HOME__`, `__PREFIX__`, `__PROJECT__`, `__NTFY_TOPIC__`).

Before committing, run:

```
grep -rniE '<your-username>|/Users/[a-z]|ntfy\.sh/[a-z-]+' . --exclude-dir=.git
```

## AGENTS.md is human-curated

Agents propose to `docs/agents-md-proposals.md`. Only a human edits `AGENTS.md`.
