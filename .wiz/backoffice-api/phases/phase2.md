# Phase 2: HTTP Kernel — Typed Errors, Validation, PII Masking, and Secure Edge

**Duration**: ~3 days (22 milestones @ 1h each)
**Dependencies**: Phase 1
**Status**: 🚧 TODO

## Goal

Build the cross-cutting layer (`src/common/`) that every endpoint in subsequent phases will inherit, so no feature needs to reimplement error handling, validation, masking, or security headers — and no future endpoint can bypass these controls.

Main deliverables:
- `DomainError` hierarchy with stable `code` (public contract; see `docs/technical/guidelines/error-handling.md`) and `DomainExceptionFilter` as the single point of translation to HTTP status; `AllExceptionsFilter` for technical failures returning a generic 500 without stack trace.
- Global `ValidationPipe` with `whitelist`, `forbidNonWhitelisted`, and `transform`; input DTOs always validated with `class-validator`.
- `LoggingInterceptor` propagating `correlationId`/`request_id` and the mandatory tags (`tenant_id`, `organization_id`, `user_id`, `trace_id`) to logs and traces.
- Global response `MaskingInterceptor` and PII masking in logs (CPF `***.***.789-01`, email `c***@example.com`, phone `***4321`).
- Helmet.js with OWASP configuration (CSP, HSTS, X-Frame-Options), CORS restricted to `FRONTEND_URL`, global `ThrottlerModule` (100 req/min).
- Shared `PaginationDto` / `PaginatedResponseDto` (default 20, max 100) and `BaseEntity`.
- Swagger/OpenAPI auto-generated via decorators, with the error format from `docs/contract/contract.md` documented.
- `/api` prefix convention and consolidated bootstrap in `main.ts`.

## Phase Acceptance Criteria

- Throwing a `DomainError` from any service produces the `{ error: { code, message, correlationId } }` envelope from `docs/contract/contract.md`, with HTTP mapping in a single filter — verified by e2e test.
- A technical exception (e.g. simulated database unavailable) returns a generic 500, with no stack trace or connection string in the response body, and emits an `error`-level log with stack trace only in the internal log.
- A payload with a field not declared in the DTO is rejected with 400 (`forbidNonWhitelisted`), covered by test.
- A response containing CPF, email, or phone is masked by the `MaskingInterceptor`; unit test covers the three mask formats and the absent-field case.
- No log emitted during an authenticated or anonymous request contains plaintext PII — integration test inspects the log transport.
- Helmet, restricted CORS, and Throttler are active globally; e2e test proves 429 after exceeding the limit and proves the presence of security headers.
- Swagger available in non-production environments, with all common DTOs and the error schema documented.
- Coverage ≥ 90% on filters, interceptors, and pipes that carry rules; `scripts/pre-commit.sh` green.

## Milestones

<!-- Milestones appended by /wiz-milestones -->
### P02M01: Create the `src/common/` structure and `CommonModule`

**Status:** 🚧 TODO
**ID:** P02M01

**Goal**

Create the `src/common/` directory skeleton per PRD §9 (`decorators/`, `guards/`, `interceptors/`, `filters/`, `interfaces/`, `dto/`, `entities/`, `services/`, `errors/`) and the `CommonModule` that centralizes registration of this phase's global providers.

**Acceptance Criteria**

- [ ] `src/common/` directories created exactly with the names from PRD §9, plus `errors/`
- [ ] `src/common/common.module.ts` created as `@Global()` and imported by `AppModule`
- [ ] `CommonModule` compiles with no orphan provider and no circular import
- [ ] Barrel `index.ts` per subdirectory, without re-exporting nonexistent symbols
- [ ] No empty directories left in the commit (every directory has at least a barrel or a real file)
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---

### P02M02: Define the base `DomainError` class and stable code catalog

**Status:** 🚧 TODO
**ID:** P02M02

**Goal**

Implement `src/common/errors/domain-error.ts` with the abstract base class `DomainError` and the stable error code catalog, treating `code` as a public contract per `docs/technical/guidelines/error-handling.md` and `docs/contract/contract.md`.

**Acceptance Criteria**

