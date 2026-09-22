# Phase 6: BaaS Providers — CRUD, Credentials in Secrets Manager, and Rotation

**Duration**: ~4 days (28 milestones @ 1h each)
**Dependencies**: Phase 5
**Status**: 🚧 TODO

## Goal

Deliver BaaS provider management per tenant with credentials living exclusively in AWS Secrets Manager (LocalStack in dev), respecting the IAM split: `backoffice-api` only writes (`CreateSecret`, `PutSecretValue`) and the core only reads (`GetSecretValue`).

Main deliverables:
- `infrastructure/secrets/` with `ISecretsService` and `SecretsManagerService`, path `payflow/{env}/tenants/{tenant_id}/providers/{provider_code}`.
- `GET /api/tenants/:tid/providers` and `GET /api/tenants/:tid/providers/:pid` (ADMIN, OPERATIONS) — never return credentials, only metadata and mask.
- `POST /api/tenants/:tid/providers` (ADMIN): registers in `provider_configs` and stores credentials in Secrets Manager.
- `PUT /api/tenants/:tid/providers/:pid` (metadata) and `PUT /api/tenants/:tid/providers/:pid/credentials` (rotation — new secret version).
- `DELETE /api/tenants/:tid/providers/:pid` (soft delete) and `POST /api/tenants/:tid/providers/:pid/test-connection`.
- ARN cache in `provider:credentials:arn:{tid}:{code}` on Valkey Auth (TTL 5min) — ARN only, never the secret.
- `POST /api/tenants/:tid/providers/resync-redis` rebuilding the `tenant:providers:{tenant_id}` key on Redis Core, reusing the propagation service from Phase 5 (strong contract on creation, outbox on update/delete).

## Phase Acceptance Criteria

- No provider credential is persisted in database, cache, or log — integration test inspects `provider_configs`, Valkey Auth, and log transport after creation and rotation, proving only the ARN is cached.
- Detail `GET` returns masked credentials and the e2e test confirms no plaintext field crosses the response, for both ADMIN and OPERATIONS.
- Credential rotation creates a new version in Secrets Manager without invalidating core reads during the operation, and generates a `CREDENTIALS_ROTATE` record in `backoffice_audit_log` — covered by test against LocalStack.
- Provider creation with Redis failure performs rollback (strong contract from §11.1); update/delete with Redis failure falls back to `redis_propagation_outbox` — two distinct tests.
- `test-connection` treats timeout, invalid credential, and unavailable provider as distinct typed `DomainError`s, each with a test, and never leaks the raw provider response.
- `POST /api/tenants/:tid/providers/resync-redis` rebuilds `tenant:providers:{tenant_id}` identical to the format in §16.3, verified by integration test.
- RBAC per matrix: write ADMIN-only, read ADMIN+OPERATIONS — negative cases covered.
- Coverage ≥ 90% in `ProviderService` and `SecretsManagerService`; `scripts/pre-commit.sh` green and `docs/contract/contract.md` updated in the same PR.

## Milestones

<!-- Milestones appended by /wiz-milestones -->

### P06M01: Define `ISecretsService` and the secret path resolver

**Status:** 🚧 TODO
**ID:** P06M01

**Goal**

Create in `src/infrastructure/secrets/` the `ISecretsService` interface (injection token) and the helper that builds the canonical path `payflow/{env}/tenants/{tenant_id}/providers/{provider_code}`, with no dependency on the AWS SDK.

**Acceptance Criteria**

- [ ] `src/infrastructure/secrets/interfaces/secrets-service.interface.ts` declares `ISecretsService` with `createProviderSecret`, `rotateProviderSecret`, and `resolveSecretArn`, all typed without `any`
- [ ] The interface exposes only write operations and ARN resolution — no secret value read method exists in the contract
- [ ] Helper `buildProviderSecretName(env, tenantId, providerCode)` produces exactly `payflow/{env}/tenants/{tenant_id}/providers/{provider_code}`
- [ ] The helper normalizes `provider_code` to lowercase and rejects values outside `^[a-z0-9-]{2,40}$` with a typed `DomainError`
- [ ] Unit test covers valid path, case normalization, and invalid `provider_code` cases
- [ ] `npm run lint` and `npm run build` pass

