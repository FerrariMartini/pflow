# Phase 10: Internal User Management and Email Notification

**Duration**: ~3 days (20 milestones @ 1h each)
**Dependencies**: Phase 4
**Status**: 🚧 TODO

## Goal

Deliver backoffice user administration (`src/users/`), including the granular scope control the ADMIN exercises over what each operator sees — the write-side counterpart to scoping implemented in Phase 4.

Main deliverables:
- `GET /api/users` (filters `active`, `roleId`, pagination) and `GET /api/users/:id`, both restricted to the JWT Organization.
- `POST /api/users`: registration with initial password under the password policy, triggering email notification (SES in production, MailHog in dev) with retry/outbox on send failure.
- `PUT /api/users/:id`: profile, scope (`tenantIds`), `active`, and `twoFactorEnabled`.
- `DELETE /api/users/:id`: soft delete (`deleted_at` + `deleted_by`).
- Validation that every supplied `tenantId` belongs to the user's Organization, on `POST` and `PUT`.

## Phase Acceptance Criteria

- All five endpoints are ADMIN-only and return 403 for the other four profiles — covered by e2e.
- An ADMIN cannot read, create, update, or deactivate a user from another Organization — explicit integration test (P0 — isolation).
- `tenantIds` containing a tenant from another Organization or an inactive tenant is rejected with typed `DomainError`, on both `POST` and `PUT`; empty `tenantIds` is accepted and means "all tenants in the Organization".
- Setting `twoFactorEnabled` to `false` for ADMIN or COMPLIANCE user is rejected (2FA is mandatory for those profiles) — edge case with test.
- Email send failure on registration does not lose the created user: the item enters retry/outbox queue and structured `error` log is emitted — test with failing email transport.
- No user response exposes `password_hash`, and no `/api/users` log contains plaintext email.
- Every write generates a record in `backoffice_audit_log` with sanitized `payload_before`/`payload_after`.
- Coverage ≥ 90% in `UserService`; `scripts/pre-commit.sh` green and `docs/contract/contract.md` updated in the same PR.

## Milestones

<!-- Milestones appended by /wiz-milestones -->

### P10M01: Create `src/users/` structure and `BackofficeUser` entity

**Status:** 🚧 TODO
**ID:** P10M01

**Goal**

Create the `src/users/` directory skeleton per PRD §9 and the TypeORM `BackofficeUser` entity, mapping the `backoffice_users` table in `backoffice-db` created in Phase 1, with `password_hash` shielded against serialization.

**Acceptance Criteria**

- [ ] Directories `interfaces/`, `controllers/`, `services/`, `repositories/`, `entities/`, and `dto/` created under `src/users/`
- [ ] `BackofficeUser` maps `id`, `organization_id`, `email`, `name`, `role`, `tenant_ids`, `active`, `two_factor_enabled`, `password_hash`, `deleted_at`, `deleted_by`, `created_at`, and `updated_at`
- [ ] `role` is typed by the enum of the five §6 PRD profiles (`ADMIN`, `OPERATIONS`, `FINANCE`, `COMPLIANCE`, `SUPPORT`), no loose string literal
- [ ] `tenant_ids` mapped as UUID array with default `{}`, per PRD §10
- [ ] `password_hash` declared with `select: false` and `@Exclude()`, so default serialization never exposes it
- [ ] Unit test proves serializing the entity does not produce the `password_hash` key
- [ ] `npm run lint` and `npm run build` pass

---

### P10M02: Define `IUserRepository`, `IUserService`, and `UsersModule`

**Status:** 🚧 TODO
**ID:** P10M02

**Goal**

Declare user module contracts and register providers by injection token, following PRD §9 Hexagonal Light pattern and `docs/technical/guidelines/dependency-injection.md`.

**Acceptance Criteria**

- [ ] `IUserRepository` declares `findManyByOrganization`, `findByIdInOrganization`, `findByEmailInOrganization`, `create`, `update`, and `softDelete`, all typed without `any`
- [ ] `IUserService` declares `list`, `getById`, `create`, `update`, and `deactivate`
- [ ] Every read and write signature receives `organizationId` explicitly — no contract operation allows access without Organization scope
- [ ] `UsersModule` registers `{ provide: 'IUserService', useClass: UserService }` and `{ provide: 'IUserRepository', useClass: UserRepository }`
- [ ] `UserController` injects only `IUserService`; no repository or TypeORM reference in the controller
- [ ] `UsersModule` is imported by `AppModule` and the app boots without orphan provider or circular import
- [ ] `npm run lint` and `npm run build` pass

