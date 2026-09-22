# Phase 11: Queryable Audit Trail for Compliance

**Duration**: ~2 days (18 milestones @ 1h each)
**Dependencies**: Phase 7 (read model), Phase 4 (RBAC)
**Status**: 🚧 TODO

## Goal

Deliver audit trail query (`src/audit/`), reading `transaction_audit_ledger` — chronological append-only ledger written exclusively by `audit-worker` via Kafka — without conflating it with the administrative action `backoffice_audit_log` from Phase 4.

Main deliverables:
- `GET /api/audit/transactions/:id`: complete chronological history of a transaction (cash-in or cash-out).
- `GET /api/audit`: event trail with period, type, tenant, and direction filters, paginated.
- Repository strictly read-only on `transaction_audit_ledger` (no write path exposed by `backoffice-api`).
- Scoping by `user.tenant_ids` and RLS applied to the trail as well.
- Query indexes by transaction, period, and tenant.

## Phase Acceptance Criteria

- Both endpoints are restricted to ADMIN and COMPLIANCE, denying OPERATIONS, FINANCE, and SUPPORT — covered by e2e.
- `AuditLedgerRepository` exposes no write methods, and an integration test proves the backoffice database user cannot INSERT/UPDATE/DELETE on `transaction_audit_ledger`.
- A transaction history returns events in stable chronological order by `occurredAt` with deterministic tie-break, including the case of events with the same timestamp — edge case with test.
- Querying a transaction from a tenant outside `user.tenant_ids` returns 403/empty per defined contract, never another tenant's data (P0).
- All `GET /api/audit` filters work in isolation and combined; nonexistent transaction returns typed `DomainError` `TRANSACTION_NOT_FOUND`, with test.
- Response respects global interceptor PII masking, including in historical ledger payloads.
- Coverage ≥ 90% in `AuditService` and repository; `scripts/pre-commit.sh` green.
- `docs/contract/contract.md` updated with both endpoints and the distinction between the two ledgers documented in the service README.

## Milestones

<!-- Milestones appended by /wiz-milestones -->