- [ ] `DomainError` is an abstract class extending `Error`, exposes `readonly code: string`, and accepts `message` and an optional `details?`
- [ ] Instance `name` is the subclass name and the stack trace is captured correctly (`Error.captureStackTrace` / `Object.setPrototypeOf`)
- [ ] Code catalog declared as an `as const` object (e.g. `ERROR_CODES`) with a derived type, in its own file — no loose string literal error codes
- [ ] Catalog includes, at minimum, `TRANSACTION_NOT_FOUND` and `INVALID_RECONCILIATION_TRANSITION` cited in the guideline
- [ ] Comment in the file explicitly states that changing an existing `code` is a contract breaking change and requires API versioning
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---

### P02M03: Create typed `DomainError` subclasses and the code → HTTP status map

**Status:** 🚧 TODO
**ID:** P02M03

**Goal**

Implement typed `DomainError` subclasses by semantic category (not found, invalid input, state conflict, unauthorized, forbidden) and the single map that translates each category to the corresponding HTTP status, with unit tests.

**Acceptance Criteria**

- [ ] Subclasses created covering, at minimum, 404, 400/422, 409, 401, and 403 cases, each receiving a `code` from the catalog
- [ ] Category → HTTP status mapping lives in a single exported module, with no duplicated `switch` in another file
- [ ] Map has an explicit, deterministic fallback for unknown category (never `undefined` reaching the filter)
- [ ] Unit test verifies, for each subclass, the `code`, category, and resolved HTTP status
- [ ] Unit test proves that `instanceof DomainError` is true for all subclasses (inheritance preserved after transpilation)
- [ ] Coverage ≥ 90% in `src/common/errors/` files
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---

### P02M04: Implement `DomainExceptionFilter` with the contract error envelope

**Status:** 🚧 TODO
**ID:** P02M04

**Goal**

Implement `DomainExceptionFilter` as the single point of translation from `DomainError` to HTTP response, producing exactly the `{ error: { code, message, correlationId } }` envelope from `docs/contract/contract.md`, with unit tests.

**Acceptance Criteria**

- [ ] `@Catch(DomainError)` applied; filter resolves HTTP status exclusively via the P02M03 map
- [ ] Serialized response is exactly `{ error: { code, message, correlationId } }` — no extra fields, no duplicated `statusCode` in the body
- [ ] `correlationId` is read from the request context; missing context does not break the filter (generates fallback value and logs `warn`)
- [ ] Business error is logged at `warn` level (not `error`), with `code` and `correlationId`, without stack trace
- [ ] Unit test covers: each error category, presence and absence of `correlationId`, and the exact response body shape
- [ ] No service controller translates `DomainError` to HTTP status on its own — verified by inspection/grep
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---

### P02M05: Implement `AllExceptionsFilter` with generic 500 and no leakage

**Status:** 🚧 TODO
**ID:** P02M05

**Goal**

Implement `AllExceptionsFilter` for technical failure, returning 500 with a generic body (no stack trace, no driver message, no connection string) and recording the full error only in the internal log at `error` level.

**Acceptance Criteria**

- [ ] `@Catch()` with no argument; delegates to Nest native behavior when the exception is already a known 4xx `HttpException`
- [ ] 500 response body uses the same contract envelope, with a generic `code` (e.g. `INTERNAL_ERROR`) and a fixed message that does not derive from the original exception
- [ ] `error`-level log contains the original message, stack trace, and `correlationId` — and is the only place where the stack appears
- [ ] Unit test proves that an exception containing a connection string (`postgres://user:pass@host/db`) exposes none of it in the response body
- [ ] Unit test proves that the response body does not contain the stack trace substring `at ` nor the original exception class name
- [ ] Coverage ≥ 90% in the filter file
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---

### P02M06: Register filters globally and fix precedence order

**Status:** 🚧 TODO
**ID:** P02M06

**Goal**

Register `DomainExceptionFilter` and `AllExceptionsFilter` as global filters via `APP_FILTER` in `CommonModule`, ensuring the specific filter takes precedence over the catch-all, and prove the behavior with e2e test.

**Acceptance Criteria**

