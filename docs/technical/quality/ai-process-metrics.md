# AI process metrics

`ai-augmented-sdlc.md` and review notes describe the process. This document defines what to measure to know whether it is working. This repository does not yet have enough execution (implemented milestones, commit history) to produce real numbers — the metrics below are the process definition to be collected as work advances, not a snapshot of what has already happened.

## Defined metrics

### 1. Review finding rate
% of milestones whose review note (`.wiz/<slug>/reviews/`, produced by `wiz-reviewer` via `/wiz-review-milestone` or `/wiz-review-phase`) recorded at least one finding — not necessarily blocking. A high rate is not bad in itself: it indicates review is actually happening. A **zero** rate over many milestones is a warning signal — superficial review, or findings being omitted.

### 2. Business domain test coverage (not aggregate coverage)
% coverage of classes that carry business rules (`*.service.ts` in Node, `internal/domain`+`internal/usecase` in Go) — not aggregate service coverage, which mixes business rules with framework boilerplate (controller, DTO, module) that unit tests should not need to cover (see `docs/technical/quality/qa-guidelines.md`, test pyramid).

### 3. Post-commit rework rate
% of commits that needed a subsequent correction commit because of something that should already have been caught in review (does not count correction due to requirement change). Distinguished from "finding in review": pre-commit finding is the process working; post-commit correction is the process failing.

### 4. Lead time per milestone
Time between a milestone reaching Definition of Ready (`qa-guidelines.md`) and the commit that closes it. Not yet collected — depends on instrumentation described in Limitations.

### 5. Code origin (AI vs. human)
Not treated as a percentage of lines — that is easy to measure and easy to game (e.g., a human who only accepts 100% of what AI suggests without reading produces the same "% human" as a human who rewrites everything). Treated qualitatively: what AI generated as draft, what the human decided/corrected/rejected, recorded in each milestone's review note (`.wiz/<slug>/reviews/`).

## Current collection limitations

- **Lead time is not yet collected.** Requires timestamps of two events: when the milestone reaches Definition of Ready (`.wiz/<slug>/phases/`) and when the commit that closes it is created. The source is the state in `.wiz/<slug>/` itself (phase → milestone), not an external board.
- **No dashboard.** Collection is manual: read review notes (`.wiz/<slug>/reviews/`) and commit history. Automating requires a job that does that reading periodically and publishes the result in the same product metrics infrastructure (`docs/technical/architecture/observability.md`), not a separate tool.
- **Insufficient execution for inference.** With few implemented milestones, any calculated percentage would describe a sample too small to become a process target — the correct reading of those numbers, when they exist, is "what happened in this phase", not a benchmark.
