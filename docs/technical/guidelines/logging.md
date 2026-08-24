# Guideline — Logging

## Format

Every log is a single-line JSON object (never free-form `console.log`/`fmt.Println` string in production code), with mandatory minimum fields:

```json
{
  "timestamp": "2026-08-23T14:02:11.482Z",
  "level": "info",
  "service": "payflow-backoffice-api",
  "correlationId": "corr-...",
  "message": "reconciliation.updated"
}
```

## Levels

| Level | When to use |
|---|---|
| `error` | Failure that prevents the operation from completing; always actionable (generates alert in production). |
| `warn` | Anomalous but recoverable situation (e.g., webhook retry before exhausting attempts). |
| `info` | Relevant business event (transaction created, reconciliation recorded) — not "debug log", it is the operational trail. |
| `debug` | Technical detail useful only in active investigation; disabled by default in production. |

## What never to log

- Holder sensitive data (document, full banking details) — see `docs/technical/architecture/security.md`.
- Raw request/response body containing secret (HMAC signature, authentication token).
- Technical error with stack trace at `info` level — stack trace only at `error`, and only in internal log (never in HTTP response).

## correlationId is mandatory

Any log within a transaction lifecycle carries `correlationId` — without it, an incident investigation becomes manual grep across multiple services with no way to connect the dots (see `docs/technical/architecture/observability.md`). A log without `correlationId` in a context that already has one available is considered a defect, not style.

## Sampling

High-volume `info` logs (e.g., healthy consumer heartbeat) use sampling (e.g., 1 in every N) to avoid drowning the search index — but any transaction state change log is never sampled, it is always 100%.
