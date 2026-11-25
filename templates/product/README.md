# <Product name> product reference

What the product does, screen by screen and flow by flow, written as built.
This is what QA, reviewers and product-design sessions compare the product
against. It is not the engineering guide and not the system design; those
stay the system references, and the pages here link to them.

**This folder is the product truth; design documents and specs are
snapshots.** A design document says what was intended on the day it was
written. A spec says what one change intended. A page here says what the
product does now, and every change that alters that updates the page in the
same PR.

As built on <date> (<default branch> at <short commit>). <One or two
sentences: the top-level shape a new person needs before opening any page:
the tabs or main areas in order, and what a fresh launch opens.>

## How to read a page

Every page has the same seven sections, in this order:

1. **Purpose** - one paragraph: what the area is for and who uses it.
2. **What the user sees** - the screen or flow in order, plus one `Route:`
   line per screen file.
3. **Behaviours** - numbered statements a person with the product in hand
   can check.
4. **States and edge cases** - empty, loading, offline, signed out,
   other-user view, errors.
5. **Data it touches** - in plain terms: what stays on the device, what
   syncs, who can see it.
6. **Known gaps** - links to open issues, "Design intended X; product does Y"
   lines, and "Unknown: ..." lines. Nothing is silently resolved.
7. **Verified by** - the tests, QA-log entries and QA passes behind the
   behaviours, and what they do not cover.

The blank page is [_TEMPLATE.md](_TEMPLATE.md). Copy it, keep the headings
exactly, and follow the writing rules inside it.

## Writing rules (short form)

- Sections 1 to 6 use product terms only: no file paths, function, store,
  log or column names. The single exception is the `Route: <source file>`
  line in section 2, one per screen file. Section 7 may cite test files and
  QA-log entry titles.
- Say what the product does today. If a design document or a merged spec
  says otherwise, write the as-built behaviour and add a Known gaps line:
  "Design intended X (document, section); product does Y; issue #n." File
  the issue with labels `product-doc-drift` and `status:triage`. The issue
  decides which of the two is wrong; the page is never silently edited to
  match either.
- Never invent behaviour. When it cannot be told from the code or the
  documents, write "Unknown: ..." under Known gaps.
- Each behaviour statement must be checkable by a person with the product
  in hand.
- Pages are prose and numbered lists. No screenshots in the repo: they go
  stale faster than text, and QA evidence lives in the QA log.
- A change that alters user-visible behaviour updates the page in the same
  PR. The reviewer gates on it.

## Index line format

One line per page, in this form, in alphabetical order by file name inside
each group:

```
- [Title](file.md) - what the page covers in one sentence. Screens: the
  screens or areas it owns.
```

## Pages

<!-- Group as suits the product: top-level areas, flows, and systems that
     show up on several screens. Every page in this folder except this
     index and the template is listed exactly once. -->

### <Group>

- [<Title>](<file>.md) - <one sentence>. Screens: <screens>.

## Related documents

- `<engineering guide>` - architecture and local bring-up.
- `<system design>` - the design the pages compare against.
- `<QA log>` - dated validation entries cited in section 7.
- `docs/specs/` - per-change specs; their Part 1 sections state intent.
