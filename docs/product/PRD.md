# PRD — PayFlow Hub

## 1. Context and problem

Companies that process instant payments (e.g., PIX in Brazil) often rely on a single provider/bank to settle transactions. This causes three recurring problems:

1. **Single point of failure**: provider unavailability halts the business payment flow.
2. **Lack of standardization**: each banking integration exposes a different contract, forcing internal systems to know the details of each bank.
3. **Low operational observability**: without a central reconciliation point, it is hard for the operations team (backoffice) to know the real status of a transaction when discrepancies arise.

## 2. Objective

Build a **payment hub** that abstracts multiple settlement providers behind a single internal contract, ensures consistency via asynchronous event-driven processing, and gives operations teams a unified, auditable view of all transactions.

## 3. Personas

- **Integrator (hub client)**: internal systems from other company products that initiate collections (cash-in) or payments (cash-out) through the hub. Goal: integrate once against a stable contract without needing to know the particulars of each banking provider. Current pain: every product that integrates directly with a bank reimplements retry, idempotency, and error handling from scratch.
- **Backoffice operator**: analyst who looks up transaction status, investigates discrepancies, and triggers manual reprocessing when needed. Goal: answer "what happened to transaction X" in seconds, not through a manual investigation across databases. Current pain: without a unified view, they need direct (and risky) access to each service's production database.
- **Settlement provider**: partner bank/institution that actually moves money and notifies the hub via webhook. Not a direct hub user, but defines contract constraints (callback format, confirmation window) that the hub must absorb without leaking them to integrators.
- **SRE / on-call**: responsible for keeping the hub operational; consumes artifacts from `docs/technical/infrastructure/` and `docs/technical/architecture/observability.md`, not the domain code itself.
- **QA**: validates that each delivery meets the acceptance criteria defined in the milestone (`.wiz/<slug>/phases/`, when the service is planned via the PayFlow SDLC Kit), based on `docs/technical/quality/qa-guidelines.md`.

## 3.1 Multi-tenancy

Each integrator is treated as a logical tenant of the hub (there is no dedicated deploy per client). This implies: no query without a filter by `integratorId`, limits (rate limit, amount) configurable per tenant, and no integrator's data accessible to another — see `docs/technical/architecture/security.md` and `docs/technical/infrastructure/aws-architecture.md` for how this is reflected in authentication and infrastructure.

## 4. Functional scope (v1)

| Capability | Description | Responsible service |
|---|---|---|
| Cash-in | Receive collection orders, generate collection at the provider, await confirmation | `payflow-cashin-service` |
| Cash-out | Receive payment/transfer orders, submit to the provider, handle settlement | `payflow-cashout-service` |
| Ingress routing | Authentication, rate limiting, and routing of integrator calls | `payflow-gateway` |
| Outbound notification | Notify integrator systems about status changes via webhook, with retry and HMAC signature | `payflow-webhook-service` |
| Event consistency | Ensure reliable publication of domain events (outbox pattern) | `payflow-outbox-relay` |
| Audit trail | Record every relevant event for compliance and investigation | `payflow-audit-service` |
| Operations/backoffice | Transaction lookup, manual reconciliation, reprocessing, operational metrics | `payflow-backoffice-api` (+ frontend) |

## 5. Out of scope (v1)

- Support for multiple simultaneous providers with routing by cost/SLA (deferred to v2).
- Payment split among multiple beneficiaries.
- Self-service interface for integrators (onboarding is manual/via commercial team).

## 5.1 Non-functional requirements (by priority)

| Priority | Category | Requirement |
|---|---|---|
| P0 — Correctness | No duplicate movement under any retry/network condition | See section 7 (risks) and `docs/technical/guidelines/error-handling.md` |
| P1 — Testing | State machine regression impossible without breaking CI | See `docs/technical/ci-cd.md` and `docs/technical/quality/qa-guidelines.md` |
| P2 — Security | Every entry point authenticated; no sensitive data in logs | See `docs/technical/architecture/security.md`, `docs/technical/guidelines/logging.md` |
| P3 — Quality | Code reviewable in isolation per commit; ADR for every relevant decision | See `docs/technical/guidelines/coding-standards.md`, `docs/decisions/` |
| P4 — Performance | Latency and throughput within SLO per service | See `docs/technical/architecture/observability.md` |

## 6. Success metrics

- p95 latency for cash-in confirmation below 200ms.
- 100% of transactions with a complete audit trail (no lost events).
- Zero undetected discrepancy between internal status and provider status (guaranteed by periodic reconciliation).

## 7. Known risks

- **Duplicate processing**: mitigated by idempotency on all entry endpoints (idempotency key required).
- **Out-of-order events**: mitigated by an explicit state machine per transaction that rejects invalid transitions.
- **Webhook delivery failure**: mitigated by a retry queue with exponential backoff and dead-letter queue.