---

### P06M02: Implement `SecretsManagerService` with AWS SDK v3 and secret creation

**Status:** 🚧 TODO
**ID:** P06M02

**Goal**

Implement `SecretsManagerService` on top of `@aws-sdk/client-secrets-manager` (v3), with a client configurable by endpoint (LocalStack in dev) and the `createProviderSecret` operation using `CreateSecretCommand`.

**Acceptance Criteria**

- [ ] `SecretsManagerService` implements `ISecretsService` and receives the SDK v3 client by injection, without instantiating it internally
- [ ] `createProviderSecret` emits `CreateSecretCommand` with the name resolved by the P06M01 helper and `SecretString` containing the credentials JSON
- [ ] The method returns only `{ arn, versionId }` — the credential value is never returned or retained in an instance field
- [ ] The client is created from `AWS_REGION` and the optional endpoint (`AWS_ENDPOINT_URL`) validated in the config module with Zod
- [ ] No log emitted by the service contains `SecretString`, credential key, or credential value
- [ ] Unit test with mocked client covers success and SDK error propagation
- [ ] `npm run lint` and `npm run build` pass

---

### P06M03: Implement rotation via `PutSecretValue` and map AWS errors to `DomainError`

**Status:** 🚧 TODO
**ID:** P06M03

**Goal**

Add `rotateProviderSecret` using `PutSecretValueCommand` (new version of existing secret) and translate SDK failures into typed `DomainError`s from the Phase 2 hierarchy.

**Acceptance Criteria**

- [ ] `rotateProviderSecret` creates a new version of the existing secret without deleting or overwriting previous versions
- [ ] SDK `ResourceNotFoundException` becomes `ProviderSecretNotFoundError`, with stable `code` and mapping to 404
- [ ] `ResourceExistsException` on creation becomes `ProviderSecretAlreadyExistsError` (409) instead of throwing a technical error
- [ ] AWS credential/permission errors (`AccessDeniedException`) become technical failure with generic 500, without exposing the original message in the response
- [ ] The original AWS message is logged only internally, with no fragment of `SecretString`
- [ ] Unit tests cover the four error mappings above
- [ ] `npm run lint` and `npm run build` pass

---

### P06M04: Create `SecretsModule` with token wiring and document the write-only IAM split

**Status:** 🚧 TODO
**ID:** P06M04

**Goal**

Package the secrets infrastructure in a NestJS module that provides `ISecretsService` by interface token, and register in the service README the write-only IAM policy for `backoffice-api`.

**Acceptance Criteria**

- [ ] `SecretsModule` provides `{ provide: 'ISecretsService', useClass: SecretsManagerService }` and exports only the token, never the concrete class
- [ ] The SDK v3 client is registered as its own provider, allowing substitution by a fake in tests
- [ ] Variables `AWS_REGION`, `AWS_ENDPOINT_URL`, and `SECRETS_ENV_PREFIX` are in the Zod config schema, with boot failure if missing outside dev
- [ ] Service README documents that `backoffice-api` uses write-only IAM (`CreateSecret`, `PutSecretValue`) and that `GetSecretValue` is exclusive to the core
- [ ] Integration test proves the service exposes no code path that calls `GetSecretValueCommand`
- [ ] `npm run lint`, `npm run build`, and `npm test` pass

---

### P06M05: Cache the secret ARN in Valkey Auth with a 5-minute TTL

**Status:** 🚧 TODO
**ID:** P06M05

**Goal**

Implement `resolveSecretArn` with cache in `provider:credentials:arn:{tid}:{code}` on Valkey Auth (TTL 300s), storing exclusively the ARN.

**Acceptance Criteria**

