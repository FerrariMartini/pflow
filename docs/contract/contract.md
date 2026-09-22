# API contracts — overview

Complete contracts for each service live in `services/<service>/README.md`. This document covers only the shared conventions for all hub endpoints.

## Protocol by communication segment

The external contract (integrator → hub) is always REST. The internal protocol (gateway → domain service) varies by service — see `docs/technical/architecture/overview.md`, section "Why cash-in is synchronous and cash-out is asynchronous", for the full rationale:

| Segment | Protocol | Nature |
|---|---|---|
| Integrator → `payflow-gateway` | REST (HTTPS + HMAC) | — |
| `payflow-gateway` → `payflow-cashin-service` | gRPC (proto in `docs/contract/`) | Synchronous |
| `payflow-gateway` → `payflow-cashout-service` | Kafka command (`payflow.cashout.command.v1`) | Asynchronous |
| `payflow-gateway` → `payflow-backoffice-api` | REST | Synchronous |

## REST conventions

- Every command endpoint (POST) that creates/changes state requires header `Idempotency-Key` (string, UUID recommended).
- Every integrator request is authenticated via HMAC-SHA256 signature in header `X-Signature`, computed over the raw request body with the integrator's secret key.
- Errors follow the format:
  ```json
  {
    "error": {
      "code": "TRANSACTION_ALREADY_CONFIRMED",
      "message": "Transaction already confirmed; reprocessing is not allowed.",
      "correlationId": "..."
    }
  }
  ```
- Contract versioning via path prefix (`/v1/...`); breaking changes require a new prefix, never in-place alteration of an already published contract. Every contract version bump is a `BREAKING CHANGE` in the service changelog and deprecation policy — see `docs/technical/versioning.md`.

## Event conventions (Kafka)

- Topic name: `payflow.<domain>.<event>` (e.g. `payflow.cashin.confirmed`).
- Every event carries `eventId`, `correlationId`, `occurredAt`, `payload`.
- Consumers must be idempotent with respect to `eventId` (at-least-once delivery).

## Command convention (Kafka) — different from event

`payflow.cashout.command.v1` is not a domain event (it does not represent something that already happened) — it is a **command**: an instruction for `payflow-cashout-service` to execute. That is why the name uses `.command.` instead of the `<domain>.<event>` pattern above. It carries the same base fields (`eventId` here acts as `commandId`, `correlationId`, `occurredAt`, `payload`) plus the `Idempotency-Key` received from the integrator, used by the consumer to deduplicate before processing.
