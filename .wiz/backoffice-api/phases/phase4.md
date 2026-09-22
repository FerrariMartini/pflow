# Phase 4: Deny-by-Default RBAC, Organization Scoping, and Administrative Trail

**Duration**: ~3 days (24 milestones @ 1h each)
**Dependencies**: Phase 3
**Status**: 🚧 TODO

## Goal

Close the authorization model before any data endpoint exists: profile, tenant scope, and append-only logging of every privileged action. Without this phase, no subsequent phase can expose an endpoint.

Main deliverables:
- `RolesGuard` + `@Roles()` decorator validating the 5 profiles (`ADMIN`, `OPERATIONS`, `FINANCE`, `COMPLIANCE`, `SUPPORT`) against the §6 PRD permission matrix, with deny-by-default: endpoint without `@Roles()` and without `@Public()` is denied.
- `AuthContextService` + `@CurrentUser()` decorator exposing `organization_id`, `role`, and `tenant_ids` derived from the JWT.
- `tenant_ids` calculation on login: empty (`{}`) → all active tenants in the Organization; populated → validated subset of active tenants in the Organization.
- `TenantScopeGuard`/helper validating `tenant_id ∈ user.tenant_ids` on every tenant-scoped access, and applying `SET LOCAL app.current_tenant_id` per request for `backoffice-db` RLS queries.
- Explicit `WHERE organization_id = $1` filter pattern for `core-db` access.
- `BackofficeAuditLogService` + interceptor writing append-only to `backoffice_audit_log` (`actor_id`, `actor_email`, `actor_role`, `resource_type`, `resource_id`, `payload_before`, `payload_after`, `ip_address`, `performed_at`) for CREATE, UPDATE, DEACTIVATE, CONFIG_UPDATE, KICK, REINSTATE, and CREDENTIALS_ROTATE, with sensitive field sanitization (OWASP ASVS V7).
- Shared soft delete pattern (`deleted_at` + `deleted_by`).

## Phase Acceptance Criteria

- A test endpoint without `@Roles()` and without `@Public()` returns 403 — deny-by-default proven by e2e test, not convention alone.
- The §6 PRD permission matrix is encoded in a parameterized test table (profile × action) and all cases pass, including negatives.
- A user from one Organization cannot see another Organization's tenant; a user with restricted `tenant_ids` cannot see a tenant outside the list — two distinct integration tests against real compose database (P0 — multi-tenant isolation).
- Empty `tenant_ids` resolves to all active tenants in the Organization on login, and inactive tenant is excluded from the list — covered by unit and integration test.
- Every privileged write generates exactly one record in `backoffice_audit_log`, with sanitized `payload_before`/`payload_after` (`password_hash` and credentials never present) — verified by test.
- `backoffice_audit_log` is append-only: UPDATE/DELETE attempt is blocked at database level, covered by integration test.
- Coverage ≥ 90% on guards, `AuthContextService`, and `BackofficeAuditLogService`; `scripts/pre-commit.sh` green.
- No endpoint from subsequent phases can merge without `@Roles()` — rule documented in service README and verified by deny-by-default test.

## Milestones

<!-- Milestones appended by /wiz-milestones -->

### P04M01: Define `BackofficeRole` enum and `@Roles()` decorator

**Status:** 🚧 TODO
**ID:** P04M01

**Goal**

Create the enum of the five §6 PRD RBAC profiles and the `@Roles()` decorator that annotates authorization metadata on handlers, the base on which `RolesGuard` operates.

**Acceptance Criteria**

- [ ] `src/common/enums/backoffice-role.enum.ts` defines `BackofficeRole` with exactly `ADMIN`, `OPERATIONS`, `FINANCE`, `COMPLIANCE`, and `SUPPORT`
- [ ] `src/common/decorators/roles.decorator.ts` exports `@Roles(...)` via `SetMetadata`, with `ROLES_KEY` exported for `Reflector` consumption
- [ ] Decorator applies to method and class, with method precedence over class documented in JSDoc
- [ ] Signature requires at least one profile, so `@Roles()` with no argument fails at compile time
- [ ] Unit test reads metadata via `Reflector` and validates profiles annotated on handler and controller
- [ ] `npm run lint` and `npm run build` green

---

### P04M02: Encode the §6 PRD permission matrix

**Status:** 🚧 TODO
**ID:** P04M02

**Goal**

Translate the profile × action matrix from §6 PRD into a single typed structure, serving both as the source for decorators on subsequent phase endpoints and as the oracle for authorization tests.

**Acceptance Criteria**

