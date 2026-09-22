# Phase 5: Organizations and Tenants — CRUD, Bearer Token, and Resilient Redis Propagation

**Duration**: ~4 days (34 milestones @ 1h each)
**Dependencies**: Phase 4
**Status**: 🚧 TODO

## Goal

Deliver Organization and Tenant management on `core-db` together with the configuration propagation mechanism to Redis described in PRD §11 and §11.1 — the point where the backoffice stops being read-only and starts feeding the core in real time.

Main deliverables:
- `GET/POST/PUT/DELETE /api/organizations` (ADMIN, soft delete), with unique `slug`.
- `GET /api/tenants`, `GET /api/tenants/:id`, `POST`, `PUT`, `DELETE /api/tenants/:id` — full CRUD with Bearer Token generation in `tenant_auth` (hash + `token_hint`, raw token shown once in create response).
- `TenantConfigPropagationService`: write to `core-db` as source of truth followed by updating keys `tenant:config:*`, `tenant:limits:*`, `tenant:providers:*`, and `routing:weights:*` on Redis Core.
- Local retry with backoff + jitter parameterized by `REDIS_PROPAGATION_MAX_RETRIES`, `REDIS_PROPAGATION_BASE_DELAY_MS`, `REDIS_PROPAGATION_MAX_DELAY_MS`.
- Strong contract (transaction rollback + 500) for tenant creation, provider creation, and bearer token rotation.
- Reconciliation contract (persist in `redis_propagation_outbox` on `core-db` + `redis_propagation_failed` log) for config updates and deletes.
- `POST /api/tenants/:id/resync-redis` (ADMIN) for manual reprocessing.
- `GET /api/health/redis-propagation` exposing `redis_propagation_pending_total`.

## Phase Acceptance Criteria

- Complete organizations and tenants CRUD, with RBAC applied per endpoint per matrix (§6): tenants ADMIN for write and ADMIN+OPERATIONS for read, organizations ADMIN-only — covered by positive and negative e2e test.
- Tenant creation writes `tenant_auth` with Bearer Token hash and `token_hint`; raw token appears once in response and is never stored in plaintext, cached, or logged — verified by test.
- Redis failure on tenant creation performs full rollback on `core-db` and returns 500: no orphan tenant remains persisted — integration test with Redis down/mocked on failure.
- Redis failure on config update/delete persists item in `redis_propagation_outbox`, emits structured `redis_propagation_failed` log, and keeps success response — dedicated integration test.
- Retry applies backoff with jitter and respects the three tuning variables; unit test with fake timers covers exhausted attempts and success on second attempt.
- `POST /api/tenants/:id/resync-redis` rebuilds all tenant keys from `core-db` and clears corresponding outbox items; `GET /api/health/redis-propagation` reflects drop in `redis_propagation_pending_total` — covered by e2e.
- Every write generates a record in `backoffice_audit_log`, and deactivated tenant persists `deleted_at` + `deleted_by`.
- Coverage ≥ 90% in `OrganizationService`, `TenantService`, `TenantConfigPropagationService`, and repositories; `scripts/pre-commit.sh` green.
- `docs/contract/contract.md` updated with organizations and tenants endpoints in the same PR.

## Milestones

<!-- Milestones appended by /wiz-milestones -->
### P05M01: Create Organization entity and repository interface

**Status:** 🚧 TODO
**ID:** P05M01

**Goal**

Model the TypeORM `Organization` entity on the named `core` DataSource, reflecting exactly the schema created in Phase 1 (PRD §7), and declare contract `IOrganizationRepository` in `src/organizations/interfaces/`.

**Acceptance Criteria**

- [ ] `src/organizations/entities/organization.entity.ts` maps `id` (UUID), `name` (varchar 100), `slug` (varchar 50, unique), `active`, `created_at`, `updated_at`, `deleted_at`, `deleted_by`
- [ ] Entity is registered only on `core` DataSource and consumed via `@InjectRepository(Organization, 'core')`
- [ ] `IOrganizationRepository` declares `findAll`, `findById`, `findBySlug`, `create`, `update`, and `softDelete`, with no TypeORM types leaking into signatures
- [ ] Entity extends Phase 1 common `BaseEntity` when that does not conflict with `core-db` schema
- [ ] No infrastructure import in `interfaces/`, per `docs/technical/guidelines/dependency-injection.md`
- [ ] `npm run lint` and `npm run build` pass

---

### P05M02: Implement OrganizationRepository on core DataSource

**Status:** 🚧 TODO
**ID:** P05M02

**Goal**

Implement `OrganizationRepository` against `core-db`, covering query, create, update, and soft delete with `deleted_at` + `deleted_by`.