- [ ] `resolveSecretArn(tenantId, providerCode)` checks key `provider:credentials:arn:{tid}:{code}` before any AWS call
- [ ] The cached value is only the ARN string — no credential field, secret version, or payload is stored
- [ ] The key is written with a 300-second TTL via Valkey Auth `ICacheService` (`REDIS_AUTH_URL`), never on Redis Core
- [ ] Credential creation and rotation update the key with the resulting ARN
- [ ] Valkey failure on the cache path does not bring down the operation: the ARN is resolved directly and the failure becomes a structured warning log
- [ ] Integration test against compose Valkey confirms key content, TTL, and that no other field was persisted
- [ ] `npm run lint`, `npm run build`, and `npm test` pass

---

### P06M06: Test `SecretsManagerService` end-to-end against LocalStack

**Status:** 🚧 TODO
**ID:** P06M06

**Goal**

Write the `SecretsManagerService` integration suite against LocalStack from `docker-compose.yml`, covering real creation, rotation, and versioning.

**Acceptance Criteria**

- [ ] Test creates a secret at path `payflow/{env}/tenants/{tenant_id}/providers/{provider_code}` and confirms the returned ARN
- [ ] Rotation test confirms a new version was created and the previous version still exists in LocalStack
- [ ] Test confirms recreating the same path returns `ProviderSecretAlreadyExistsError`, not a technical error
- [ ] The suite cleans up created secrets at the end, allowing idempotent re-execution
- [ ] The suite runs within `npm run test:e2e` without requiring manual steps beyond `docker compose up -d`
- [ ] `scripts/pre-commit.sh` passes

---
### P06M07: Model the `ProviderConfig` entity on the `core` DataSource

**Status:** 🚧 TODO
**ID:** P06M07

**Goal**

Create the TypeORM `ProviderConfig` entity mapping `provider_configs` from `core-db`, with metadata fields, soft delete, and credential hint — never the credential itself.

**Acceptance Criteria**

- [ ] `src/providers/entities/provider-config.entity.ts` maps `provider_configs` on the named `core` DataSource
- [ ] Mapped fields: `id`, `tenant_id`, `provider_id`, `base_url`, `active`, `created_at`, `updated_at`, `deleted_at`, `deleted_by`
- [ ] Credential fields (`api_key`, `api_secret`, `client_id`, or equivalents) do not exist on the entity or in the table
- [ ] Only `secret_arn` and `credentials_hint` exist as Secrets Manager references, both without sensitive values
- [ ] `core-db` migration adds `secret_arn`, `credentials_hint`, `deleted_at`, and `deleted_by` if not yet present, idempotently
- [ ] Integration test confirms the entity loads a row seeded per PRD §16.1
- [ ] `npm run lint` and `npm run build` pass

---

### P06M08: Implement `IProviderRepository` and `ProviderConfigRepository` on `core-db`

**Status:** 🚧 TODO
**ID:** P06M08

**Goal**

Create the `provider_configs` repository on the `core` DataSource, with explicit organization filter and exclusion of soft-deleted records.

**Acceptance Criteria**

- [ ] `IProviderRepository` declares `findByTenant`, `findById`, `create`, `update`, `softDelete`, and `findActiveByTenantForRedis`
- [ ] `ProviderConfigRepository` uses `@InjectRepository(ProviderConfig, 'core')` per Phase 1 pattern
- [ ] Every tenant query applies explicit join/filter `WHERE organization_id = $1` on `core-db`, per PRD §10
- [ ] Records with `deleted_at` set do not return from `findByTenant` or `findById`
- [ ] `softDelete` writes `deleted_at` and `deleted_by` instead of removing the row
- [ ] Integration tests against compose `core-db` cover all six methods, including the case of a provider from another organization
- [ ] `npm run lint`, `npm run build`, and `npm test` pass

---

### P06M09: Create provider DTOs with strict validation

**Status:** 🚧 TODO
**ID:** P06M09

**Goal**

Define `CreateProviderDto`, `UpdateProviderDto`, and `CredentialsDto` with `class-validator`, ensuring the global `ValidationPipe` rejects any undeclared field.

**Acceptance Criteria**

