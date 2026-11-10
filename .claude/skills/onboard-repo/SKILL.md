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
  the PR merges. Do not load launchd jobs, create `status:ready` issues or
  dispatch anything.
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
  `docs/proposals.md`, `docs/review-checklist.md`,
  `.claude/skills/qa-procedure/SKILL.md`, `.githooks/pre-commit`,
  `.claude/settings.json`. If it has not, stop and say so.
- Work on a branch named `factory/onboard`. Never commit to the default
  branch.
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
- Where should evidence live so that an issue can link to it?

**4. Decision boundaries.**

- What may agents decide without asking? What must always come to you?
- Is any existing data disposable? Which data is never to be lost or
  rewritten, under any circumstances?
- May agents add dependencies, change schemas, change public interfaces,
  touch CI or deployment?
- How do you want to be interrupted, and how often is too often?

**5. Defaults.**

- `review:` default for specs, `human` or `auto`?
- Once the reviewer approves, does the spec's `review:` field decide who
  merges (`landing: per-spec`), or should approved code always land without
  you (`landing: autonomous`)?
- `budget:` default: how many iterations before a worker must stop?
- Parallel-worker cap, if not 5?

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
- Write the prime directive from the operator's "what has fooled you before".
- Mark any section you could not implement `NOT IMPLEMENTED: <why>`.
- If driving the app needs helper scripts that do not exist, do not write
  them here. List each as a proposed first issue in the PR body.

### 3. `docs/factory-config.md`

Set the settings block, "Protected data", and "Decision boundaries" from
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
- `TYPECHECK_CMD` / `TEST_CMD` in `.githooks/pre-commit`, only if both passed
  on the default branch;
- **only if the operator asked for the GitHub Action reviewer:**
  `.github/workflows/claude-review.yml`, copied from
  `~/.claude/factory/examples/claude-review.yml` with the model placeholder
  filled in. List its two prerequisites (the GitHub App install and the
  repository secret) under "Open TODOs" in the PR body: both are the
  operator's to do, and the workflow fails on every PR until they are done.

Change no application code.

## Phase D — one pull request

Open exactly one PR, titled `docs: onboard <project> to the factory`.

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
6. **Proposed first issues.** What you would file once the factory is live
   (fix the red baseline, build a missing QA helper). Do not file them now.
7. **Mechanical scaffolding**, listed.

Then stop and tell the operator the PR is ready. Do not merge it. Answer
review comments by pushing changes to the same branch.

## After the merge

Tell the operator what remains, all of it theirs: accept the workspace trust
dialog, load the launchd jobs, add the project to `boot.sh`, create the
labels (`install.sh --project` printed the commands).

From here on the loop runs by itself. The Foreman's retro files what the
factory learns into `docs/proposals.md`, each line tagged with the artifact
it would change, and the operator approves line by line, exactly as they
just did.
