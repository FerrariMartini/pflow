# CI/CD — pipeline and quality criteria

## Pipeline stages (every service)

```
lint → build → unit test → integration/e2e test → security scan → image build → deploy (dev → staging → prod)
```

Each stage is a **gate**: failure at any one blocks advancement to the next. There is no "merge with red CI and fix later" — if the gate failed, the PR is not eligible for merge.

## Criteria per stage

### 1. Lint / static analysis
- **Acceptance criterion**: zero errors. Warnings are acceptable for items already tracked as explicit technical debt; new code cannot introduce a new warning without justification in the PR.
- Node/TS: ESLint + Prettier (`npm run lint`). Go: `golangci-lint` with custom architecture rule blocking infrastructure imports inside `internal/domain` (see `docs/technical/guidelines/dependency-injection.md`).

### 2. Build
- **Acceptance criterion**: reproducible build from a clean checkout, with no dependency on the developer machine's local state (no "works on my machine").

### 3. Unit tests
- **Acceptance criterion**: minimum 80% coverage in `internal/domain`/`internal/usecase` (Go) and in `src/modules/*/[!.]*.service.ts` (Node) — business rules, not framework boilerplate. Line coverage in infrastructure code (adapters, thin controllers) is not a gate, it is an indicator.
- Every new `DomainError` needs a test covering the path that triggers it (see `docs/technical/guidelines/error-handling.md`).

### 4. Integration / e2e tests
- **Acceptance criterion**: e2e suite brings up the full service (without mocking the service itself) against real or containerized dependencies (Postgres/Kafka via `docker-compose` in CI); services with event contracts have contract tests validating published/consumed schema.

### 5. Security scan
- **Acceptance criterion**: zero `critical`/`high` vulnerabilities without an explicitly approved exception (with remediation deadline); dependency scan (`npm audit`/`govulncheck`) and container image scan before push to registry.

### 6. Image build and push
- Image versioned by commit SHA (never `:latest` in deploy), with SBOM generated and attached to the artifact.

### 7. Progressive deploy
- `dev` automatic on every merge to main branch → `staging` automatic after smoke test in `dev` → `prod` with manual approval (for services that move value: `cashin`, `cashout`) or automatic with canary + automatic rollback by metric (for services without that criticality, e.g. `audit-service`).
- **Automatic rollback criterion**: error rate > 1% or p95 latency above SLO (see `docs/technical/architecture/observability.md`) in the first 10 minutes after deploy triggers automatic rollback, without waiting for human intervention.

## Branch and PR

- No direct push to main branch — all code enters via PR.
- PR requires: 1 human approval + all gates above green. For services that move value (`cashin`, `cashout`, `gateway`), 2 approvals are required.
- Commits follow Conventional Commits (see `docs/technical/guidelines/coding-standards.md`), which feeds automatic changelog per service — see `docs/technical/versioning.md` for commit → version → changelog mapping and tooling used.