- [ ] `CreateProviderDto` validates `provider_id`, `base_url` (valid URL), `active`, and the required `credentials` object
- [ ] `UpdateProviderDto` covers metadata only (`base_url`, `active`) and rejects any credential field with 400
- [ ] `CredentialsDto` validates credential keys as non-empty strings with defined max length, without `any`
- [ ] Credential DTOs are marked for exclusion from logging and response serialization
- [ ] E2e test proves sending `credentials` in `PUT /api/tenants/:tid/providers/:pid` returns 400 from `forbidNonWhitelisted`
- [ ] Unit tests cover valid input and at least three invalid inputs per DTO
- [ ] `npm run lint`, `npm run build`, and `npm test` pass

---

### P06M10: Create the `ProviderService` skeleton, its `DomainError`s, and `ProvidersModule`

**Status:** 🚧 TODO
**ID:** P06M10

**Goal**

Set up the `src/providers/` module with `IProviderService`, empty service injecting repository and `ISecretsService` by token, and the provider domain `DomainError` family.

**Acceptance Criteria**

- [ ] `ProvidersModule` registers `{ provide: 'IProviderService', useClass: ProviderService }` and `{ provide: 'IProviderRepository', useClass: ProviderConfigRepository }`
- [ ] `ProviderService` injects `IProviderRepository`, `ISecretsService`, and the Redis propagation service only by interface token
- [ ] Typed `DomainError`s created: `ProviderNotFoundError` (404), `ProviderAlreadyExistsError` (409), `ProviderInactiveError` (409), and `TenantNotAccessibleError` (403), each with stable `code`
- [ ] No file in `src/providers/services/` imports AWS SDK, `ioredis`, or TypeORM directly
- [ ] `ProvidersModule` is imported in `app.module.ts` and the application starts without DI errors
- [ ] Unit test instantiates `ProviderService` with all interface mocks, proving wiring is substitutable
- [ ] `npm run lint`, `npm run build`, and `npm test` pass

---

### P06M11: Implement credential masking for read responses

**Status:** 🚧 TODO
**ID:** P06M11

**Goal**

Create the mask helper that generates and applies `credentials_hint` (e.g. `dev-****-001`), ensuring no API response exposes plaintext credential values.

**Acceptance Criteria**

- [ ] Helper `maskCredential(value)` preserves at most the first 4 and last 3 characters and masks the rest
- [ ] Values shorter than 8 characters are fully masked, without revealing exact length
- [ ] The hint is computed at creation/rotation time and persisted in `credentials_hint`, without the original value
- [ ] Provider response DTO has no field capable of carrying plaintext credentials, verified by type/serialization test
- [ ] Unit tests cover short value, long value, empty value, and `undefined` value
- [ ] `npm run lint`, `npm run build`, and `npm test` pass

---

### P06M12: Implement `GET /api/tenants/:tid/providers` with RBAC and tenant scope

**Status:** 🚧 TODO
**ID:** P06M12

**Goal**

Deliver tenant provider listing for ADMIN and OPERATIONS, returning metadata only and respecting scope `tenant_id ∈ user.tenant_ids`.

**Acceptance Criteria**

- [ ] `ProviderController` exposes `GET /api/tenants/:tid/providers` with `@Roles('ADMIN', 'OPERATIONS')`
- [ ] The endpoint applies the Phase 4 tenant scope guard/helper and returns 403 for tenant outside `tenant_ids`
- [ ] Response lists `provider_id`, `base_url`, `active`, `created_at`, and `updated_at`, without `secret_arn` or any credential
- [ ] Soft-deleted providers do not appear in the listing
- [ ] Pagination uses shared `PaginationDto` (default 20, max 100)
- [ ] E2e tests cover ADMIN, OPERATIONS, out-of-scope tenant (403), and tenant from another organization (403)
- [ ] `npm run lint`, `npm run build`, `npm test`, and `npm run test:e2e` pass

---

### P06M13: Implement `GET /api/tenants/:tid/providers/:pid` with masked credentials

**Status:** 🚧 TODO
**ID:** P06M13

**Goal**

Deliver provider detail returning metadata and masked `credentials_hint`, with e2e test proving no plaintext field crosses the response.

**Acceptance Criteria**

