# A flow that follows a service's next pages: the `self` source, considered and not built (2026-11-06)

> **Considered, not built.** Reopen it only if a flow over a third-party server truly needs pagination that the tool itself can't do. Sideflow follows pages
> inside its own tools (a `max_pages` argument), so its plans never carry a cursor. If this is reopened it is a T53 amendment, a new D, and an independent read.

## The question

Today a cursor taken from a service's own answer (`next_page`, `page_token`, `cursor`, `offset`) that fills a field of a later call asks for a card on every
page. A flow that follows pages would ask each time.

## What is true today

A cursor field is a field of class "other" (a place or a choice: not plain words, not code). A value filled in from outside (everything the host can't place
as the person's own) makes the line `fullAccessOnly` (`reach_field`): it **stands in Full access** and asks on each call in Ask once and Auto (a card per
page). So in Full access nothing is asked per page; the cost is in the other two modes.

## The design (smallest that would work)

**(a) Recognise it, from the plan alone.** The field's slot root is the line's *own* step name (`{{page.next}}` in the step `page`), the plan says
`goes_round: true`, and the tool is a read (`mutates` false). A chain through other steps, or two steps of one tool, stays outside and asks. A name used
before the step that makes it is read as outside today, so this is a new source class, `self`, ranked between inside and outside: a step whose field moves
from `self` to `outside` is new (coverage), and `self` is never believed where code runs.

**(b) The tool declares the field.** In the input schema of the property, e.g. `"x-sidefolk-cursor": true`, part of the pinned `definition` (a change is new,
T52). An author can always declare their own field, so the declaration proves nothing alone. The real guard is a **run-time shape check** where a call is
matched to its plan step: the value is at most 512 characters of `[A-Za-z0-9_=+-]` (no `/`, `.` or `:`, so no URL or path). Anything else doesn't fit the
plan and asks for a card, as today. A `next_page` that is a full URL stays asking.

**(c) Reach.** No new reach in Full access. In Ask once and Auto it widens from a card per page to a loop of the same pinned tool with an opaque token back to
the same service, bounded by `per_run` and `per_day` (at most 1000), the 256-row cap, and read-only. The card must say it ("follows its own next pages: each
page's token comes from the same service's last answer"), so the one approval shows it. The program's claim that a value came from its own last answer can't
be verified (like `inside` and `claimed`): the shape check is the bound. A page's words can't fit an opaque-token charset, and a steered token only moves
within that service's own data.

**(d) History.** Lossless with one new phrase: the field entry reads `#N cursor: it follows its own earlier answer [from “page”]`; the source entry (the
step itself) is unchanged. One string in nine languages. `plan.check` has nothing to say (it stands).

## Risks

- The provenance claim is the program's (bounded by the shape check and the limits).
- A cursor that is a URL isn't supported.
- A loop without `goes_round` isn't accepted; a mutating tool with a cursor is excluded.
- It touches coverage, the verdict, evaluation, the card and record, call matching and the catalog: about 150 lines in 6–8 files, so it needs its own read.

## The alternative that needs no engine

The tool follows the pages itself (`max_pages`), so the plan never carries a cursor. It works where the author controls the tool (Sideflow's own), not for a
third-party MCP server's tools.
