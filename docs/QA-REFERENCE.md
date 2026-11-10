# QA procedure: a reference implementation

`.claude/skills/qa-procedure/SKILL.md` is a template that every project fills
in for its own app. This page describes one complete implementation, from the
first deployment of this factory, so that the template's six sections are not
abstract. It is described rather than copied: the scripts are specific to that
app and would mislead more than they would help.

The app was a mobile app for iOS whose core feature was a multi-step sync
pipeline: content captured on one device travels through local storage, a
cloud database and object storage, and appears on a second user's device. Its
failures were overwhelmingly silent. That shaped everything below.

## How the six sections were filled

**Prime directive.** "Never conclude sync works from the UI." A healthy screen
over an empty cloud table was the most common false pass in the codebase's
history, so the rule sat at the top of the skill.

**0. Preflight.** The development config pointed at production by default, and
the build tool let a config file override shell variables, so exporting the
right value did nothing. The preflight fetched the bundle the dev server was
actually serving and grepped it for the backend URL. Agents were told to stop
if it showed production. It also listed the already-filed QA issues, and
checked for a stale dev server on the default port.

**1. Bring up.** Two simulators of different models (so logs and screenshots
are unambiguous), a local backend stack, and a seeded account per device. The
recipe recorded each trap as it was found: a generated native directory that
goes stale, a database reset that drops grants and breaks every later
assertion, an install path that had been renamed. Later additions covered
running from an agent worktree, where the bundler's ignore rules excluded the
worktree's own files, and sharing one local backend among concurrent agents:
no resets while another agent is running; use a fresh account instead.

**2. Drive.** A small directory of shell and Node helpers over an
accessibility-tree CLI: dump the tree with tap coordinates, tap by label
substring, scroll an element into view and then tap it, sign in, and read
the app's on-device key-value store directly. The gotchas section was the
valuable part: accessibility frames reported in scroll-content rather than
screen coordinates, a permission command that restarts the app, a dev overlay
that swallows taps. A debug deep link set and advanced an in-app clock, which
made every time-dependent behaviour testable in seconds, with a standing
instruction to reset it at the end of a run because the override persisted.

**3. Assert each hop.** A five-row table, one row per hop of the pipeline, each
with the command that reads real state at that hop: a structured log line
with counts, the on-device store, the cloud rows over the REST API, the stored
object sizes queried from the database, and the second device's store. Two
warnings earned their place. First, onboarding used a different ingest path
from the steady-state one, so it could fill the app with healthy data while
the path under test was dead; the mandatory check was to add new content
*after* onboarding and assert a counter moved. Second, a specific all-zero
result was the "analysis failed" placeholder and indistinguishable from a
legitimate empty result.

**4. Capture evidence.** Two scripts.

- *record*: `start <device> <name>` begins a screen recording of one
  simulator in the background and writes a pid file; `stop <name>` ends it
  with an interrupt signal, because that is what makes the recorder finalise
  the file (a kill truncates it), then fails loudly if the output is
  implausibly small. Clips land in a gitignored directory.
- *publish-evidence*: uploads files as assets on a dedicated, non-latest
  GitHub release used purely as a bucket, prints markdown links, and with
  `--issue N` posts them as a comment on that issue. GitHub has no API for
  issue attachments, so release assets are the only scriptable way to get a
  durable URL an issue can link to.

The rules around them mattered more than the scripts: keep a clip to about
twenty seconds and one claim; always pair it with the per-hop assertions,
since a clip cannot show that a row count never moved or that a stored object
is zero bytes; capture while the state exists. Passes were recorded in a
validation log with a mandatory "scope limits" paragraph, and an entry could
not say PASS for a criterion that did not literally hold.

**5. Report coverage.** A checklist of about twenty behaviours, each marked
pass, fail or not covered on every run, including lines that were known to be
untestable with the issue blocking them. Findings separated "confirmed on
device" from "found by reading code".

**6. Clean up.** The local config override that redirected the app to the test
backend was gitignored and would silently redirect future builds, so the
skill required deleting it or stating in the report that it was still there.

## What generalises

- The table in section 3 is the heart of it. Writing it forces you to name
  the hops, and the bugs live between them.
- The preflight target check is not optional for any app that has a
  production environment an agent could reach.
- Evidence needs a durable home that an issue can link to. Decide where
  before the first QA run, not after the first lost recording.
- The procedure grew almost entirely from failures: each gotcha line was an
  hour someone lost. That is the feedback loop working. A QA gap found in a
  retro is a `[qa-procedure]` proposal.
- The same skill served the QA agent, the reviewer reproducing a PR's
  criteria, and workers gathering evidence. One procedure, three callers, is
  why it is a skill and not part of any agent's role.

## What a different kind of app would change

| App | Bring up | Drive | Hops are typically |
|---|---|---|---|
| Web app | dev server plus a seeded database | a headless browser | request → handler → database → rendered page |
| HTTP API | the service plus its dependencies | HTTP calls from a contract suite | request → validation → write → read-back → emitted events |
| CLI or library | a build | invocations on fixture inputs | input → parse → transform → output on disk |
| Data pipeline | a small fixture dataset | a run of the pipeline | each stage's row counts and checksums |

The sections stay the same. Only their contents change.
