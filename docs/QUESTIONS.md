# Open questions

What is still undecided or unverified. Each entry states the choice currently
in the files, so nothing here was settled by a guess. Delete an entry when it
is resolved and record the outcome where it belongs (usually
`docs/FINDINGS.md` or the file in question).

## Assumptions that need observing, not deciding

These are behaviours of Claude Code that the patrol depends on and that could
not be tested when it was written. The next login expiry or usage limit will
show whether they hold.

1. **Does the stored login expiry move on an ordinary token refresh, or only
   on `claude auth login`?** The patrol's "login renewed, restart the
   spawners" reminder assumes only on login. If it moves on every refresh the
   reminder fires spuriously and should be removed.

2. **Does restarting a spawner drop the sessions it hosts?** The patrol
   assumes yes, which is why it reminds the operator to restart spawners
   after a re-login and never does it itself. If restarting is harmless, the
   patrol should just do it, as it now does for a dead Foreman.

3. **In which timezone is the usage-limit reset time expressed?** The 429 text
   gives a wall-clock time with no zone. The patrol reads it in the machine's
   local zone. If it is in the account's zone, the pause ends at the wrong
   hour on a machine set elsewhere.

4. **Is `agentPushNotifEnabled` required for Claude app push notifications?**
   The reference deployment's settings have it on. Nothing here sets or
   documents it, because its effect was not verified.

## Unproven

5. **The GitHub Action reviewer has never produced a review.**
   `examples/claude-review.yml` is offered as an opt-in during onboarding. Its
   prerequisites are documented and its prompt sets the verdict labels, but
   the tool allowlist and inline-comment commands are unverified. Someone has
   to prove it on a throwaway PR.

6. **`spec_gate: auto` has never been run.** The reviewer's spec-review mode
   and the patrol's handling of spec PRs under that setting were written from
   the design, not from a deployment. The reference deployment only ever ran
   with human-approved specs.

## Still to decide

7. **Where a worker's raw reflection lives.** Today it is a comment on the
   worker's PR: durable, readable by the Foreman's retro, and writable from
   inside a worker's sandbox. The alternative is a local directory outside
   the repository (`~/.claude/factory/reflections/<project>/`), which keeps
   raw notes off the PR, something that matters more for a public repo. It
   needs a worker to be able to write outside its worktree without a
   permission prompt, which has not been verified for background agents.

8. **This repo has never been onboarded with its own skill.** Its `AGENTS.md`
   and `qa-procedure` are the unfilled templates. Running `/onboard-repo`
   here is the obvious first use of it. What "QA" means for a repo of shell
   scripts and prompts is the interesting question that interview would have
   to answer; the sandboxed dry-runs used while writing the patrol and the
   installer suggest a starting point.
