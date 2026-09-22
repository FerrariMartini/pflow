# ADR-0002: Backoffice API maintains its own read model, fed by events

**Status**: Accepted

## Context

The operations team needs to query transactions with efficient filters, search, and pagination, without impacting the performance of transactional services (cash-in/cash-out), which are optimized for high-throughput writes, not ad-hoc queries.

## Alternatives considered

1. **Backoffice queries cash-in/cash-out database directly**: couples those services' internal schema to backoffice query needs, and any schema change becomes a coordinated change across teams.
2. **Backoffice exposes a proxy that calls cash-in/cash-out API in real time**: avoids schema coupling, but generates read load on critical write services and causes cascading unavailability.
3. **Backoffice maintains its own read model, populated asynchronously from domain events published via Kafka**: decouples schemas, isolates read load, and the backoffice can model data specifically for operational query patterns (e.g., indexes by period, status, integrator).

## Decision

Adopt option 3. `payflow-backoffice-api` consumes domain events (`transaction.created`, `transaction.confirmed`, `transaction.failed`, etc.) and maintains a denormalized read table optimized for the operations team's lookup and reconciliation use cases.

## Consequences

- Pros: no read pressure on transactional services; free data modeling to optimize queries; temporary backoffice failure does not affect the payment flow.
- Cons: introduces *eventual consistency* — the UI must clearly communicate when data may be a few seconds stale. Also requires reconciliation logic to handle out-of-order or reprocessed events (consumer idempotency).
