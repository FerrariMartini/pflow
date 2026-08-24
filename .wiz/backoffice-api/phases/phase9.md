# Phase 9: Provider Balancing and Circuit Breaker Operations

**Duration**: ~4 days (30 milestones @ 1h each)
**Dependencies**: Phase 5 (Redis propagation), Phase 7 (CB events), Phase 8 (queryable read model)
**Status**: 🚧 TODO

## Goal

Deliver Hub runtime operational control: provider visibility, manual balancing weight adjustment with real-time propagation, and circuit breaker operations (state, thresholds, manual kick and reinstate).

Main deliverables:
- `GET /api/providers` (list by tenant), `GET /api/providers/:id/kicks` (history from `circuit_breaker_events`), and `GET /api/providers/:id/performance` (conversion and volume calculated on-the-fly in V1).
- `GET /api/balancing/:tenant_id` and `PUT /api/balancing/:tenant_id` (weights and `MANUAL` mode), writing to `routing_configs` and propagating `routing:weights:{tenant_id}:{flow_type}` via Phase 5 service.
- Kafka producer for `balancing.recalibrated.v1` when operator adjusts weights manually.
- `GET /api/circuit-breaker/:tenant_id` reading `cb:state:*` and `cb:halfopen:*` from Redis Core (read-only — these keys are written by core).
- `PUT /api/circuit-breaker/:tenant_id/config` writing to `circuit_breaker_configs` (`circuit_breaker_configs:{tenant_id}:{provider_id}:{flow_type}` as official key, never `tenant:config`).
- `POST /api/circuit-breaker/:tenant_id/kick` and `POST /api/circuit-breaker/:tenant_id/reinstate` (body: `provider_id`, `flow_type`).

## Phase Acceptance Criteria

- All 9 endpoints require ADMIN or OPERATIONS and deny FINANCE, COMPLIANCE, and SUPPORT — negatives covered by e2e per §6 matrix.
- `PUT /api/balancing/:tenant_id` validates weight sum and provider set are consistent with tenant's active providers, rejecting with typed `DomainError` in invalid cases (negative weight, nonexistent provider, inactive provider, invalid flow_type) — one test per case.
- Weight adjustment writes to `core-db`, propagates `routing:weights:*` on Redis, and publishes `balancing.recalibrated.v1` with `docs/contract/contract.md` envelope — verified by integration test against Redpanda.
- Redis failure on weight adjustment falls into `redis_propagation_outbox` without losing `core-db` write, and Phase 5 resync rebuilds the key — dedicated test.
- `GET /api/circuit-breaker/:tenant_id` never writes to `cb:state:*`/`cb:halfopen:*`; test proves operation is read-only on those keys.
- Manual kick and reinstate generate record in `backoffice_audit_log` with `KICK`/`REINSTATE`, `actor_*`, and `flow_type`, and are idempotent (kick on already kicked provider does not duplicate state) — covered by test.
- `GET /api/providers/:id/performance` calculates conversion and volume from read model with deterministic result over fixed test data, including zero transactions in period (no division by zero).
- Coverage ≥ 90% in `BalancingService` and `CircuitBreakerService`; `scripts/pre-commit.sh` green and `docs/contract/contract.md` updated in the same PR.

## Milestones

<!-- Milestones appended by /wiz-milestones -->

### P09M01: Map routing and circuit breaker entities on core-db and create `balancing/` module

**Status:** 🚧 TODO
**ID:** P09M01

**Goal**

Map TypeORM entities for `routing_configs` and `circuit_breaker_configs` on `core` connection and create `balancing/` module in PRD §9 Hexagonal Light pattern, leaving DI tokens ready for subsequent milestones.

**Acceptance Criteria**

- [ ] `src/balancing/entities/routing-config.entity.ts` maps `routing_configs` (`tenant_id`, `provider_id`, `flow_type`, `position`, `weight`, `mode`) on `core` connection
- [ ] `src/providers/entities/circuit-breaker-config.entity.ts` maps `circuit_breaker_configs` (`tenant_id`, `provider_id`, `flow_type`, `consecutive_threshold`, `suspension_minutes`) on `core` connection
- [ ] `src/balancing/balancing.module.ts` created with `interfaces/`, `controllers/`, `services/`, `repositories/`, and `dto/` per §9 module pattern
- [ ] Tokens `IBalancingService` and `IBalancingRepository` registered via `provide`/`useClass`; no concrete class injection
- [ ] `providers.module.ts` extended with `ICircuitBreakerService` and `ICBEventRepository` tokens
- [ ] Repositories access entities via `@InjectRepository(Entity, 'core')` and app boots without metadata error
- [ ] `scripts/pre-commit.sh` green

---

### P09M02: Implement provider query by tenant in repository

**Status:** 🚧 TODO

**ID:** P09M02

**Goal**

Implement in provider repository the query powering `GET /api/providers`, reading `provider_configs` on `core-db` already restricted to tenants visible to authenticated user.

