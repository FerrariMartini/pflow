# Architecture — Security

## Threat model (summary)

The hub processes financial movement, so the threat model prioritizes: (1) forging/altering a transaction, (2) replaying a legitimate transaction, (3) privilege escalation for administrative operations, (4) leaking transaction data in transit or in logs.

## Authentication and authorization

- **Integrator → Gateway**: HMAC-SHA256 signature over the raw request body (`X-Signature`), with secret per integrator, rotatable without downtime (two valid secrets simultaneously during rotation).
- **Service → Service**: mTLS on the internal mesh (all services behind `payflow-gateway` trust only certificates issued by the cluster's internal CA).
- **Backoffice (human operator)**: OIDC against the company's identity provider; the token carries `role` (e.g. `operator`, `auditor`) used for per-endpoint authorization in `payflow-backoffice-api`.
- **No implicit trust principle between services**: even inside the internal network, each service validates received `correlationId`/claims, and does not assume "came from internal network" is sufficient.

## Idempotency as a security control (not only reliability)

Mandatory `Idempotency-Key` on every write operation is not only protection against network failure — it is also replay mitigation: an attempt to resend a captured request does not generate a second collection/payment.

## Data protection

- No sensitive data (holder document, full banking details) is logged — logs carry only internal identifiers (`transactionId`, `correlationId`, masked `integratorId`).
- Data at rest: at-rest encryption in each service's database; data in transit: TLS 1.2+ on all boundaries, mTLS internally.
- Secrets (HMAC keys, database credentials) never in plain-text environment variables in production — they come from a secrets manager, injected at runtime.

## Audit as a security control

`payflow-audit-service` exists both for operational reconciliation and as a security control: any transaction state change is traceable to an origin event, which is a prerequisite for incident investigation and compliance (trail cannot be altered even by the operations team).

## Surfaces reviewed per service

| Service | Critical surface | Primary control |
|---|---|---|
| `payflow-gateway` | External entry | HMAC + rate limiting |
| `payflow-cashin-service` / `payflow-cashout-service` | Value movement | Idempotency + state machine |
| `payflow-webhook-service` | Outbound to third parties | Payload signature, without exposing data beyond what is necessary |
| `payflow-backoffice-api` | Privileged human action | OIDC + RBAC per endpoint |
| `payflow-audit-service` | Trail of truth | Append-only, no update/delete |