- [ ] `src/common/authorization/permission-matrix.ts` defines type `PermissionAction` with the thirteen §6 actions (deposit query, withdrawal query, CSV export, balancing config, circuit breaker config, kick history, organization management, tenant management, tenant query, BaaS provider management, BaaS provider query, user management, audit trail)
- [ ] `PERMISSION_MATRIX` maps each `PermissionAction` to the exact set of allowed `BackofficeRole`, cell-by-cell identical to the §6 table
- [ ] SUPPORT basic read on deposits and withdrawals is explicitly represented, and `SUPPORT` is denied on CSV export
- [ ] Helper `rolesFor(action: PermissionAction): readonly BackofficeRole[]` exported for direct use in `@Roles()` decorators
- [ ] Structure declared `as const` / `readonly`, no runtime mutation possible
- [ ] Unit test compares matrix to §6 table including denied cells, and fails if any action lacks an entry

---

### P04M03: Implement `RolesGuard`

**Status:** 🚧 TODO
**ID:** P04M03

**Goal**

Deliver the guard that compares the JWT `role` issued in Phase 3 with profiles required by the handler, registered globally immediately after `JwtAuthGuard`.

**Acceptance Criteria**

- [ ] `src/common/guards/roles.guard.ts` resolves handler and class metadata via `Reflector.getAllAndOverride`
- [ ] Request whose `role` is in the required list is allowed; otherwise guard produces 403 with stable `code`, translated by Phase 2 `DomainExceptionFilter`
- [ ] Guard registered as global `APP_GUARD` after `JwtAuthGuard`, so 401 takes precedence over 403 for missing or invalid token
- [ ] Routes annotated with `@Public()` are not evaluated by `RolesGuard`
- [ ] Denial log records `user_id`, `role`, and route, without plaintext PII, per `docs/technical/guidelines/logging.md`
- [ ] Unit tests cover: allowed profile, denied profile, public route, and class metadata overridden on method
- [ ] Coverage ≥ 90% on guard file

---

### P04M04: Prove deny-by-default for handler without `@Roles()`

**Status:** 🚧 TODO
**ID:** P04M04

**Goal**

Ensure an authenticated handler without `@Roles()` and without `@Public()` is denied by the guard — behavior proven by test, not code convention alone.

**Acceptance Criteria**

- [ ] `RolesGuard` denies with 403 when no `ROLES_KEY` metadata exists on handler or class and route is not `@Public()`
- [ ] Test fixture exposes a controller with a handler without `@Roles()` and without `@Public()`
- [ ] E2e test proves 403 on that handler using a valid JWT for each of the five profiles
- [ ] E2e test proves the same handler, when annotated with `@Roles(BackofficeRole.ADMIN)`, responds 200 for ADMIN
- [ ] Fixture lives only in `test/` and is not registered in production `AppModule`
- [ ] Denial response does not reveal which profiles would be required to access the route

---

### P04M05: Parameterized permission matrix test

**Status:** 🚧 TODO
**ID:** P04M05

**Goal**

Cover the entire permission matrix with a parameterized profile × action test table, including all negative cases, so a new action never lacks coverage.

**Acceptance Criteria**

- [ ] Test iterates the Cartesian product of five profiles by `PERMISSION_MATRIX` actions using `it.each`, without manually written cases
- [ ] Each allowed combination results in access granted and each denied combination results in 403
- [ ] Explicit assertion verifies executed case count equals 5 × number of matrix actions
- [ ] Adding an action to `PERMISSION_MATRIX` without corresponding coverage makes the suite fail
- [ ] Negatives include at least SUPPORT on CSV export, OPERATIONS on audit trail, and FINANCE on balancing config
- [ ] Full parameterized suite runs in under 10 seconds

---

### P04M06: Implement `AuthContextService`

**Status:** 🚧 TODO
**ID:** P04M06

**Goal**

Deliver the request-scoped service exposing authenticated context — `organization_id`, `role`, and `tenant_ids` — derived from the JWT, so no service needs to read the `Request` object.

**Acceptance Criteria**

- [ ] `src/common/interfaces/auth-context.interface.ts` defines `IAuthContextService` and type `AuthenticatedUser` with `user_id`, `email`, `organization_id`, `role`, `tenant_ids`, and `jti`
- [ ] `src/common/services/auth-context.service.ts` implements `IAuthContextService` with `REQUEST` scope and is provided by token `'IAuthContextService'`
- [ ] Methods `getUser()`, `getOrganizationId()`, `getRole()`, and `getTenantIds()` available and typed
- [ ] Accessing context on unauthenticated request throws typed `DomainError`, never silently returns `undefined`
- [ ] Service imports nothing from infrastructure, per `docs/technical/guidelines/dependency-injection.md`
- [ ] Unit tests cover present context, absent context, and empty `tenant_ids`; coverage ≥ 90%

---