- [ ] Both filters registered via `APP_FILTER` (injectable, with logger injected via DI — never instantiated with `new` in `main.ts`)
- [ ] Registration order ensures `DomainError` hits `DomainExceptionFilter`, not the catch-all
- [ ] E2e test with fixture controller: route that throws `DomainError` returns mapped status and contract envelope
- [ ] E2e test with fixture controller: route that throws a generic technical error returns generic 500
- [ ] E2e test proves both bodies carry the same `correlationId` sent in the request header
- [ ] Fixture controllers remain restricted to the test directory, outside the production bundle
- [ ] `npm run lint`, `npm test`, and `npm run test:e2e` pass with no error, failure, or skipped test

---
### P02M07: Configure global `ValidationPipe` and `exceptionFactory` in the envelope

**Status:** 🚧 TODO
**ID:** P02M07

**Goal**

Register the global `ValidationPipe` with `whitelist`, `forbidNonWhitelisted`, and `transform` enabled, and an `exceptionFactory` that converts validation failure into a typed `DomainError`, so the 400 response goes through the same contract error envelope.

**Acceptance Criteria**

- [ ] `ValidationPipe` registered via `APP_PIPE` with `{ whitelist: true, forbidNonWhitelisted: true, transform: true, transformOptions: { enableImplicitConversion: false } }`
- [ ] `enableImplicitConversion` disabled and type conversion done via explicit `@Type()` on DTOs, to avoid masking invalid payload
- [ ] `exceptionFactory` builds a validation `DomainError` with stable `code` (e.g. `VALIDATION_ERROR`) and aggregates invalid fields in `details`
- [ ] Validation response follows the `{ error: { code, message, correlationId } }` envelope, with per-field detail in a dedicated key within `error`
- [ ] Validation messages are in English, per the language policy in `docs/technical/guidelines/coding-standards.md`
- [ ] Unit test of `exceptionFactory` covers simple field error, nested field error, and multiple fields
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---

### P02M08: Test input validation end to end

**Status:** 🚧 TODO
**ID:** P02M08

**Goal**

Write e2e tests that prove global `ValidationPipe` behavior over a fixture DTO, covering rejection of undeclared fields, whitelist removal, `transform` coercion, and success path.

**Acceptance Criteria**

- [ ] E2e test: payload with field not declared in DTO returns 400 with validation `code` (`forbidNonWhitelisted` effect)
- [ ] E2e test: payload with wrong type on declared field returns 400 and names the field in the detail
- [ ] E2e test: valid payload with numeric query string reaches handler already converted by `transform` (`typeof === 'number'`)
- [ ] E2e test: valid payload returns 2xx and expected body
- [ ] E2e test proves 400 body does not echo the raw rejected value when it is a PII field
- [ ] `npm run lint`, `npm test`, and `npm run test:e2e` pass with no error, failure, or skipped test

---

### P02M09: Implement `RequestContextService` and `correlationId` middleware

**Status:** 🚧 TODO
**ID:** P02M09

**Goal**

Create per-request context based on `AsyncLocalStorage` (`src/common/services/`) and middleware that resolves `correlationId`/`request_id` — reusing the incoming header or generating a new UUID — and makes it available to logs, filters, and interceptors without chaining parameters.

**Acceptance Criteria**

- [ ] `RequestContextService` implemented on `AsyncLocalStorage`, exposed via interface/token per `docs/technical/guidelines/dependency-injection.md`
- [ ] Middleware reads `x-correlation-id` (or `x-request-id`) from the request and generates UUID v4 when absent
- [ ] Resolved `correlationId` is returned in the response header, allowing the client to correlate the incident
- [ ] Context exposes `correlationId`, `request_id`, `tenant_id`, `organization_id`, `user_id`, and `trace_id`, with identity fields optional in this phase (filled by Phase 3)
- [ ] Reading context outside a request returns `undefined` safely, without throwing
- [ ] Provider scope remains singleton (`DEFAULT`); no `REQUEST` provider introduced
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---

### P02M10: Implement `LoggingInterceptor` with mandatory tags

**Status:** 🚧 TODO
**ID:** P02M10

**Goal**

Implement the global `LoggingInterceptor` that logs start and end of each request in structured JSON, carrying `correlationId` and the mandatory tags `tenant_id`, `organization_id`, `user_id`, `request_id`, and `trace_id` from PRD §7.

**Acceptance Criteria**

