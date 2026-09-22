# Phase 8: Deposit and Withdrawal Queries with Filters, Pagination, and Profile-Based Masking

**Duration**: ~3 days (24 milestones @ 1h each)
**Dependencies**: Phase 7
**Status**: 🚧 TODO

## Goal

Deliver operational query screens over the read model projected in Phase 7 — the first direct value delivery for Operations, Finance, Compliance, and Support.

Main deliverables:
- `GET /api/deposits` and `GET /api/deposits/:id` (`src/deposits/`).
- `GET /api/withdrawals` and `GET /api/withdrawals/:id` (`src/withdrawals/`).
- Common filters: `tenant_id`, `status`, `provider_id`, `date_from`, `date_to`, `document_number`, `merchant_transaction_id`, `payer_id`.
- Pagination `page` + `limit` (default 20, max 100) using Phase 2 `PaginatedResponseDto`.
- Scoping by `user.tenant_ids` on every query, with `SET LOCAL app.current_tenant_id` (RLS) per request.
- `SUPPORT`-specific rule: basic read, without full `document_number`.
- Query indexes on `backoffice-db` (period, status, tenant, provider) sized for p95 < 500ms target.

## Phase Acceptance Criteria

- All four endpoints are accessible to all 5 profiles per matrix (§6) and deny unauthenticated user — covered by e2e.
- `SUPPORT` receives masked `document_number` while ADMIN/OPERATIONS/FINANCE/COMPLIANCE receive full value — parameterized test by profile, on both listing and detail.
- Query with `tenant_id` outside `user.tenant_ids` returns 403; query without `tenant_id` returns only authorized tenants — two integration tests (P0 — multi-tenant isolation).
- All eight filters work in isolation and combined, including edge cases: inverted date range, `limit` above 100, nonexistent `page`, and filter with no result — each with a test.
- Paginated query over representative test data responds at p95 < 500ms with created indexes, measured by hot-spot benchmark recorded in the repository.
- No sensitive field appears in query log; `MaskingInterceptor` also covers read model fields.
- Coverage ≥ 90% in `DepositService`, `WithdrawalService`, and respective repositories; ≥ 85% on controllers.
- `scripts/pre-commit.sh` green and `docs/contract/contract.md` updated with all four endpoints in the same PR.

## Milestones

<!-- Milestones appended by /wiz-milestones -->
### P08M01: Create base transactional query DTO with eight filters

**Status:** 🚧 TODO
**ID:** P08M01

**Goal**

Create shared `TransactionQueryDto`, extending Phase 2 `PaginationDto`, declaring the eight common §8 PRD filters with `class-validator` validation.

**Acceptance Criteria**

- [ ] `TransactionQueryDto` declares `tenant_id`, `status`, `provider_id`, `date_from`, `date_to`, `document_number`, `merchant_transaction_id`, and `payer_id`, all optional
- [ ] `tenant_id` and `provider_id` validated as UUID; `date_from` and `date_to` as ISO 8601 date with `@Type(() => Date)`
- [ ] `status` validated against read model status enum, rejecting out-of-list value with 400
- [ ] Inherits `page` (default 1, minimum 1) and `limit` (default 20, maximum 100) from Phase 2 `PaginationDto`, without redeclaring rules
- [ ] Global `ValidationPipe` `forbidNonWhitelisted` rejects undeclared query param with 400
- [ ] Unit tests cover, for each filter, one valid value and one rejected value
- [ ] `npm run lint` and `npm run test` green

---

### P08M02: Validate date range and normalize text filters

**Status:** 🚧 TODO
**ID:** P08M02

**Goal**

Add custom validator rejecting inverted date range and normalize text filters before they reach the repository, avoiding format divergence between client and read model.

**Acceptance Criteria**

- [ ] Custom validator `@IsValidDateRange()` on `TransactionQueryDto` rejects `date_from` after `date_to` with 400 and stable `code` from `docs/technical/guidelines/error-handling.md`
- [ ] `document_number` is normalized to digits only (removes CPF punctuation) via `@Transform`, before length validation
- [ ] `merchant_transaction_id` and `payer_id` are trimmed and reject empty string
- [ ] `date_from` without `date_to` (and vice versa) is accepted and treated as open interval
- [ ] Unit tests cover: inverted range, equal range (`date_from == date_to`), open interval on each end, CPF with and without punctuation
- [ ] No `document_number` value appears in log during validation — verified by test
- [ ] `npm run lint` and `npm run test` green

