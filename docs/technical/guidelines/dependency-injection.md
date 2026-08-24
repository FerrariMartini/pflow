# Guideline — Dependency injection

## Backoffice (Node.js/NestJS — `payflow-backoffice-api`)

- Use NestJS native DI container (`@Injectable`, constructor injection) — never instantiate dependencies manually inside a service (`new SomeService()`), because that breaks mock substitution in tests and framework-managed lifecycle.
- Infrastructure dependencies (repository, HTTP client, queue client) are injected by **interface/token**, not by concrete implementation — the module decides which real implementation is used; the service depends only on the contract. That is what allows `TransactionsService` to be tested with an in-memory repository without any mock framework (see `transactions.service.spec.ts`).
- Default scope is singleton (`DEFAULT`); use `REQUEST` scope only when there is per-request state that truly cannot be singleton (e.g., authenticated user context) — `REQUEST` scope has performance cost (new instance per request) and should be the exception, not the default.

## CORE (domain services in Go)

- No magic DI framework (no reflection-based container) — manual injection via constructor (`func NewService(repo Repository, publisher EventPublisher) *Service`), following the hexagonal architecture pattern already adopted (`internal/domain`, `internal/usecase`, `internal/adapter`).
- `main.go` (or `cmd/`) is the only place that knows concrete implementations (adapters); everything below depends on an interface defined in the domain/usecase package that consumes it (Dependency Inversion — whoever defines the interface is whoever consumes, not whoever implements).
- This keeps `internal/domain` with no infrastructure imports (neither database driver nor Kafka SDK), which is validated by architecture lint in CI (see `docs/technical/ci-cd.md`).