- [ ] Interceptor registered via `APP_INTERCEPTOR` in `CommonModule`, with Winston logger injected via interface/token
- [ ] Completion log includes method, route, HTTP status, and duration in milliseconds
- [ ] All five mandatory tags are present in every log emitted in the request cycle, with explicit `null` when not yet available — never a missing key
- [ ] `trace_id` is obtained from `dd-trace-js` when an active span exists, without breaking when the tracer is disabled in tests
- [ ] `info` level for 2xx/3xx, `warn` for 4xx, and `error` for 5xx, per `docs/technical/guidelines/logging.md`
- [ ] Request and response bodies are not logged at any level
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---

### P02M11: Test `correlationId` propagation and `LoggingInterceptor` tags

**Status:** 🚧 TODO
**ID:** P02M11

**Goal**

Cover context middleware and `LoggingInterceptor` with tests, proving end-to-end `correlationId` propagation and invariant presence of mandatory tags.

**Acceptance Criteria**

- [ ] Unit test: `correlationId` received in header is preserved; when absent, a valid UUID v4 is generated
- [ ] Unit test: the same `correlationId` appears in request log, response log, and response header
- [ ] Unit test verifies presence of the five mandatory tags in each captured log transport record
- [ ] Unit test covers log level selection for 200, 400, and 500
- [ ] Unit test proves context does not leak between concurrent requests (two parallel executions keep distinct `correlationId` values)
- [ ] Coverage ≥ 90% on `LoggingInterceptor` and `RequestContextService`
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---

### P02M12: Implement PII masking utilities

**Status:** 🚧 TODO
**ID:** P02M12

**Goal**

Implement pure masking functions for CPF, email, and phone with the exact format defined in PRD §7, along with exhaustive unit tests for each format and edge cases.

**Acceptance Criteria**

- [ ] `maskCpf` produces `***.***.789-01` from CPF with and without punctuation
- [ ] `maskEmail` produces `c***@example.com`, preserving the first character of the local part and the full domain
- [ ] `maskPhone` produces `***4321`, preserving the last four digits regardless of formatting and country code
- [ ] Each function is pure, with no I/O and no framework dependency, and returns full mask when the value is too short to preserve the suffix
- [ ] `null`, `undefined`, empty string, or out-of-format input does not throw and returns a safe masked value (never the original value)
- [ ] Table-driven unit test covers the three formats, each edge case above, and idempotency (masking an already masked value does not corrupt it)
- [ ] 100% coverage on masking utilities
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---
### P02M13: Implement global response `MaskingInterceptor`

**Status:** 🚧 TODO
**ID:** P02M13

**Goal**

Implement the global `MaskingInterceptor` that applies P02M12 utilities to the response body, identifying PII fields by naming convention and explicit decorator, without each module needing to remember to mask.

**Acceptance Criteria**

- [ ] Interceptor registered via `APP_INTERCEPTOR`, running after the handler and before serialization
- [ ] `@MaskPii(type)` decorator available to mark DTO/entity property, with types `cpf`, `email`, and `phone`
- [ ] List of field names recognized by convention (`cpf`, `document`, `email`, `phone`, `msisdn`) configured in a single place
- [ ] Traverses nested objects, arrays, and the `data` field of paginated responses, preserving structure and non-PII types
- [ ] Absent field, `null`, or non-string value is ignored without throwing
- [ ] Maximum traversal depth limited and circular references handled, to avoid hanging on malformed payload
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---

### P02M14: Test `MaskingInterceptor` on nested payloads and collections

**Status:** 🚧 TODO
**ID:** P02M14

**Goal**

Cover `MaskingInterceptor` with tests, proving the three mask formats in the HTTP response, behavior on nested structure, and the absent-field case required by phase criteria.

**Acceptance Criteria**

- [ ] Unit test: simple response containing `cpf`, `email`, and `phone` exits with the three exact masks from PRD §7
- [ ] Unit test: object nested two levels deep and array of objects are masked in all elements
- [ ] Unit test: absent PII field in payload does not cause error or add a new key to the response
- [ ] Unit test: field marked with `@MaskPii` but with non-conventional name is also masked
- [ ] E2e test: a fixture route returning PII responds already masked through the full pipeline
- [ ] Coverage ≥ 90% on `MaskingInterceptor`
- [ ] `npm run lint`, `npm test`, and `npm run test:e2e` pass with no error, failure, or skipped test

