# The reviewer: two paths

Independent review is the highest-leverage gate in this pipeline — a separate
reviewer surfaces roughly 75% useful findings against under 50% for self-review.
Whichever path you pick, **the reviewer is dispatched by the Foreman, never by
the worker.** A writer that chooses its own reviewer has not been reviewed.

Both paths are wired in this repo. Pick one; you can switch later.

---

## Path A — local agent (default)

`agents/reviewer.md`, spawned by the Foreman into its own worktree after a
worker opens a PR. Findings go to GitHub as inline comments; the verdict is a
**label**.

**Choose it when** you are on a Claude subscription, your machine is always on,
and reviewing well requires *running* the code rather than only reading a diff.

```
gh label create ai-approved          --color 0E8A16
gh label create ai-changes-requested --color B60205
```

- Cost: covered by your subscription.
- Can run gates, tests, even the app — decisive in a codebase whose failures
  are silent.
- **Cannot formally approve.** All agents share one GitHub account and GitHub
  rejects self-approval on your own PR. The label is the signal; the worker
  polls for it and must never wait on `reviews` being non-empty.
- Cannot gate merges natively — `review: human` stays convention, not
  enforcement.

## Path B — GitHub Action

`.github/workflows/claude-review.yml`, triggered on PR open/update.

**Choose it when** enforcement matters more than cost — typically once real
users exist and an unreviewed merge has consequences.

- Runs as `github-actions[bot]`, a **different identity**, so it *can* formally
  approve — and that approval can satisfy a branch-protection rule. This is the
  only way `review: human | auto` becomes enforced rather than conventional.
- Off-machine: survives the Mac being asleep, and reviews PRs you open by hand.
- Cost: `anthropic_api_key` is **pay-as-you-go API billing, separate from a
  Claude subscription.** Every PR and every follow-up push is metered.
  (Check whether the action supports subscription auth via
  `CLAUDE_CODE_OAUTH_TOKEN` — if so, this drawback largely disappears.)
- Cannot run your simulator or local fixtures.

## Side by side

| | Local agent | GitHub Action |
|---|---|---|
| Cost | subscription | separate API billing |
| Runs tests / the app | yes | no |
| Formal approval | no (self-approval blocked) | yes (bot identity) |
| Gates merges | label convention only | required status check |
| Works while Mac is off | no | yes |
| Reviews human-opened PRs | only if dispatched | automatically |

## Running both

Supported, and not as silly as it sounds: the local agent reviews substance
(it can run the suite) while the Action provides the formal approval that
branch protection requires. The cost is double review tokens and two comment
threads on every PR. Worth it only once merge-gating genuinely matters.