---

### P10M03: Implement Organization-scoped `UserRepository`

**Status:** 🚧 TODO
**ID:** P10M03

**Goal**

Implement `UserRepository` on `backoffice-db` with all queries filtering `organization_id` and excluding soft-deleted records, covering read and write.

**Acceptance Criteria**

- [ ] Every query applies `WHERE organization_id = :organizationId AND deleted_at IS NULL`, without exception
- [ ] `findManyByOrganization` accepts optional filters `active` and `roleId` plus pagination parameters, returning items and total in a single call
- [ ] Deterministic ordering (`created_at DESC, id DESC`) for stable pagination across pages
- [ ] `findByEmailInOrganization` is case-insensitive and also scoped by Organization
- [ ] `softDelete` writes `deleted_at` and `deleted_by` per Phase 4 pattern, without removing the row
- [ ] `password_hash` is loaded only in the method explicitly used on creation; list and detail queries never fetch it from the database
- [ ] Integration test against compose `backoffice-db` covers filtered listing, detail, create, update, and soft delete
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---

### P10M04: Create user module query and response DTOs

**Status:** 🚧 TODO
**ID:** P10M04

**Goal**

Create `ListUsersQueryDto` (filters `active` and `roleId` on Phase 2 shared pagination) and `UserResponseDto`, ensuring by construction that no response carries `password_hash`.

**Acceptance Criteria**

- [ ] `ListUsersQueryDto` composes Phase 2 `PaginationDto` (default 20, max 100)
- [ ] `active` is optional and accepts boolean only, transformed from `"true"`/`"false"`
- [ ] `roleId` is validated against the five-profile enum; out-of-enum value returns 400 with `docs/contract/contract.md` error envelope
- [ ] `UserResponseDto` exposes exactly `id`, `email`, `name`, `role`, `tenantIds`, `active`, `twoFactorEnabled`, `createdAt`, and `updatedAt` — no other field
- [ ] `UserResponseDto` does not declare `password_hash` or `passwordHash` in any form
- [ ] Query param not declared in the DTO is rejected with 400 by Phase 2 global `forbidNonWhitelisted`
- [ ] Unit test of entity → `UserResponseDto` mapper proves absence of `password_hash` even when the entity loads it populated
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---

### P10M05: Implement `GET /api/users` with filters and pagination

**Status:** 🚧 TODO
**ID:** P10M05

**Goal**

Implement `UserService.list` and the `GET /api/users` endpoint, ADMIN-only, returning only users from the JWT Organization with `active` and `roleId` filters and pagination.

**Acceptance Criteria**

- [ ] `UserService.list` receives Organization from Phase 4 `@CurrentUser()` and never from query param or body
- [ ] `GET /api/users` is decorated with `@Roles('ADMIN')`, per §6 permission matrix
- [ ] Response uses Phase 2 `PaginatedResponseDto` with `items`, `total`, `page`, and `limit`
- [ ] Filters `active` and `roleId` work in isolation and combined
- [ ] Soft-deleted users do not appear in listing
- [ ] Filter with no result returns 200 with empty list, never 404
- [ ] E2e test covers listing without filter, with `active=false`, with `roleId`, with filter yielding no result, and with `limit` above maximum
- [ ] Unit test of `UserService.list` with repository mocked via interface
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---

### P10M06: Implement `GET /api/users/:id`

**Status:** 🚧 TODO
**ID:** P10M06

**Goal**

Implement `UserService.getById` and the `GET /api/users/:id` endpoint, ADMIN-only, restricted to JWT Organization without leaking existence of users from other Organizations.

**Acceptance Criteria**

- [ ] `id` is validated as UUID in path; invalid value returns 400
- [ ] `GET /api/users/:id` is decorated with `@Roles('ADMIN')`
- [ ] User from another Organization returns 404 with typed not-found `DomainError` — never 403 nor message confirming record existence
- [ ] Soft-deleted user returns 404
- [ ] Response is serialized by `UserResponseDto`, without `password_hash`
- [ ] E2e test covers found detail, invalid UUID, nonexistent id, id from another Organization, and soft-deleted user
- [ ] Unit test of `UserService.getById` with repository mocked
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---
