# <Area name, in plain words>

As built on <date> (<default branch> at <short commit>). <One line: which
screen, area or flow this page describes.>

<!--
Copy this file to docs/product/<name>.md. Keep the seven headings below, with
exactly these titles, in this order. Sections 1 to 6 are written in product
terms: say what a person sees and what the product does. No file paths,
function, store, log or column names. The one exception is the `Route:` line
in section 2, one per screen file this page owns. Section 7 may cite test
files and QA-log entry titles.

Say what the product does today, not what a design document wished. Where a
design document or a merged spec disagrees with the product, write the
as-built behaviour and add a Known gaps line: "Design intended X (document,
section); product does Y; issue #n." File that issue with
`gh issue create --label product-doc-drift --label status:triage`.
Never invent behaviour. When you cannot tell from the code or the documents,
write "Unknown: ..." under Known gaps.

Every behaviour statement must be checkable by a person with the product in
hand.
-->

## Purpose

One paragraph: what this area is for and who uses it (the owner of a record,
someone it was shared with, a new user, a developer).

## What the user sees

The screen or flow walked through in order, top to bottom or step by step.
Name the visible labels and buttons the way they read on screen.

Route: <path-to-screen-file>

(One `Route:` line for every screen file this page owns. A screen file belongs
to exactly one page. A page for a system with no screen of its own has none.)

## Behaviours

Numbered, testable statements. Each one names an action and its visible
result.

1. Tapping <control> does <visible result>.
2. When <condition>, the screen shows <thing>.

## States and edge cases

Empty, loading, offline, signed out, other-user view (a record someone else
owns), permission denied, errors. One short bullet per case, in the same
plain terms.

- Empty: ...
- Offline: ...
- Other-user view: ...

## Data it touches

In plain terms: what is stored on the device only, what syncs, and who can
see it (only me, people I shared with, my linked accounts).

## Known gaps

Links to open issues; nothing is silently resolved here. One line per gap.

- Design intended X (document, section); product does Y; issue #n.
- Unknown: <what could not be determined, and what would settle it>.
- Known bug: <one line>; issue #n.

## Verified by

The tests, QA-log entries (by title) and QA passes that back the behaviours
above, with what each does and does not cover. Write "Not covered by any
recorded pass" when that is the truth.
