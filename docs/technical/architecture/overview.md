# Architecture — Overview

## Architectural style

Event-driven microservices. The integrator boundary is always REST (HTTPS + HMAC), but **the internal protocol between gateway and domain service changes according to flow nature**: cash-in is synchronous (gRPC), cash-out is asynchronous (command via Kafka). See section "Why cash-in is synchronous and cash-out is asynchronous" below. In both cases, state propagation to the rest of the hub uses the **transactional outbox pattern**, ensuring no event is lost even if failure occurs between database write and broker publication.

```
Integrator
   │ REST (HTTPS + HMAC)
   ▼
┌───────────────────┐
│  payflow-gateway   │  auth, rate limit, routing
└──┬─────────────┬───┘
   │ gRPC          │ publishes payflow.cashout.command.v1
   │ (sync)        │ (async — gateway returns 202 Accepted)
   ▼               ▼
┌──────────┐   ┌─────────────────────────┐
│ cash-in  │   │ payflow.cashout.command │  Kafka
└────┬─────┘   └───────────┬─────────────┘
     │                     ▼
     │               ┌───────────┐
     │               │ cash-out  │  consumes command
     │               └─────┬─────┘
     │ outbox               │ outbox
     ▼                      ▼
┌───────────────────────────────┐
│      payflow-outbox-relay      │  reads outbox, publishes to Kafka, marks sent
└────────────────┬────────────────┘
                 │ domain events
   ┌─────────────┼──────────────┬───────────────┐
   ▼             ▼               ▼               ▼
┌────────┐   ┌───────────┐ ┌────────────┐ ┌──────────────┐
│webhook │   │  audit    │ │ backoffice │ │ (future      │
│service │   │  service  │ │    api     │ │  consumers)  │
└────────┘   └───────────┘ └────────────┘ └──────────────┘
```

## Why cash-in is synchronous and cash-out is asynchronous

The two flows look symmetric (both create a transaction and take it to a settlement provider), but the nature of the response the integrator needs is different — and that guides the internal protocol:

- **Cash-in (gRPC, synchronous)**: the integrator needs data back in the response (e.g., collection reference to display to the end user) to proceed. There is no useful way to respond without waiting for the provider call result — so the gateway calls `payflow-cashin-service` via **gRPC** and only responds to the integrator after the service confirms collection creation.
- **Cash-out (Kafka command, asynchronous)**: the integrator only needs to know the order was accepted, not the immediate settlement result. Decoupling acceptance from processing avoids blocking the HTTP response on provider latency and, more importantly, **reduces double-execution risk**: if the gateway called the provider synchronously and the connection dropped after the provider confirmed but before the response arrived, an integrator retry could generate a second payment. As an asynchronous command with `Idempotency-Key`, an integrator retry is deduplicated before even reaching `payflow-cashout-service`. The gateway responds `202 Accepted` + `transactionId`; final status is queried later (`GET /v1/cash-out/:id`, or uniformly via `payflow-backoffice-api`).

This asymmetry is deliberate, not an inconsistency between the two services — see `docs/contract/contract.md` for protocol detail per service.

## Why this pattern (other decisions)

- **Outbox instead of publishing directly to the broker inside the handler**: avoids the classic problem of "wrote to the database but crashed before publishing the event" (or vice versa). Transaction write and pending event write happen in the same database transaction; a separate process (`outbox-relay`) ensures publication with at-least-once delivery.
- **Gateway as the only entry point**: centralizes authentication and rate limiting, avoiding each domain service reimplementing that logic.
- **Backoffice as consumer, not owner of transactional data**: backoffice-api maintains its own *read model*, built from domain events, optimized for operational lookup (search, filters, pagination) — without coupling the operations team to cash-in/cash-out internal schema.

## Consistency and idempotency

- Every entry call (`POST /cash-in` via gRPC, `POST /cash-out` via Kafka command) requires an `Idempotency-Key`. Repeated requests with the same key return the first execution result without reprocessing — for cash-out, deduplication happens before the command is actually processed, not after.
- Each transaction has an explicit state machine (`created → processing → confirmed | failed | reversed`), and invalid transitions are rejected in the domain layer, not merely validated at the API.

## Observability

- Every domain event carries a `correlation_id` (originated in the gateway request) propagated through all downstream services, enabling end-to-end transaction tracing in logs.
- `payflow-audit-service` persists an immutable copy of every relevant event, serving as the source of truth for investigations — independent of current state in each service.
- See `docs/technical/architecture/observability.md` for the three pillars (logs/metrics/tracing) and reference SLOs.

## Security

See `docs/technical/architecture/security.md` for threat model, authentication per layer (integrator→gateway, service→service, operator→backoffice) and data protection. Idempotency (section above) is also treated there as a security control, not only reliability.

## Infrastructure

See `docs/technical/infrastructure/aws-architecture.md` for infrastructure design (ECS Fargate, MSK, RDS per service, network isolation) and `docs/technical/infrastructure/sre-runbook.md` for incident severities and critical alert runbooks.

## Evolution v1 → v2

**v1 (scope of this repository)**: a single settlement provider behind the hub, multi-tenant isolation only at the application layer (see `docs/technical/infrastructure/aws-architecture.md`), no payment split among beneficiaries (see PRD, section 5 — out of scope v1).

**v2 (out of scope, but already considered in design)**: support for multiple simultaneous providers with routing by cost/SLA — this changes `payflow-cashin-service`/`payflow-cashout-service` from "integrates with one provider" to "chooses among providers", which is why we already isolate the provider client behind its own interface from v1 (Dependency Inversion, see `docs/technical/guidelines/dependency-injection.md`) — swapping/adding a provider should not require rewriting the state machine.

## Detail per service

See `services/<service-name>/README.md` for API contract, published/consumed events, and service-specific decisions. Phase/milestone breakdown for each service lives in `.wiz/<slug>/` from the moment it is planned via the PayFlow SDLC Kit (`/wiz-prd` → `/wiz-phases` → `/wiz-milestones`) — today only `payflow-backoffice-api` (`.wiz/backoffice-api/`) has gone through that process.
