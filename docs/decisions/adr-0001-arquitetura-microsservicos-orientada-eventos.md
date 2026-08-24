# ADR-0001: Event-driven microservices with outbox pattern

**Status**: Accepted

## Context

The hub needs to integrate multiple internal services (cash-in, cash-out, webhook, audit, backoffice) that evolve at different paces and have distinct availability requirements (e.g., audit service failure must not take down cash-in). We also need to ensure that no transaction "disappears" between payment confirmation and notification of interested systems.

## Alternatives considered

1. **Modular monolith**: simpler to operate initially, but couples the deploy cycle of all domains and does not isolate failures.
2. **Microservices with synchronous calls (REST/gRPC) between them**: easier to reason about, but creates temporal coupling — if `webhook-service` is down, `cash-in` could not depend on it to confirm a transaction.
3. **Event-driven microservices (Kafka) with outbox pattern**: decouples services in time; each service reacts to domain events without depending on consumers' immediate availability.

## Decision

Adopt option 3. Each domain service publishes events through the outbox pattern (writes the pending event in the same database transaction as the state change; a dedicated relay — `outbox-relay` — ensures publication to Kafka).

## Consequences

- Pros: failures in consumer services (webhook, audit) do not block the main payment flow; each service scales and deploys independently.
- Cons: consistency is eventual, not immediate — the backoffice UI may take a few seconds to reflect the latest state. Acceptable given there is no strong consistency requirement for operational lookup.
- Requires investment in observability (end-to-end `correlation_id`) to avoid losing traceability when replacing synchronous calls with events.