---

### P02M15: Apply PII masking to Winston logger and test log transport

**Status:** 🚧 TODO
**ID:** P02M15

**Goal**

Add a masking formatter to the Winston pipeline, so no log emitted during a request carries plaintext CPF, email, or phone, and prove this with an integration test that inspects the log transport.

**Acceptance Criteria**

- [ ] Masking formatter chained in Winston before the JSON formatter, applied to both `message` and structured metadata
- [ ] Formatter reuses P02M12 utilities — no duplicated masking regex in logger code
- [ ] Secrets and credentials (`password`, `token`, `authorization`, `secret`, `x-signature`) are fully redacted, per `docs/technical/guidelines/logging.md`
- [ ] Integration test with in-memory transport: request carrying PII produces logs with no occurrence of the original value
- [ ] Integration test covers anonymous request and request with populated user context
- [ ] Test proves formatter cost does not alter log structure (mandatory fields `timestamp`, `level`, `service`, `correlationId` intact)
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---

### P02M16: Configure Helmet with OWASP profile and CORS restricted to `FRONTEND_URL`

**Status:** 🚧 TODO
**ID:** P02M16

**Goal**

Apply Helmet.js with OWASP configuration (CSP, HSTS, X-Frame-Options, and other headers) and restrict CORS exclusively to the `FRONTEND_URL` origin, with credentials enabled for the HttpOnly cookie that Phase 3 will emit.

**Acceptance Criteria**

- [ ] Helmet enabled in bootstrap with explicit CSP (no `unsafe-inline` in `script-src`), HSTS with `includeSubDomains`, and `X-Frame-Options: DENY`
- [ ] `x-powered-by` removed from response
- [ ] CORS accepts only the `FRONTEND_URL` origin, with `credentials: true` and explicit list of allowed methods and headers — never `origin: true` or `*`
- [ ] `FRONTEND_URL` is read from the Zod-validated configuration module from Phase 1; missing variable fails boot
- [ ] Swagger still loads in non-production despite CSP (documented exception restricted to docs route)
- [ ] Helmet and CORS configuration lives in bootstrap, not spread across modules
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---

### P02M17: Configure global `ThrottlerModule` and 429 envelope

**Status:** 🚧 TODO
**ID:** P02M17

**Goal**

Register global `ThrottlerModule` with a limit of 100 requests per minute and translate `ThrottlerException` to the contract error envelope, maintaining a single error format across the API.

**Acceptance Criteria**

- [ ] `ThrottlerModule` configured with `ttl` of 60 s and `limit` of 100, both values from the configuration module with that default
- [ ] `ThrottlerGuard` registered as global guard via `APP_GUARD`
- [ ] `ThrottlerException` translated to `{ error: { code, message, correlationId } }` envelope with stable `code` (e.g. `RATE_LIMIT_EXCEEDED`) and status 429
- [ ] Rate limit headers (`Retry-After` and equivalents) present on 429 response
- [ ] Exemption decorator (`@SkipThrottle()`) applied only to health check, with reason commented
- [ ] Limit exceeded generates `warn` log with `correlationId` and caller identifier — no PII
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---

### P02M18: Test secure edge end to end

**Status:** 🚧 TODO
**ID:** P02M18

**Goal**

Write e2e tests that prove Helmet, restricted CORS, and Throttler are active globally, covering the phase acceptance criterion on security headers and 429 response.

**Acceptance Criteria**

- [ ] E2e test verifies presence and value of `Content-Security-Policy`, `Strict-Transport-Security`, and `X-Frame-Options` on any response
- [ ] E2e test verifies `x-powered-by` is absent
- [ ] E2e test: request with `Origin` different from `FRONTEND_URL` does not receive permissive `Access-Control-Allow-Origin`
- [ ] E2e test: exceeding configured limit returns 429 with contract error envelope
- [ ] E2e test proves health check is not blocked by throttler
- [ ] Limit used in test comes from reduced configuration in test environment, without firing 100 real requests or fixed `sleep`
- [ ] `npm run lint`, `npm test`, and `npm run test:e2e` pass with no error, failure, or skipped test

---
### P02M19: Create `PaginationDto`, `PaginatedResponseDto`, and `BaseEntity`