**Acceptance Criteria**

- [ ] `OrganizationRepository` implements `IOrganizationRepository` and is registered by interface token in `OrganizationModule`
- [ ] All reads exclude records with `deleted_at` set
- [ ] `findBySlug` detects `slug` collision before insert, including deactivated organizations
- [ ] `softDelete(id, actorId)` writes `deleted_at = now()`, `deleted_by = actorId`, and `active = false` in a single operation
- [ ] `update` updates `updated_at` and never allows changing `id` or `created_at`
- [ ] Integration test against compose `postgres-core` covers create, read, update, soft delete, and exclusion of deleted record from listings

---

### P05M03: Implement OrganizationService with slug rules and deactivation

**Status:** 🚧 TODO
**ID:** P05M03

**Goal**

Implement `OrganizationService` (implementing `IOrganizationService`) with business rules for `slug` uniqueness, normalization, and blocking deactivation of an organization that still has active tenants.

**Acceptance Criteria**

- [ ] `create` normalizes `slug` (lowercase, trim) and rejects duplicates with typed `DomainError` `ORGANIZATION_SLUG_ALREADY_EXISTS`
- [ ] `update` rejects `slug` change to a value already used by another organization, with the same `code`
- [ ] `findById` throws `ORGANIZATION_NOT_FOUND` when record does not exist or is soft-deleted
- [ ] `deactivate` throws `ORGANIZATION_HAS_ACTIVE_TENANTS` when active linked tenants exist
- [ ] No `throw new Error(...)` in business flow, per `docs/technical/guidelines/error-handling.md`
- [ ] Service receives `IOrganizationRepository` by interface token, no direct TypeORM access

---

### P05M04: Expose GET/POST/PUT/DELETE /api/organizations restricted to ADMIN

**Status:** 🚧 TODO
**ID:** P05M04

**Goal**

Create input and output DTOs, `OrganizationController`, and `OrganizationModule`, exposing the four organization endpoints exclusively for ADMIN profile per §6 PRD matrix.

**Acceptance Criteria**

- [ ] `CreateOrganizationDto` and `UpdateOrganizationDto` validate `name` (1–100) and `slug` (1–50, pattern `^[a-z0-9-]+$`) with `class-validator`
- [ ] `GET /api/organizations` (paginated with Phase 2 `PaginationDto`), `POST /api/organizations`, `PUT /api/organizations/:id`, and `DELETE /api/organizations/:id` are implemented
- [ ] All four endpoints declare `@Roles('ADMIN')`; none is `@Public()`
- [ ] `DELETE` performs soft delete using `@CurrentUser()` `user_id` as `deleted_by` and responds 204
- [ ] Controller injects only `IOrganizationService` by token, never the repository
- [ ] Endpoints annotated with Swagger decorators, including `docs/contract/contract.md` error envelope

---

### P05M05: Cover OrganizationService and OrganizationRepository with unit tests

**Status:** 🚧 TODO
**ID:** P05M05

**Goal**

Write the organizations unit suite mocking `IOrganizationRepository`, covering happy path and all business errors until reaching phase coverage target.

**Acceptance Criteria**

- [ ] Tests cover `create` (success, duplicate slug, slug normalization), `update` (success, slug in use, not found), `findAll`, `findById`, and `deactivate` (success, with active tenants)
- [ ] Each module `DomainError` has at least one dedicated test, per `docs/technical/quality/qa-guidelines.md`
- [ ] Tests mock repository interface, not concrete class
- [ ] Coverage of `OrganizationService` and `OrganizationRepository` ≥ 90% in statements, branches, and lines
- [ ] `npm run test:cov` passes with no skipped tests (`.skip`, `.todo`) and no `any` in mocks

---

### P05M06: Validate /api/organizations with e2e RBAC and lifecycle tests

**Status:** 🚧 TODO
**ID:** P05M06

**Goal**

Write organizations e2e tests against compose stack, covering full CRUD cycle and negative RBAC behavior for profiles without permission.

**Acceptance Criteria**

- [ ] E2e test covers create → list → get → update → delete with authenticated ADMIN user
- [ ] Parameterized test proves 403 for `OPERATIONS`, `FINANCE`, `COMPLIANCE`, and `SUPPORT` on all four endpoints
- [ ] Request without JWT returns 401 on all module endpoints
- [ ] `POST` with existing `slug` returns status and `code` mapped by `DomainExceptionFilter`
- [ ] After `DELETE`, organization disappears from listings and record persists `deleted_at` and `deleted_by` in `core-db`
- [ ] Each successful write generates exactly one record in `backoffice_audit_log` with `resource_type = 'ORGANIZATION'`

---
