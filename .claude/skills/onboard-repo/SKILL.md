---
name: onboard-repo
description: Adapt the baseline software factory to a new repository. Analyses the repo, interviews the operator, and opens ONE pull request containing a draft AGENTS.md, a draft qa-procedure skill, and the factory config, for the operator to approve line by line before anything is dispatched. Use when onboarding a project to the factory, or when asked to set up, adopt or bootstrap the factory in a repo.
---

# Onboard a repository to the factory

## What this is

The factory improves through one loop: something is learned, it is written as
a proposal against the artifact that should change, and the operator approves
it line by line. After onboarding, the Foreman's retro runs that loop forever
(`docs/proposals.md`).

**Onboarding is iteration zero of the same loop.** Same artifacts, same
propose-then-approve mechanism. The only differences are the source of the
lessons (the repository and the operator's head, instead of merged PRs) and
the size of the batch (everything at once, as one PR). You are not
configuring the factory. You are drafting its first set of proposals.

Three consequences:

- **You propose; the operator approves.** Nothing you write is in force until
  the PR merges. Do not load launchd jobs, add the project to `boot.sh`,
  create `status:ready` issues or dispatch anything. (`boot.sh` starts a
  Foreman for every project it lists, and any project's patrol can run it.)
- **Every line must be reviewable on its own.** The operator will read the
  diff line by line. A line they cannot evaluate without asking you what you
  meant is a defect in the draft.
- **A line must change behaviour.** `AGENTS.md` is loaded on every task; each
  line costs tokens forever and dilutes the others. A description of the
  codebase that an agent would discover anyway is noise. Agent-written context
  files have been measured to slightly reduce success while raising cost;
  what rescues this one is the operator's line-by-line approval, so make that
  review easy rather than long.

## Before you start

- `install.sh --project <path>` has been run, so the scaffolding exists
  uncommitted in the working tree: `AGENTS.md` and
  `docs/specs/_TEMPLATE.md` templates, `docs/factory-config.md`,
  `docs/proposals.md`, `docs/review-checklist.md`, the `docs/product/`
  index and page template, `.claude/skills/qa-procedure/SKILL.md`,
  `.githooks/pre-commit`, `scripts/ship.sh`, `.claude/settings.json`. If it
  has not, stop and say so.
- **Check that list file by file.** If some are there and others are not,
  the installer that ran is older or newer than this skill. Stop and say
  which files are missing; the fix is to re-run `install.sh --project` from
  the same factory checkout this skill came from (it never overwrites). Do
  not onboard around the gap.
- Work on a branch named `factory/onboard`, cut from the up-to-date default
  branch: `git fetch`, then `git switch -c factory/onboard origin/<default>`.
  The uncommitted scaffolding carries over. Do this even if the checkout was
  sitting on another branch. Never commit to the default branch.
- Files that were already untracked or modified before the installer ran are
  not yours. Stage the onboarding files by path, never with `git add -A`,
  and name what you left alone in the PR body.
- If `AGENTS.md` already has real content, this is a re-onboarding. Do not
  rewrite it: every change to an approved `AGENTS.md` goes through
  `docs/proposals.md`. Limit yourself to the QA skill and the config, and say
  so in the PR.

## Phase A — analyse the repository

Read-only. Do this before asking the operator anything, so the interview is
about judgement and not about facts you could have looked up.

1. **Shape.** What the system is, its components and how they talk, the
   stack, where state lives, what is deployed where. Read the README, the
   manifests, the directory tree, CI config, and the entry points.
2. **Commands.** The exact build, typecheck, lint, test and run commands.
   **Run each one on the default branch and record the result.** A gate that
   does not pass today must not be enabled: it would block every worker on
   failures it did not cause. Record the failing baseline as a finding.
3. **Validation.** How anyone currently knows the app works: test suites and
   what they actually cover, end-to-end tooling, fixtures, seed scripts,
   staging environments. Note what can only be checked by running the app.
4. **Existing conventions.** Existing agent or contributor instructions
   (`CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING`, linters, commit style, PR
   templates). Prefer what the repo already enforces mechanically over
   anything you would have to write down.
5. **Candidate failure-prone areas.** Where an agent is most likely to do
   damage or be fooled: files with heavy churn and bug-fix history
   (`git log`), code with no tests, anything touching money, auth,
   migrations or deletion, generated directories, config that points at
   production, anything whose failure is silent.
6. **Factory hazards.** Agent worktrees are nested inside the checkout at
   `.claude/worktrees/`. Check that it is gitignored and that the test
   runner, bundler and linters do not crawl it. Check what a worker would be
   missing in a fresh worktree (dependencies, untracked env files).
   If `docs/product/` already held documents before the installer ran, list
   them: the product-reference checks loop over every file in that folder.
7. **Patterns you cannot classify.** List the places where the code does the
   same thing two ways, or does something that looks wrong on purpose. You
   cannot tell intent from debt by reading. That is a question for Phase B.

Write the findings up briefly for the operator before the interview. They go
into the PR body, not into a committed file.

## Phase B — interview the operator

The repository tells you what is. Only the operator can tell you what is
intended. Ask; do not infer.

Rules for the interview:

- Lead with what you found, so each question is concrete: "I see two
  data-access styles, X in these directories and Y in those. Which is the
  intended one?" beats "what are your conventions?"
- A few questions at a time, each answerable in a sentence. The operator may
  be on a phone.
- **Say the size before you start and keep to it:** how many rounds, roughly
  how many questions, and at each round how many are left. Aim for fifteen
  questions or fewer. Put the questions whose answers change the most first
  (what is production, the gates, what agents may do unasked), so that if
  the operator stops early the rest can become `TODO(operator)` lines.
- Offer choices only where the choices are real. "What would make you reject
  a PR on sight", "what invariants does the data have" and "what has fooled
  you before" are open questions: ask them as plain text, with what you
  found as a prompt, not as a list to tick.
- **Never fill a gap with a guess.** An unanswered question becomes a visible
  `TODO(operator): <question>` in the draft, which the operator resolves in
  review.
- Record answers in the operator's own words. Do not improve them.

Cover all six areas.

**1. Golden principles.** The architectural rules that must never be
violated, and why each exists.

- What would make you reject a PR on sight, even if it worked?
- Which boundaries between components must not be crossed, and in which
  direction?
- What invariants does the data have that the code does not enforce?
- What is this project's attitude to scope: smallest possible change, or
  fix what you touch?

**2. Intent versus debt.** For each item from Phase A step 7:

- Is this the pattern to follow, a pattern to migrate away from, or an
  accident to leave alone?
- If a worker touches legacy code, does it match the legacy style or the
  intended one?

**3. What QA depth means here.**

- What does "verified" mean for this app: unit tests green, an API contract
  suite, a browser run, simulators, a staging deploy?
- Which user journeys must never break? These become the hops and the
  coverage checklist.
- What has fooled you before: what looked like a pass and was not?
- What may an agent safely run and reset, and what is shared or production?
- If Phase A found no test environment at all (the app can only talk to
  production), say so and ask what agents may do against production until
  one exists: nothing signed in, named test accounts only, or anything.
- Where should evidence live so that an issue can link to it?

**4. Decision boundaries.**

- What may agents decide without asking? What must always come to you?
- Is any existing data disposable? Which data is never to be lost or
  rewritten, under any circumstances? (Recorded as a standing rule; by
  default anything that could lose data escalates.)
- May agents add dependencies, change schemas, change public interfaces,
  touch CI or deployment?
- How do you want to be interrupted, and how often is too often?

**5. Human gates and defaults.** There are two places a human can be
required, and they are set separately. Put it to the operator as two
questions:

- **Specs.** Who merges a spec PR: you for every spec (`spec_gate: human`);
  you for new features, architectural choices and product-impacting
  deviations while the Foreman merges plain bug-fix specs (`spec_gate:
  by-kind`, the shipped default); or the reviewer agent for all of them
  (`spec_gate: auto`)? Under `by-kind`, is there a second person who drives
  product changes and should merge the specs they drive? Record them under
  "Drivers" in the config.
- **Code.** Once the reviewer agent approves a PR, who merges it: always you
  (`code_gate: human`), always the Foreman (`code_gate: auto`), or decided
  spec by spec (`code_gate: per-spec`)? If spec by spec, what should a new
  spec default to, `review: human` or `review: auto`?
- `budget:` defaults: how many iterations before a worker must stop, for a
  one-screen change, a flow across several screens, and a change that
  touches data or sync?
- Parallel-worker cap, if not 5?

**5b. Shipping.** Only if merging to the default branch is meant to publish
something (an app update, a web deploy, a package).

- Which channels does a merge ship to, and what configuration must each
  one's artifact carry (backend host, client ids, feature flags)? That
  becomes `ship_channels` and one `ship_expect_<channel>` line each in the
  config, and the check the ship step refuses to publish without.
- Is there a production migration step, and does its tool read the folder
  git tracks or a different one?
- For native or device builds: what two-minute smoke on a real device must
  pass before a build is offered to testers?

Say plainly what the combination they chose means, for example: "so nothing
merges without you" or "so a bug QA finds can be fixed and merged with nobody
looking". Both gates on `auto` is a legitimate choice for a project with no
users; make sure it is a choice.

**6. Reviewer.**

- Every implementation PR is reviewed by the local reviewer agent the Foreman
  dispatches. That is always on and needs nothing from you. Do you *also*
  want a GitHub Action reviewer on this repository?

Explain the trade in one breath before they answer. The Action runs with the
machine off and reviews PRs opened by hand. It cannot run the app, it needs
the Claude Code GitHub App installed on the repository plus an API key or
OAuth token stored as a repository secret, and it has not yet been proven to
work. The default answer is no.

If the operator says "use the defaults", write the shipped defaults and note
in the PR body that they were chosen by default rather than by decision.

## Phase C — draft the three artifacts

### 1. `AGENTS.md`

Fill in the template. This file holds **golden principles**: durable
judgement. Mechanical rules belong in the artifact that enforces them (a
test, a lint rule, the review checklist), not here.

- **Project shape:** a few lines: what it is, the stack, and which directory
  is the dangerous one.
- **Gates:** only commands you ran in Phase A and saw pass. List a failing
  gate under a `TODO` with its baseline, not as a gate.
- **Principles:** the operator's golden principles, each one imperative line
  plus the reason in a clause. Their words.
- **Patterns:** intent-versus-debt rulings, as "follow X; do not extend Y".
- **Failure-prone areas:** the ones the operator confirmed, each with what to
  do differently there.
- Leave out anything an agent would get right unprompted.

The template says agents never edit this file. This draft is the single
exception, and only because the file has never been approved: the operator's
line-by-line review of this PR is what makes it human-curated. After the
merge the rule has no exceptions, this skill included.

### 2. `.claude/skills/qa-procedure/SKILL.md`

Implement the template's six sections for this app, at the QA depth the
operator described. Keep the headings; they are the contract.

- **Verify the bring-up recipe by running it**, from a clean worktree if you
  can. A recipe you did not run is marked `UNVERIFIED` line by line.
- Build the hop table from the must-never-break journeys. If you cannot find
  a way to assert a hop, say so in the table. That is a real finding.
- If there is no test environment, the template's target check cannot be
  met as written. Write the preflight around what can be proven instead
  (which backend the build points at, which account is signed in), record
  the operator's answer about production as a standing rule in the config,
  and make an isolated environment the first proposed issue after the
  product reference.
- Write the prime directive from the operator's "what has fooled you before".
- Mark any section you could not implement `NOT IMPLEMENTED: <why>`.
- If driving the app needs helper scripts that do not exist, do not write
  them here. List each as a proposed first issue in the PR body.

### 3. `docs/factory-config.md`

Set the settings block, "Decision boundaries" and "Standing rules" from
the interview. Every value that differs from the shipped default gets a line
in the PR body quoting the operator's answer that justifies it. Keep the safe
default wherever the operator did not explicitly choose otherwise.

### Mechanical scaffolding

These ride in the same PR and need no line-by-line judgement. List them
separately in the PR body so the operator can skim them:

- the files `install.sh --project` wrote;
- `.gitignore` entry for `.claude/worktrees/`;
- test-runner, bundler and linter excludes for `.claude/worktrees/`, if
  Phase A found they crawl it;
- `TYPECHECK_CMD` / `TEST_CMD` in `.githooks/pre-commit`, each one only if
  it passed on the default branch. They are independent: enable the one
  that passes, and leave the other empty with its failing baseline recorded
  in the comment above it;
- the "Ship step" block in `docs/factory-config.md` and the `ship_*`
  functions in `scripts/ship.sh`, from the shipping answers, only if a merge
  is meant to publish something. Run `scripts/ship.sh --dry-run` and paste
  its output: the artifact check must pass against the real expectation for
  every channel before the Foreman ever runs it for real. Leave the
  functions as shipped, and say so, if nothing is published;
- the header of `docs/product/README.md`: product name, as-built line, the
  groups the pages will fall into. Not the pages themselves (next section);
- **only if the operator asked for the GitHub Action reviewer:**
  `.github/workflows/claude-review.yml`, copied from
  `~/.claude/factory/examples/claude-review.yml` with the model placeholder
  filled in. List its two prerequisites (the GitHub App install and the
  repository secret) under "Open TODOs" in the PR body: both are the
  operator's to do, and the workflow fails on every PR until they are done.

Change no application code.

### 4. The product reference: propose it, do not write it

`docs/product/` is where the factory keeps what the product should do, one
page per screen or flow, as built. Without it QA cannot tell a regression
from a feature, the reviewer cannot tell scope creep from intent, and a
non-technical operator has nothing to design against. It is too large for
the onboarding PR and needs code reading, so onboarding leaves the index
and template in place and lists the writing as the **first proposed issue**
(Phase D, item 6), as a spec with three documentation PRs, one worker each,
in order:


1. the skeleton plus the areas that already have written material (design
   documents, merged specs, the QA log);
2. the areas with no written behaviour anywhere, written from the code;
3. the project's own guidance pointing at the pages: its `CLAUDE.md`, any
   product-design skill. The factory's four hooks (spec template, worker,
   reviewer, QA) are already in place, so this PR is small.

If `docs/product/` already held the project's own documents, do not move or
rewrite them in the onboarding PR. Name them in the findings, and make
moving them out of that folder (they are source material for the pages, not
pages) the first step of the first documentation PR above; until then the
heading and index checks will fail on them.

Each PR is reviewed by the reviewer agent, which spot-checks statements
against the code. Expect it to find wrong statements; expect the writers to
find real bugs by reading code against what a user would expect. Both are
the point.

Acceptance criteria for those PRs, mechanically checkable; put them in the
spec as single plain commands run from the worktree root:

- every page has the seven headings, in order (loop over
  `docs/product/*.md`, skipping `README.md` and `_TEMPLATE.md`, `grep -q`
  each heading; print the file on a miss);
- the index lists every page (loop over the files, `grep -q` the basename in
  `README.md`);
- no code identifiers in sections 1 to 6 (a `grep -n -E` for the project's
  own identifier shapes: store or hook names, source-file extensions, package
  scopes; exclude `Route:` lines and everything from `## Verified by` on);
- every screen or route file is named in exactly one page's `Route:` line
  (loop over the screen files, count `grep -l` matches, print any count that
  is not 1).

Two traps: route names containing brackets must be matched with `grep -F`
(fixed strings), and a one-line `&&`/`||` chain needs explicit `{ }` or
`( )` grouping or the `|| echo MISSING` binds to the last test only.

## Phase D — one pull request

Open exactly one PR, titled `docs: onboard <project> to the factory`.

The onboarding commit is larger than the diff-size guard allows, by
construction: the installer's own templates are most of it. Commit it with
`MAX_DIFF_LINES=2000 git commit …`, for this commit only, and say so under
"Mechanical scaffolding". Do not use `--no-verify`: the secret scan must
still run.

The body, in this order:

1. **What this is.** Two sentences, including: nothing is dispatched until
   this merges, and after it merges every further change to these files goes
   through `docs/proposals.md`.
2. **How to review.** `AGENTS.md`, the QA skill and the config are to be read
   line by line. Delete any line that does not earn its place; a shorter file
   is a better file.
3. **Provenance.** A table: each `AGENTS.md` line and each non-default config
   value, with where it came from: `operator` (quote the answer) or `repo`
   (cite the file or command output). A line with neither source should not
   be in the draft.
4. **Open TODOs.** Every `TODO(operator)`, `UNVERIFIED` and
   `NOT IMPLEMENTED`, as a checklist.
5. **Phase A findings** that did not become a line anywhere: failing
   baselines, untested areas, factory hazards.
6. **Proposed first issues.** What you would file once the factory is live:
   the product reference (Phase C, item 4) first, then fix the red baseline,
   build a missing QA helper. Do not file them now.
7. **Mechanical scaffolding**, listed.

Then stop and tell the operator the PR is ready. Do not merge it. Answer
review comments by pushing changes to the same branch.

## After the merge

Tell the operator what remains, all of it theirs: accept the workspace trust
dialog, load the launchd jobs, add the project to `boot.sh`, create the
labels (`install.sh --project` printed the commands). The project's Remote
Control spawner is one of those launchd jobs: it is what makes the repository
appear in the Claude app as a place to start a session.

From here on the loop runs by itself. The Foreman's retro files what the
factory learns into `docs/proposals.md`, each line tagged with the artifact
it would change, and the operator approves line by line, exactly as they
just did.
