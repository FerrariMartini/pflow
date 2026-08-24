## Milestone

- ID: `P<phase>M<milestone>` — e.g. `P02M01` (see `.wiz/<slug>/phases/phase<phase>.md`)
- Context consulted: <link to the guideline(s) in `docs/technical/guidelines/` that govern this implementation — pointed to by `.wiz/context/authoritative-sources.md`>

## What changed and why

<!-- Do not describe "what" only — the diff already shows that. Describe "why", especially if something deviated from the consulted guideline (see review note, if any). -->

## Checklist

- [ ] Lint clean (`npm run lint` / `golangci-lint run`) — see `docs/technical/ci-cd.md`
- [ ] Build passes
- [ ] Tests cover the milestone acceptance criteria, including at least one edge/rejection case
- [ ] No secrets, credentials, or real data introduced
- [ ] API/event contract updated in `docs/contract/contract.md`, if this PR changes contract
- [ ] ADR created in `docs/decisions/`, if this PR involves a relevant architecture decision
- [ ] Language specialist review done before commit (mandatory in `/wiz-next`)
- [ ] If this PR closed a formal audit, review note written in `.wiz/<slug>/reviews/milestone-<id>-review.md`

## Review

<!-- Filled by reviewer: what was checked against applicable guidelines, any findings (even non-blocking), verdict. -->