**Status:** 🚧 TODO
**ID:** P02M19

**Goal**

Implement shared pagination contracts (`src/common/dto/`) with default 20 and maximum 100 items per page, and `BaseEntity` (`id`, `created_at`, `updated_at`) that entities in subsequent phases will extend.

**Acceptance Criteria**

- [ ] `PaginationDto` exposes `page` (default 1, minimum 1) and `limit` (default 20, minimum 1, maximum 100), validated by `class-validator` and converted by `@Type(() => Number)`
- [ ] `limit` above 100 is rejected with 400 by `ValidationPipe` — not silently truncated
- [ ] `PaginatedResponseDto<T>` is generic and exposes `data: T[]` plus metadata `page`, `limit`, `total`, and `total_pages`
- [ ] `total_pages` is derived and correct for zero, exact, and non-multiple-of-`limit` totals
- [ ] `BaseEntity` defines `id` (UUID), `created_at`, and `updated_at` with corresponding TypeORM columns, ready to be extended
- [ ] Unit test covers defaults, boundary limits (0, 1, 100, 101), and `total_pages` calculation
- [ ] `npm run lint` and `npm test` pass with no error, failure, or skipped test

---

### P02M20: Configure Swagger/OpenAPI with documented error schema

**Status:** 🚧 TODO
**ID:** P02M20

**Goal**

Configure decorator-driven auto-generated Swagger, available only in non-production environments, documenting common DTOs and the `{ error: { code, message, correlationId } }` envelope from `docs/contract/contract.md` as the API default response.

**Acceptance Criteria**

- [ ] `SwaggerModule` configured in bootstrap with service title, version, and description, served on a route under the `/api` prefix
- [ ] Swagger is mounted only when environment is not production, verified by test
- [ ] An `ErrorResponseDto` documents the `{ error: { code, message, correlationId } }` envelope and is registered as a reusable schema
- [ ] 400, 401, 403, 404, 429, and 500 responses declared as global default pointing to `ErrorResponseDto`, without repetition per controller
- [ ] `PaginationDto` and `PaginatedResponseDto` appear in schema with limits (default 20, max 100) described
- [ ] Swagger CLI plugin enabled in `nest-cli.json` to infer types without polluting DTOs with redundant decorators
- [ ] `npm run lint`, `npm test`, and `npm run test:e2e` pass with no error, failure, or skipped test

---

### P02M21: Consolidate `main.ts` and publish error code catalog

**Status:** 🚧 TODO
**ID:** P02M21

**Goal**

Consolidate bootstrap in `main.ts` with global `/api` prefix and correct initialization order for this phase's controls, and register the error code catalog in `docs/contract/contract.md`, per the rule of not changing contract without updating documentation in the same PR.

**Acceptance Criteria**

- [ ] `setGlobalPrefix('api')` applied once, with health route still responding at `GET /api/health`
- [ ] Explicit, commented bootstrap order: validated config → Helmet → CORS → global prefix → Swagger (non-production) → listen
- [ ] Global filters, pipe, guard, and interceptors registered via DI in `CommonModule`, and `main.ts` does not instantiate any of them with `new`
- [ ] `main.ts` contains no business logic nor direct `process.env` reads — everything goes through Phase 1 configuration module
- [ ] `docs/contract/contract.md` updated with backoffice error code catalog and note that `code` is versioned public contract
- [ ] No remaining `console.log` on bootstrap path; boot logs in structured JSON
- [ ] `npm run lint`, `npm test`, and `npm run test:e2e` pass with no error, failure, or skipped test

---

### P02M22: Verify Phase 2 completion

**Status:** 🚧 TODO
**ID:** P02M22

**Goal**

Verify that all Phase 2 requirements are met, tests pass, and the phase is ready for sign-off before advancing to Phase 3.

**Acceptance Criteria**

- [ ] All previous Phase 2 milestones are marked complete
- [ ] `scripts/pre-commit.sh` passes green from a clean checkout
- [ ] Coverage ≥ 90% on filters, interceptors, and pipes that carry rules
- [ ] All phase acceptance criteria ("Phase Acceptance Criteria" section) are satisfied and verified
- [ ] No open bugs or pending items from this phase
- [ ] Documentation updated
- [ ] Ready to advance to Phase 3

---
