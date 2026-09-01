# Issue tracker: GitHub

Issues and specs live as GitHub issues on `edheltzel/RAM`.

All GitHub operations go through `gh-axi` (`npx -y gh-axi`). Read `npx -y gh-axi --help` and `npx -y gh-axi <command> --help` for current verbs and flags. Do not use raw `gh`.

The clone’s `origin` is the default repo. Pass `-R owner/name` only when operating on a different repository.

## Conventions

- **Create**: `gh-axi issue create --title "..." --body "..."` (or `--body-file`)
- **Read**: `gh-axi issue view <number> --comments`
- **List**: `gh-axi issue list`
- **Comment**: `gh-axi issue comment <number> --body "..."` (or `--body-file`)
- **Labels**: `gh-axi issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh-axi issue close <number>`

Triage label strings: `docs/agents/triage-labels.md`.

## Pull requests as a triage surface

**PRs as a request surface: no.**

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

`gh-axi issue view <number> --comments`.

## Wayfinding

Used by `/wayfinder`. The **map** is one issue; **children** are tickets.

- **Map**: one issue labelled `wayfinder:map` (Notes / Decisions-so-far / Fog).
- **Child**: `gh-axi issue subissue add <map> <child>`. Labels: `wayfinder:<type>` (`research` / `prototype` / `grilling` / `task`). Claim by assigning the driving dev.
- **Blocking**: GitHub native issue dependencies. A ticket is unblocked when every blocker is closed.
- **Frontier**: open children of the map, no open blocker, no assignee; first in map order wins.
- **Resolve**: comment the answer, close the child, append a pointer to the map’s Decisions-so-far.