- [ ] `GET /api/tenants/:tid/providers/:pid` responds with `@Roles('ADMIN', 'OPERATIONS')` and tenant scope applied
- [ ] Response includes masked `credentials_hint` and last rotation indicator, never credential value or `SecretString`
- [ ] `secret_arn` is not exposed in the public endpoint response
- [ ] Nonexistent or soft-deleted provider returns `ProviderNotFoundError` with 404
- [ ] E2e test for ADMIN and OPERATIONS scans the response body and fails if any seeded credential value appears
- [ ] `npm run lint`, `npm run build`, `npm test`, and `npm run test:e2e` pass

---
### P06M14: Implement metadata persistence in `POST /api/tenants/:tid/providers`

**Status:** 🚧 TODO
**ID:** P06M14

**Goal**

Create the provider metadata write path on `core-db` within a transaction, still without Secrets Manager storage, with ADMIN-only RBAC.

**Acceptance Criteria**

- [ ] `POST /api/tenants/:tid/providers` responds with `@Roles('ADMIN')` and returns 403 for OPERATIONS, FINANCE, COMPLIANCE, and SUPPORT
- [ ] Creation runs in a single transaction on `core-db`, writing `tenant_id`, `provider_id`, `base_url`, and `active`
- [ ] Duplicate `provider_id` for the same tenant returns `ProviderAlreadyExistsError` with 409
- [ ] Nonexistent tenant or tenant outside user scope returns 403 before any write
- [ ] No field from the `credentials` object is written to `core-db` at this stage or at any other
- [ ] Integration tests cover successful creation, duplicate, and negative RBAC
- [ ] `npm run lint`, `npm run build`, `npm test`, and `npm run test:e2e` pass

---

### P06M15: Store credentials in Secrets Manager during provider creation

**Status:** 🚧 TODO
**ID:** P06M15

**Goal**

Chain `createProviderSecret` in provider creation, persisting only `secret_arn` and `credentials_hint` on `core-db` and discarding the in-memory value immediately after submission.

**Acceptance Criteria**

- [ ] `ProviderService.create` calls `ISecretsService.createProviderSecret` before confirming the `core-db` transaction
- [ ] Only `secret_arn` and `credentials_hint` are persisted; the `credentials` object is never assigned to the entity
- [ ] Secret storage failure aborts the transaction and no provider remains persisted on `core-db`
- [ ] The returned ARN is written to cache key `provider:credentials:arn:{tid}:{code}` from P06M05
- [ ] No log from any step of the flow contains the `credentials` object, verified by test inspecting log transport
- [ ] Integration test against LocalStack confirms the secret created at the correct path after a successful `POST`
- [ ] `npm run lint`, `npm run build`, `npm test`, and `npm run test:e2e` pass

---

### P06M16: Apply strong Redis propagation contract on provider creation

**Status:** 🚧 TODO
**ID:** P06M16

**Goal**

Reuse Phase 5 `TenantConfigPropagationService` to update `tenant:providers:{tenant_id}` on creation, with full rollback and 500 on Redis failure, per §11.1.

**Acceptance Criteria**

- [ ] After `core-db` persistence, creation updates `tenant:providers:{tenant_id}` on Redis Core via the existing propagation service, without reimplementing the write
- [ ] Redis failure after retry with backoff+jitter rolls back the `core-db` transaction and returns 500
- [ ] No orphan provider remains on `core-db` after rollback, verified by direct query in the test
- [ ] The secret already created in Secrets Manager is logged in structured form as a reconcilable orphan, without exposing content
- [ ] The failure case does not write an item to `redis_propagation_outbox` — creation is strong contract, not reconciliation
- [ ] Integration test with Redis failing covers the full rollback scenario
- [ ] `npm run lint`, `npm run build`, `npm test`, and `npm run test:e2e` pass

---

### P06M17: Implement metadata `PUT /api/tenants/:tid/providers/:pid` with outbox

**Status:** 🚧 TODO
**ID:** P06M17

**Goal**

Deliver provider metadata update (ADMIN) with Redis propagation under reconciliation contract: Redis failure writes to `redis_propagation_outbox` and keeps the success response.

**Acceptance Criteria**

