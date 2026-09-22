# Coding standards

This document defines the technical boilerplate (versions, lint, format, structure) for the two subproject groups in the hub. For topics with a dedicated guideline, see:

- Dependency injection: `docs/technical/guidelines/dependency-injection.md`
- Error handling: `docs/technical/guidelines/error-handling.md`
- Logging: `docs/technical/guidelines/logging.md`
- CI/CD gates (minimum coverage, lint, security): `docs/technical/ci-cd.md`
- Test strategy (pyramid, Definition of Done): `docs/technical/quality/qa-guidelines.md`

## CORE — domain services in Go

Group: `payflow-gateway`, `payflow-cashin-service`, `payflow-cashout-service`, `payflow-webhook-service`, `payflow-outbox-relay`, `payflow-audit-service`.

| Item | Standard |
|---|---|
| Language | Go 1.25 |
| Lint | `golangci-lint` v2, enabled linters: `errcheck`, `govet`, `staticcheck`, `gosec`, `revive`, `exhaustive` (switch over domain enum must be exhaustive — catches incomplete `TransactionStatus`/`ReconciliationStatus` at lint compile-time, not in production) |
| Format | `gofmt`/`goimports`, no additional configuration — zero style debate |
| Tests | standard library `testing` + `testify` (`require`/`assert`) for readable asserts; case table (`t.Run` per scenario) for state machine rules |
| Structure | `cmd/` (entrypoint) · `internal/domain` · `internal/usecase` · `internal/adapter` (hexagonal architecture, see `dependency-injection.md`) · `migrations/` when the service has its own database |
| Lint timeout in CI | 5 min (see `docs/technical/ci-cd.md`) |

Hexagonal architecture: `internal/{domain,usecase,adapter}`, domain with no dependency on framework or external driver (no HTTP/Kafka library import inside `domain`) — rule enforced by architecture lint in CI, not only by documented convention. Business errors as sentinel types (`var ErrX = errors.New(...)`), never `panic` in business flow (see `error-handling.md`). `context.Context` as first parameter in every function that crosses I/O — mandatory for `correlationId`/deadline propagation. Short package names without redundancy (`cashin`, not `cashinpackage`); no generic `utils`/`common` package accumulating unrelated functions.

## Backoffice — `payflow-backoffice-api`

| Item | Standard |
|---|---|
| Runtime | Node.js 24.x |
| Framework | NestJS 11 |
| Language | TypeScript 5.6, `strict: true` |
| Lint | ESLint 9, flat config (`eslint.config.mjs`) via `typescript-eslint` 8 — see rules below |
| Format | Prettier: `singleQuote`, `trailingComma: all`, `semi: true`, `printWidth: 100`, `tabWidth: 2` |
| Commit hooks | `husky` (`commit-msg`) + `commitlint` (`@commitlint/config-conventional`) — Conventional Commits is **enforced on commit**, not only documented |
| Tests | Jest (unit) + `supertest` (e2e) |
| Structure | `src/modules/<dominio>/{controller,service,dto,entities}` |

Specific lint rules (reason for each, not just the list):
- `@typescript-eslint/no-explicit-any`: `warn` (not `error`) — NestJS uses `any` in some framework points; becomes a review signal, not automatic block.
- `@typescript-eslint/explicit-function-return-type` and `explicit-module-boundary-types`: `off` — NestJS decorators already make return type obvious/verbose to annotate.
- `@typescript-eslint/no-unused-vars`: `error`, with `argsIgnorePattern: '^_'` (allows explicitly unused parameter prefixed with `_`, common in handler signature).
- `no-console`: `warn` — use structured logger (`docs/technical/guidelines/logging.md`), not `console.log`.
- `prefer-const`, `no-var`, `object-shorthand`, `prefer-arrow-callback`: `error` — no debate, they are mechanical replacements without trade-off.

Input DTOs validated with `class-validator`; never trust unvalidated payload inside the service layer. Services do not know HTTP details — that stays exclusively in the controller. Domain errors use typed exceptions (`class X extends DomainError`), never generic `throw new Error(string)` (see `error-handling.md`).

## General (both groups)

### Language

| Artifact | Language |
|---|---|
| Code: identifiers, comments, test descriptions, error messages | English |
| Commit messages and changelog | English |
| Agents and commands in `.claude/` | English |
| Documentation in `docs/`, review notes, retrospectives | English |

Code and history are open-scope technical artifacts — tools, libraries, and future maintainers expect English. Process documentation is written for the team that reads it day to day and is maintained in English for consistency with code and tooling.

### Other conventions

- Commits follow [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`, with scope in parentheses referencing the service (`feat(backoffice-api): ...`).
- No secrets, credentials, or real data in code, commits, or documentation.
- Every relevant architectural decision becomes an ADR before implementation, not after (`docs/decisions/`).
- No API/event contract change without updating `docs/contract/contract.md` in the same PR.
