---
name: qa-procedure
description: TEMPLATE — this project's procedure for bringing the app up, driving it, asserting each hop of its critical paths, capturing evidence, and reporting what was not covered. Use when asked to QA, run an end-to-end or regression pass, reproduce a bug, or verify an acceptance criterion against the running app. Replace this description with one that names the app and its critical paths.
---

<!--
THIS FILE IS A TEMPLATE AND A CONTRACT.

The factory's agents call a skill named `qa-procedure` and assume it does the
six things below. The QA agent (agents/qa.md) runs all of it. The reviewer
runs sections 1 to 4 to reproduce a PR's acceptance criteria. A worker runs
them when a criterion needs the running app.

Every project implements this file for its own app: simulators, a browser, an
API contract suite, a CLI harness. The six sections and their order are the
interface. Keep the headings; replace everything in <angle brackets>; delete
these comments when the section is real.

The `onboard-repo` skill drafts a first implementation from the repository
and the operator interview. docs/QA-REFERENCE.md in the factory repo
describes one complete implementation.

A section you cannot implement yet stays in, marked NOT IMPLEMENTED with the
reason. An honest gap is part of the contract. A missing section is not.
-->

# QA procedure — <app name>

You are acting as a **tester**, not a developer. Find out what actually works,
produce evidence someone else can check, and report honestly, including what
you did not cover. Do not fix what you find unless you were asked to.

## Prime directive

<The one false positive this app is prone to, stated as a rule. The reference
implementation's was: never conclude the pipeline works from the UI; a green
screen over an empty backend was its most common false pass. Write yours.>

When the app's own diagnostics and its real state disagree, trust neither and
read the raw state.

## 0. Preflight

Run before touching anything. Stop if any check fails.

- **Target check.** Prove you are pointed at the test environment and not
  production: <command and the output that proves it>. Do not skip this
  because the configuration looks right; verify what the running app loaded.
- **Shared resources.** <What other agents may be using right now (a local
  backend, a device, a port) and how to get an isolated one instead of
  resetting theirs.>
- **Known issues.** <Command that lists already-filed bugs.> Confirm or deny
  those; do not re-file them.

## 1. Bring the app up

The exact, verified recipe from a clean checkout or worktree to a running app
under test. Commands, not prose.

```sh
<build / install / start commands>
```

- <Every trap that silently produces a stale or wrong build.>
- <What differs when run from an agent worktree rather than the main checkout.>
- <How to create a fresh test account or tenant, and how to tell it is fresh.>

## 2. Drive it

How an agent operates the app without a human: <the driver: simulator
automation, a headless browser, HTTP calls, a CLI>.

```sh
<the helper commands: find an element, tap or click, type, navigate>
```

- <Gotchas that each cost an hour: coordinate systems, dialogs that swallow
  input, actions that restart the app.>
- <How to move time, network state, or anything else a test must control.>
- <How to load fixtures, and which fixtures are realistic enough for which
  assertions.>

## 3. Assert each hop

**Never assert only at the end of a path.** List every hop between the user's
action and its final effect, and how to check the real state at each one. A
pass at the last hop with a failure in the middle is how silent bugs survive.

| Hop | What must be true | Assert with |
|---|---|---|
| 1. <action → first component> | <state> | <command> |
| 2. <… → next component> | <state> | <command> |
| 3. <… → final effect> | <state> | <command> |

- <Any path that can produce healthy-looking end state while the path under
  test is dead, and the check that tells them apart.>
- <Values that mean "this never ran" but look like legitimate results.>

## 4. Capture evidence

Every claim, pass or fail, carries evidence captured **at the moment it is
observed**. Test state does not survive: environments get reset, logs roll.

- **Record:** <command to start and stop a capture of the run>
- **Publish somewhere durable and linkable:** <command>
- A recording shows behaviour. It does not prove a hop. Always pair it with
  the assertions from section 3, quoted as raw output.
- One short capture per claim. Nobody watches a session-length recording.
- Record passes with the same rigour as failures: <where verified-working
  results are logged>, each with the date, the build, the actual assertion,
  the evidence link, and a **scope limits** line saying what the entry does
  not claim.

## 5. Report coverage honestly

Mark every line **pass / fail / not covered**. "Not covered" is a required
answer, not an admission. A report that implies coverage it does not have is
worse than no report, because the next reader will trust it.

- [ ] <critical path 1>
- [ ] <critical path 2>
- [ ] <recovery: interrupt mid-operation, resume, no loss or duplication>
- [ ] <anything currently untestable, with the issue that blocks it>

For each finding: symptom → evidence → root cause at `file:line` if found →
suggested direction. Label anything found by reading code rather than
reproducing it as **unreproduced**.

State explicitly what you did not test and why. If this procedure could not
reach something that matters, say so: that gap is a proposal against this
file (see `docs/proposals.md`, target `[qa-procedure]`).

## 6. Clean up

- <What this procedure leaves behind that would silently affect the next run
  (config overrides, clock offsets, test accounts, temporary devices), and
  the command that removes each.>
- If you leave something in place on purpose, say so in the report.