**Acceptance Criteria**

- [ ] Method `findByTenant(tenantIds, filters)` in `ProviderConfigRepository` reads `provider_configs` on `core` connection and returns `tenant_id`, `provider_id`, `base_url`, and `active`
- [ ] Optional `tenant_id` filter; without filter, returns only tenants in `user.tenant_ids` (or all organization tenants when `tenant_ids` is empty)
- [ ] Provider from tenant outside user scope never appears in result
- [ ] Records with `deleted_at` set are excluded by default
- [ ] No provider credential is read or returned — metadata only
- [ ] Unit tests with mocked repository cover full scope, restricted scope, and empty result
- [ ] `scripts/pre-commit.sh` green

---

### P09M03: Expose `GET /api/providers`

**Status:** 🚧 TODO
**ID:** P09M03

**Goal**

Publish provider listing endpoint by tenant, restricted to ADMIN and OPERATIONS, with pagination and multi-tenant scope applied.

**Acceptance Criteria**

- [ ] `ProviderController` exposes `GET /api/providers` with `@Roles('ADMIN', 'OPERATIONS')`
- [ ] Query DTO validates optional `tenant_id` (UUID) and pagination `page`/`limit` (default 20, max 100) reusing Phase 2 `PaginationDto`
- [ ] Response uses `PaginatedResponseDto` and exposes `tenant_id`, `provider_id`, `base_url`, and `active`
- [ ] `tenant_id` outside `user.tenant_ids` returns 403 via typed `DomainError`
- [ ] Controller injects only `IProviderService` by token, never repository
- [ ] Positive e2e for ADMIN and OPERATIONS, and 401 without JWT
- [ ] `scripts/pre-commit.sh` green

---

### P09M04: Implement kick history query on `circuit_breaker_events`

**Status:** 🚧 TODO
**ID:** P09M04

**Goal**

Implement in `CBEventRepository` paginated query of provider kick and recovery history from `circuit_breaker_events` table in `backoffice-db`, projected in Phase 7.

**Acceptance Criteria**

- [ ] `CBEventRepository.findKicksByProvider(providerId, tenantIds, filters)` queries `circuit_breaker_events` on primary connection
- [ ] Filters `tenant_id`, `flow_type`, `date_from`, and `date_to` supported, with `page`/`limit` pagination
- [ ] Result ordered by descending `occurred_at`, including event type (kick/recovery), `provider_id`, `flow_type`, reason, and timestamp
- [ ] Query respects `backoffice-db` RLS (`SET LOCAL app.current_tenant_id`) and `user.tenant_ids` scope
- [ ] Support index on (`provider_id`, `occurred_at`) created by migration if not yet present
- [ ] Integration tests on fixed data cover period filter and provider with no events
- [ ] `scripts/pre-commit.sh` green

---

### P09M05: Expose `GET /api/providers/:id/kicks`

**Status:** 🚧 TODO
**ID:** P09M05

**Goal**

Publish provider kick history endpoint for ADMIN and OPERATIONS, with period validation and tenant scope.

**Acceptance Criteria**

- [ ] `GET /api/providers/:id/kicks` exposed on `ProviderController` with `@Roles('ADMIN', 'OPERATIONS')`
- [ ] `:id` resolved as `provider_id` existing for some tenant in user scope; nonexistent returns `PROVIDER_NOT_FOUND` (404)
- [ ] Query DTO validates `tenant_id`, `flow_type` (`CASHIN`|`CASHOUT`), `date_from`, `date_to`, `page`, and `limit`
- [ ] Inverted date range rejected with typed `DomainError` (400)
- [ ] Paginated response, ordered from most recent to oldest event
- [ ] E2e covers ADMIN, OPERATIONS, provider with no kicks, and provider from tenant outside scope (403)
- [ ] `scripts/pre-commit.sh` green

---

### P09M06: Implement conversion and volume calculation on read model

**Status:** 🚧 TODO
**ID:** P09M06

**Goal**

Implement in `ProviderService` on-the-fly conversion and volume calculation per provider from `cashin_transactions` and `cashout_transactions`, handling period with no transactions without division by zero.

**Acceptance Criteria**

- [ ] Method `getPerformance(providerId, tenantIds, period)` aggregates total count, approved, failures, and value sum by `flow_type`
- [ ] Conversion rate calculated as approved/total, rounded with fixed documented precision (2 decimal places)
- [ ] Period with zero transactions returns conversion `0` and zero volume, without exception, division by zero, or `NaN`/`Infinity`
- [ ] Aggregation executed in SQL (`COUNT`/`SUM` with `GROUP BY`), not in memory over full row set
- [ ] Query restricted to given `provider_id` and user scope tenants
- [ ] Unit tests cover total > 0, total = 0, and scenario with failed transactions only
- [ ] `scripts/pre-commit.sh` green

---
