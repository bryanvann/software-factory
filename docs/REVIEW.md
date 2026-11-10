# The reviewer

Independent review is the highest-leverage gate in this pipeline: a separate
reviewer surfaces roughly 75% useful findings against under 50% for
self-review. **The reviewer is dispatched by the Foreman, never by the
worker.** A writer that chooses its own reviewer has not been reviewed.

The factory ships one reviewer, the local agent (Path A). A GitHub Action
(Path B) is kept as an optional example for the cases Path A cannot cover.

---

## Path A: local agent (the default, and the only path installed)

`agents/reviewer.md`, spawned by the Foreman into its own worktree after a
worker opens a PR. The patrol lists implementation PRs that carry no verdict
label, so a PR the Foreman missed is picked up within one patrol interval.

What the reviewer does:

1. Reads the PR, the spec it links, `AGENTS.md`, `CLAUDE.md` and the project's
   `docs/review-checklist.md`.
2. **Re-runs the gates itself.** It has a worktree; it does not take the
   worker's word that the suite is green.
3. **Reproduces the acceptance criteria**, including the ones that need the
   running app, using the project's `qa-procedure` skill. In the reference
   deployment this was the decisive step: findings that a code-only read
   could not see showed up the moment the reviewer drove the app.
4. Posts findings to GitHub as inline comments plus one summary.
5. Sets the verdict as a **label**, last:

   ```
   gh label create ai-approved          --color 0E8A16
   gh label create ai-changes-requested --color B60205
   ```

**Why a label and not an approval.** Every agent authenticates as the same
GitHub account that opened the PR, and GitHub rejects self-approval.
`gh pr review --approve` fails, and the PR's `reviews` array never gains an
approval. The worker polls for the label and the patrol filters on it. Nothing
in the factory waits on `reviews`.

Properties:

- Cost: covered by your Claude subscription.
- Can run gates, tests and the app. In a codebase whose failures are silent,
  that is the review.
- Cannot formally approve, so it cannot satisfy a branch-protection rule.
  `review: human` is a convention the Foreman follows (see
  [factory-config.md](factory-config.md)); GitHub does not enforce it.
- Needs the machine to be on, and reviews only what the Foreman dispatches.

## Path B: GitHub Action (optional, not installed)

[`examples/claude-review.yml`](../examples/claude-review.yml). The
`onboard-repo` skill asks whether you want it and adds it to the onboarding
PR if you do; or copy it into your project's `.github/workflows/` yourself. It applies the same
`ai-approved` / `ai-changes-requested` labels, so the worker, the patrol and
the Foreman behave identically whichever path set them.

**Choose it when** you need a review that runs with the machine off, a review
of PRs you open by hand, or a formal approval from a second identity for
branch protection.

**Prerequisites. Both are required.**

1. **Install the Claude Code GitHub App on the repository** (`/install-github-app`
   in Claude Code). Without it every run fails with a 401, "Claude Code is not
   installed on this repository", and posts nothing.
2. **Add a credential as a repo secret**: `ANTHROPIC_API_KEY` (pay-as-you-go
   API billing, separate from a subscription) or `CLAUDE_CODE_OAUTH_TOKEN`
   (from `claude setup-token`, billed to the subscription).

**This path is unproven.** The reference deployment shipped it as the default,
never installed the App, and got the 401 on every PR for about five weeks: a
red check on each PR and no review, while the local agent did all the actual
reviewing. The workflow was then deleted. The story is in
[FINDINGS.md](FINDINGS.md) under "Review". Verify it on a throwaway PR before
relying on it.

Other limits: it cannot run your simulator, your local stack or your
fixtures, so it cannot reproduce device criteria. It reviews by reading.

## Side by side

| | Path A: local agent | Path B: GitHub Action |
|---|---|---|
| Installed by `install.sh` | yes | no |
| Verdict signal | label | label (optionally a formal approval too) |
| Cost | subscription | API billing, or subscription via OAuth token |
| Runs gates, tests, the app | yes | no |
| Formal approval | no (self-approval blocked) | yes (separate identity) |
| Can back a branch-protection rule | no | yes |
| Works while the machine is off | no | yes |
| Reviews human-opened PRs | only if dispatched | automatically |
| Proven in the reference deployment | yes | no |

## Running both

Possible: the local agent reviews substance while the Action supplies the
formal approval that branch protection requires. Both write the same two
labels, so decide which one owns the verdict and remove the label step from
the other, or they will overwrite each other. The cost is double review
tokens and two comment threads per PR.
