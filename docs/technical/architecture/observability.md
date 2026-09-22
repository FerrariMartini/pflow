# Architecture — Observability

## Principle

In an event-driven architecture (see `overview.md`), a transaction crosses multiple services asynchronously — without end-to-end observability, an incident becomes a manual investigation across multiple databases. Observability is not an add-on here, it is a prerequisite of the chosen architecture (ADR-0001).

## Three pillars

### Structured logs
- Every log is structured JSON, never free-form string, with fixed fields: `timestamp`, `level`, `service`, `correlationId`, `transactionId` (when applicable), `message`.
- `correlationId` is generated in `payflow-gateway` at request entry and propagated in every subsequent header/event — it is the primary search key in any investigation.
- See `docs/technical/guidelines/logging.md` for log level conventions and what must never be logged.

### Metrics
- RED (Rate, Errors, Duration) per endpoint on every synchronous service (`gateway`, `backoffice-api`).
- Consumer metrics (partition lag, processing rate, error rate) on every asynchronous service (`cashin`, `cashout`, `webhook`, `outbox-relay`, `audit`).
- Dedicated business metric: rate of unreconciled transactions (`payflow-backoffice-api`) and age of the oldest pending reconciliation — it is the hub's primary operational health indicator, not only technical.

### Distributed tracing
- Every synchronous request and every asynchronous event carries trace context (`traceId`/`spanId`) propagated via header (synchronous) or event payload (asynchronous), enabling reconstruction of a transaction's full journey — from `POST /v1/cash-in` to webhook notification — in a single view.

## Reference SLOs

| Signal | Target |
|---|---|
| p95 latency for cash-in confirmation | < 200ms (see PRD, section 6) |
| Maximum consumer lag in `outbox-relay` | < 10s under normal load |
| Time between event generated and webhook delivery (p95) | < 30s |
| Undetected discrepancy between hub and provider | 0 (guaranteed by automated + manual periodic reconciliation) |

## Instrumentation state

This document defines the design: which signals are collected, with which fields, and against which SLOs. Instrumentation (OpenTelemetry, collector, dashboards, alerts) depends on infrastructure described in `docs/technical/infrastructure/aws-architecture.md` and is tracked as its own work, planned via the PayFlow SDLC Kit (`/wiz-prd`) when prioritized.

The foundation is already in code: `correlationId` and structured log fields defined in `docs/technical/guidelines/logging.md` are present in `payflow-backoffice-api`, which is the starting point for the end-to-end propagation described above.