- [ ] `PUT /api/tenants/:tid/providers/:pid` updates `base_url` and `active` with `@Roles('ADMIN')` and tenant scope applied
- [ ] After persistence, key `tenant:providers:{tenant_id}` is rebuilt by the Phase 5 propagation service
- [ ] Redis failure writes an item to `redis_propagation_outbox` on `core-db`, emits log `redis_propagation_failed`, and returns 200
- [ ] No credential field is accepted or changed by this endpoint
- [ ] `GET /api/health/redis-propagation` reflects the increment of `redis_propagation_pending_total` after failure
- [ ] Distinct integration tests cover the happy path and the outbox path
- [ ] `npm run lint`, `npm run build`, `npm test`, and `npm run test:e2e` pass

---

### P06M18: Implement credential rotation in `PUT /:pid/credentials`

**Status:** 🚧 TODO
**ID:** P06M18

**Goal**

Deliver credential rotation by creating a new secret version in Secrets Manager, without invalidating core reads during the operation and without touching provider metadata.

**Acceptance Criteria**

- [ ] `PUT /api/tenants/:tid/providers/:pid/credentials` responds with `@Roles('ADMIN')` and tenant scope applied
- [ ] Rotation uses `PutSecretValue` on the existing secret, creating a new version and keeping the previous accessible to the core until the new one is promoted
- [ ] At no point during the operation is the secret absent or empty for a concurrent core read — integration test performs concurrent reads during rotation and none fail
- [ ] `credentials_hint` and last rotation timestamp are updated on `core-db`; no credential value is persisted
- [ ] Key `provider:credentials:arn:{tid}:{code}` is rewritten with the current ARN and the 5min TTL is renewed
- [ ] Secrets Manager failure during rotation does not change `credentials_hint` on `core-db` and returns a typed error
- [ ] `npm run lint`, `npm run build`, `npm test`, and `npm run test:e2e` pass

---

### P06M19: Register `CREDENTIALS_ROTATE` and other actions in `backoffice_audit_log`

**Status:** 🚧 TODO
**ID:** P06M19

**Goal**

Wire all provider module writes to Phase 4 `BackofficeAuditLogService`, with guaranteed sanitization of credential fields.

**Acceptance Criteria**

- [ ] Creation generates `CREATE`, metadata update generates `UPDATE`, soft delete generates `DEACTIVATE`, and rotation generates `CREDENTIALS_ROTATE` in `backoffice_audit_log`
- [ ] Each record includes `actor_id`, `actor_email`, `actor_role`, `resource_type`, `resource_id`, `payload_before`, `payload_after`, `ip_address`, and `performed_at`
- [ ] `payload_before` and `payload_after` for `CREDENTIALS_ROTATE` contain only hint and timestamp — no credential value, neither before nor after
- [ ] `secret_arn` is omitted or truncated in audit payloads
- [ ] Parameterized test walks all four actions and validates exactly one record per operation
- [ ] Dedicated test scans `backoffice_audit_log` after rotation and fails if any seeded credential appears
- [ ] `npm run lint`, `npm run build`, `npm test`, and `npm run test:e2e` pass

---

### P06M20: Implement `DELETE /api/tenants/:tid/providers/:pid` with soft delete and outbox

**Status:** 🚧 TODO
**ID:** P06M20

**Goal**

Deliver provider deactivation via soft delete (ADMIN), removing it from key `tenant:providers:{tenant_id}` with reconciliation contract on Redis failure.

**Acceptance Criteria**

- [ ] `DELETE /api/tenants/:tid/providers/:pid` writes `deleted_at` and `deleted_by` without removing the row from `core-db`
- [ ] Key `tenant:providers:{tenant_id}` is rebuilt without the deactivated provider
- [ ] Redis failure writes an item to `redis_propagation_outbox`, emits `redis_propagation_failed`, and keeps the success response
- [ ] The secret in Secrets Manager is not deleted by the operation, and this decision is documented in the service README
- [ ] Deactivating an already deactivated provider returns `ProviderNotFoundError` with 404, without generating a new audit record
- [ ] Integration tests cover successful soft delete, outbox path, and double deactivation
- [ ] `npm run lint`, `npm run build`, `npm test`, and `npm run test:e2e` pass

---