---

### P08M03: Implement shared read model query builder

**Status:** 🚧 TODO
**ID:** P08M03

**Goal**

Create shared `TransactionQueryBuilder` that translates a `TransactionQueryDto` into parameterized TypeORM `WHERE` clauses, reused by deposit and withdrawal repositories.

**Acceptance Criteria**

- [ ] `TransactionQueryBuilder` applies each of the eight filters as parameterized predicate, ignoring absent filters
- [ ] `date_from`/`date_to` are applied on read model period column as closed interval
- [ ] Every query mandatorily receives `tenant_id IN (:...tenantIds)` from user scope, even when no filter is provided
- [ ] No filter value is concatenated into SQL string — parameter binding only (SQL injection prevention, P2)
- [ ] Default stable ordering by descending period with `id` tie-break, ensuring pagination without duplicate rows across pages
- [ ] Unit tests verify generated SQL and parameters for: no filter, each filter in isolation, and all eight combined
- [ ] `npm run lint` and `npm run test` green

---

### P08M04: Apply SET LOCAL app.current_tenant_id per request

**Status:** 🚧 TODO
**ID:** P08M04

**Goal**

Ensure every read model query runs inside a transaction with `SET LOCAL app.current_tenant_id` set from authenticated context, activating RLS created in Phase 1.

**Acceptance Criteria**

- [ ] Dedicated helper/`QueryRunner` opens transaction, executes `SET LOCAL app.current_tenant_id`, then runs read model query
- [ ] Value comes from Phase 4 `AuthContextService`; unauthenticated request never reaches query execution
- [ ] `SET LOCAL` is released at transaction end, without leaking between subsequent requests on the same pool connection — covered by integration test with two sequential requests from distinct tenants
- [ ] Integration test proves query executed without `SET LOCAL` returns no rows (RLS active, P0 — multi-tenant isolation)
- [ ] Error applying `SET LOCAL` results in technical failure with generic 500, without leaking connection detail
- [ ] Coverage ≥ 90% on helper
- [ ] `npm run lint` and `npm run test` green

---

### P08M05: Resolve query tenant scope from user.tenant_ids

**Status:** 🚧 TODO
**ID:** P08M05

**Goal**

Implement query tenant scope resolution: `tenant_id` filter outside `user.tenant_ids` returns 403 and missing `tenant_id` restricts result to authorized tenants.

**Acceptance Criteria**

- [ ] `TransactionScopeResolver` receives optional DTO `tenant_id` and `@CurrentUser()` `tenant_ids` and returns effective tenant list for the query
- [ ] Provided `tenant_id` present in `user.tenant_ids` resolves to single-element list
- [ ] Provided `tenant_id` absent from `user.tenant_ids` throws `DomainError` translated to 403, without revealing whether tenant exists
- [ ] Missing `tenant_id` resolves to all tenants in `user.tenant_ids`
- [ ] Empty `user.tenant_ids` never results in unrestricted query — case is treated as context error, not unrestricted access
- [ ] Unit tests cover all four scenarios above; coverage ≥ 90% on resolver
- [ ] `npm run lint` and `npm run test` green

---

### P08M06: Create deposits module base with entity, interfaces, and response DTOs

**Status:** 🚧 TODO
**ID:** P08M06

**Goal**

Set up `src/deposits/` skeleton following PRD §9 Hexagonal Light pattern: `CashinTransaction` entity, `IDepositRepository`/`IDepositService` interfaces, and listing/detail response DTOs.

**Acceptance Criteria**

- [ ] `CashinTransaction` maps `cashin_transactions` table in `backoffice-db` created in Phase 1, without redefining schema
- [ ] `IDepositRepository` and `IDepositService` declare paginated listing and find-by-id operations in `src/deposits/interfaces/`
- [ ] `DepositsQueryDto` extends `TransactionQueryDto` without adding filters outside the eight common ones
- [ ] `DepositListItemDto` and `DepositDetailDto` explicitly declare exposed fields — no entity field serialized by default
- [ ] Both response DTOs documented with Swagger decorators
- [ ] Entity → DTO mapper covered by unit test, including optional null field
- [ ] `npm run lint`, `npm run build`, and `npm run test` green

---
