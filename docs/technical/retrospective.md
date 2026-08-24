# Retrospective and continuous improvement

The other documents (`docs/technical/guidelines/`, `docs/technical/ci-cd.md`) describe the current standard. This document defines **when and how that standard changes** — without this, a guideline becomes a static document nobody revisits, and the same mistake repeats across different services because the lesson from the first time never made it back into the written rule.

## Retrospective triggers

It is not only "after a production incident" — that is too late and too expensive as the sole trigger. Triggers, from cheapest to most costly:

1. **End of a phase** — when closing all milestones in a phase, `/wiz-retro <slug> <phase-number>` revisits that phase's review notes (`.wiz/<slug>/reviews/`) together, not in isolation. An isolated finding is a finding; the same type of finding in two milestones of the same phase is a pattern.
2. **Signal in `docs/technical/quality/ai-process-metrics.md`** — if the review finding rate for a specific deviation type repeats across different services, the guideline (not the implementation) is probably unclear or outdated.
3. **Production incident** (see `docs/technical/infrastructure/sre-runbook.md`) — the most expensive trigger. Every incident whose root cause is traceable to an implementation that followed the guideline correctly, but the guideline was wrong/incomplete, requires a mandatory guideline update as part of incident closure — it is not optional nor phased for "later".

## What to decide in a retrospective

For each revisited finding, the decision is one of these three — and the retro must record explicitly which was chosen, not leave it implicit:

- **Keep as accepted technical debt** — the finding is real, but the cost of generalizing a rule from a single occurrence is greater than the risk of leaving it as is. It remains monitored (the next occurrence of the same pattern becomes an automatic review trigger).
- **Update the guideline** — the finding repeated or the impact justifies changing the written rule, not just one service's code. The corresponding guideline in `docs/technical/guidelines/` is edited and receives, at the end of the file, a history entry: date, reason, and link to the retro that originated the change. A changed guideline without that entry loses traceability of why it changed.
- **Become an ADR** — if the change has relevant architectural trade-offs (not just style/convention), it becomes a new ADR in `docs/decisions/`, not just a silent guideline edit.

## Where retrospectives live

`.wiz/<slug>/retros/phase-<n>-retro.md` — one per closed phase, not one per milestone: milestone granularity is already in review notes at `.wiz/<slug>/reviews/`.

The `/wiz-retro` command delegates to the `wiz-retro-analyst` agent, which reads the phase review notes, groups findings by deviation type, and requires one of the three decisions above for each — including, when the decision is to keep debt, the explicit trigger that would reopen it. `/wiz-retro` and `wiz-retro-analyst` are an extension made in this fork over upstream wiz-cursor, which did not have an equivalent phase-closure command (see `.claude/NOTICE.md`).

## Why this closes the AI-assisted SDLC cycle

Without this mechanism, each new AI session (see `docs/technical/prompt-engineering.md`, context window management) would re-learn — or worse, not re-learn — the same lesson a previous session already paid the price to discover. The retro is what turns a review finding from "information lost in an old conversation" into "persisted rule the next session consults via `.wiz/context/authoritative-sources.md`".
