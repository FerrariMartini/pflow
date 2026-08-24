# Versioning and Changelog

## Principle: version per service, not per monorepo

Each service has its own version (`package.json`/`go.mod`) and its own `CHANGELOG.md` — there is no single version number for the entire `payflow-hub`. This reflects the microservices reality: each one is deployed, versioned, and released on an independent cadence (see `docs/technical/ci-cd.md`, "Progressive deploy" section). A single monorepo changelog would mix changes from services that are not even deployed together.

## SemVer (MAJOR.MINOR.PATCH)

| Commit type (Conventional Commits) | Bump | Changelog section |
|---|---|---|
| `fix:` | PATCH | Bug Fixes |
| `feat:` | MINOR | Features |
| `feat!:` or footer `BREAKING CHANGE:` | MAJOR | Breaking Changes |
| `docs:`, `chore:`, `test:`, `refactor:`, `style:` | none | (appear in changelog only as "Other", do not force release) |

The bump is derived automatically from commit history — it is not a number chosen manually on each release. This only works because Conventional Commits is already a mandatory gate in this project (`docs/technical/guidelines/coding-standards.md`, General section) and enforced on commit via `commitlint` + `husky` (`services/payflow-backoffice-api`).

## Tooling

`payflow-backoffice-api` uses [`semantic-release`](https://semantic-release.gitbook.io/): on each merge to the main branch, it analyzes commits since the last tag, calculates the next version, generates `CHANGELOG.md`, and creates the tag — with no manual step. Go services follow the same principle with an equivalent ecosystem tool (`svu` + `git-chglog`), configured along with each service's first release.

## Contract version ≠ package version, but they are related

`docs/contract/contract.md` already defines that a breaking REST contract change requires a new path prefix (`/v2/...`) and a breaking event change requires a new topic/version. The relationship with package SemVer:

- **Every contract version bump is a package MAJOR** — if `/v1` becomes `/v2`, the service necessarily had a `BREAKING CHANGE` in its changelog.
- **Not every package MAJOR changes the public contract** — a large internal refactor (e.g., replacing in-memory repository with Postgres) may justify MAJOR without `/v1` ceasing to exist for the integrator. A refactor of that scale, when implemented as a milestone, has its review note in `.wiz/<slug>/reviews/`.

## Contract deprecation policy

When a contract version is retired (e.g., `/v1` in favor of `/v2`):

1. `/v1` continues responding for at least 6 months after `/v2` is published, deadline communicated in the service changelog when `/v2` ships.
2. `/v1` responses include header `Sunset: <data>` (RFC 8594) from the day `/v2` is published — the integrator is not caught by surprise.
3. Effective removal of `/v1` is itself a `BREAKING CHANGE` recorded in the changelog, even though it is not a behavior change (it is a surface removal).

## Current state

`services/payflow-backoffice-api/CHANGELOG.md` is at 0.1.0, with no breaking changes section — no published contract has changed since the initial version. The `semantic-release` configuration is in `.releaserc.json`, with `npmPublish: false` (the package is private; release produces tag and changelog, not registry publication).
