# Open questions

Decisions this repository's maintainer still has to make. Each was left open
on purpose, with the choice currently in the files stated, so that nothing
here was settled by a guess. Delete an entry when it is decided, and record
the decision where it belongs (usually `docs/factory-config.md`,
`docs/FINDINGS.md` or the file in question).

## Remote Control and the patrol

1. **Is "the second-spawner pattern" the parent-directory spawner?** The
   reference deployment runs one spawner per project plus one in the
   directory that contains the checkouts. `OPERATIONS.md` and
   `install.sh --spawner` document that as the pattern. If it meant something
   else (for example a second spawner per project in `--spawn worktree`
   mode), those two places are wrong.

2. **Should the patrol restart spawners itself after a re-login?** The
   deployed patrol only alerts when no spawner process exists. This version
   adds a one-time reminder when the login expiry moves forward, and
   deliberately restarts nothing, on the assumption that restarting a spawner
   drops the sessions it hosts. That assumption is untested.

3. **Does the stored refresh-token expiry move on an ordinary token refresh,
   or only on `claude auth login`?** The re-login reminder assumes only on
   login. If it moves on every refresh, the reminder fires spuriously (at
   most once per day of movement) and should be removed.

4. **In which timezone is the usage-limit reset time expressed?** The 429 text
   gives a wall-clock time with no zone. The deployed patrol hardcoded one
   zone; this version uses the machine's local zone. If the time is in the
   account's zone rather than the machine's, the pause ends at the wrong
   hour on a machine set to a different zone.

5. **Should "Foreman is down" be rate-limited?** Liveness now runs before the
   quiet-mode exit, so a dead Foreman is reported within 15 minutes even
   when the factory is idle (previously up to an hour). The cost is a
   notification every 15 minutes until it is restarted.

6. **Is `agentPushNotifEnabled` required for push notifications?** The
   reference deployment's settings have it set alongside
   `remoteControlAtStartup`. Nothing here documents or sets it, because its
   effect was not verified.

## Review and landing

7. **Keep or drop the `auto-merge` label?** Nothing acts on it; the Foreman
   performs the merge. It is kept as a visible marker of `review: auto`.
   Dropping it would remove a label, one worker step, and a standing source
   of confusion with GitHub's own auto-merge feature.

8. **Keep the GitHub Action example at all?** `examples/claude-review.yml`
   has never produced a successful review anywhere. Its prerequisites are
   documented and its prompt now sets the verdict labels, but the tool
   allowlist and inline-comment commands are unverified. Decided so far: it
   stays, as an opt-in the onboarding interview offers. Still open: someone
   has to prove it on a throwaway PR.

9. **Reviewer checks live in the project's `docs/review-checklist.md`, not in
   `agents/reviewer.md`.** The agent definition is installed account-wide, so
   a project's retro cannot edit it. The reviewer reads the project file on
   every PR. Is a per-project checklist the intended home, with only
   factory-wide lessons going upstream to `agents/reviewer.md`?

## The feedback loop

11. **The Foreman merges its own `docs: retro proposals` PRs.** They only
    append to `## Pending`, which changes nobody's behaviour. This is the one
    PR an agent merges regardless of `landing`. Acceptable? In a project
    where pushing the default branch has side effects (a deploy hook, for
    instance), it may not be.

12. **The worker's reflection moved from a `REFLECTION.md` file in its
    worktree to a PR comment**, because the worktree is deleted after the
    merge and the PR is the durable record. The deployed workers still write
    the file. Confirm the change, or revert `agents/worker.md` and
    `roles/foreman.md` to the file.

13. **Are the six seeded entries in `docs/proposals.md` wanted?** Five are
    lessons from the reference deployment that looked general (spec template
    and review checklist). They were queued for approval rather than applied,
    since applying them unreviewed would have bypassed the mechanism they
    arrive through. The sixth is the stale pointer in this repo's
    `AGENTS.md`.

## Config

14. **Does `data_policy: preserve | regenerable` plus a "Protected data" list
    capture the third memory-only rule?** The deployed rule was "all data is
    regenerable except one named kind". It was generalised to a setting with
    an exception list, with `preserve` as the public default.

15. **Pin model ids or use aliases?** `agents/reviewer.md`, `agents/qa.md`
    and `scripts/boot.sh` pin a dated model id, which matches the deployment
    and will go stale; `agents/worker.md` and the patrol use aliases
    (`sonnet`, `haiku`). One convention would be better than two.

## This repository as an instance

16. **This repo has never been onboarded with its own skill.** Its `AGENTS.md`
    is the unfilled template (and still points at the old proposals path),
    its `qa-procedure` is the template, and its config is the defaults. For a
    repo that claims to dogfood its own flow, running `/onboard-repo` here is
    the obvious first use of it. What "QA" means for a repo of shell scripts
    and prompts is the interesting question that interview would have to
    answer; the sandboxed dry-runs used while writing the patrol and the
    installer suggest a starting point.

17. **The patrol's project name.** `boot.sh` accepts `"<path>|<name>"`;
    the patrol takes the name as an optional second argument, but
    `launchd/patrol.plist.template` and `install.sh` always use the directory
    basename. A project given an explicit name needs its patrol plist edited
    by hand. Worth a `--name` flag on `install.sh`?
