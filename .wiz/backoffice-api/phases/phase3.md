# Phase 3: Authentication, Email 2FA, and Session Lifecycle

**Duration**: ~4 days (32 milestones @ 1h each)
**Dependencies**: Phase 1, Phase 2
**Status**: 🚧 TODO

## Goal

Deliver the panel's complete authentication flow (`src/auth/`) — absolute prerequisite for any business endpoint, per PRD §15 restriction ("no phase delivers endpoint without authentication and authorization").

Main deliverables:
- `POST /api/auth/login`: bcrypt salt 12, bifurcated response between `{ two_factor_required, session_token }` and direct JWT issuance.
- `POST /api/auth/2fa/verify` and `POST /api/auth/2fa/resend`: 6-digit OTP by email (AWS SES in production, MailHog in dev), maximum 3 attempts and 3 resends, pre-2FA session on Valkey Auth (`2fa:session:*`, `2fa:otp:*`, TTL 5min). Mandatory for ADMIN and COMPLIANCE.
- `POST /api/auth/refresh` and `POST /api/auth/logout`: 15min access token + 2-day refresh token in HttpOnly `Secure` `SameSite=Strict` cookie; logout with `jwt_blacklist:{jti}` blacklist (TTL = remaining time) and refresh invalidation.
- `PUT /api/auth/password`: requires current password; OWASP password policy (min. 8 chars, uppercase + lowercase + digit + special, rejects top 10k common passwords).
- Account lockout: 5 failures → 15min block via `login_attempts:{email}` on Valkey Auth.
- `JwtStrategy` (Passport) + global `JwtAuthGuard` with `@Public()` decorator for exceptions (`/api/health*`, login) — deny-by-default at authentication level.
- JWT payload with `user_id`, `email`, `organization_id`, `role`, `tenant_ids`, `jti`.
- ADR recording conscious deviation from OIDC baseline in `docs/technical/architecture/security.md` for local JWT + email 2FA in this service, with rationale and convergence path.

## Phase Acceptance Criteria

- Complete flow login → OTP in MailHog → verify → JWT in HttpOnly cookie covered by e2e test, including no-2FA path for non-mandatory profiles.
- JWT token is not accessible via JavaScript (HttpOnly, Secure, SameSite=Strict cookie) and e2e test validates `Set-Cookie` attributes.
- Account lockout tested: 5 failed attempts block for 15min, 6th returns lock error even with correct password, and counter expires on its own.
- 2FA tested on edge cases: invalid OTP, expired OTP, 4th attempt, 4th resend, and expired `session_token` — each with its own typed `DomainError` and dedicated test.
- Password policy rejects weak password and password from top 10k list; generated hash is bcrypt with salt rounds 12, verified by unit test.
- Logout puts `jti` on blacklist and subsequent request with same token returns 401 — covered by e2e against real compose Valkey.
- No log from any auth route contains password, OTP, token, or plaintext email (email appears masked).
- Coverage ≥ 90% in `AuthService`, `TokenService`, and `TwoFactorService`; `scripts/pre-commit.sh` green.
- Authentication model ADR created in `docs/decisions/` and `docs/contract/contract.md` updated with auth endpoints in the same PR.

## Milestones

<!-- Milestones appended by /wiz-milestones -->
### P03M01: Register backoffice authentication model ADR

**Status:** 🚧 TODO
**ID:** P03M01

**Goal**

Document, before any implementation line, the decision to use local JWT + email 2FA in this service instead of OIDC baseline described in `docs/technical/architecture/security.md`, per `docs/technical/guidelines/coding-standards.md` rule ("every relevant architecture decision becomes ADR before implementation, not after").

**Acceptance Criteria**

- [ ] New ADR created in `docs/decisions/` with next available sequential number (after `adr-0002`), following existing ADR format (context, decision, consequences, alternatives)
- [ ] ADR explicitly states it diverges from baseline "Backoffice (human operator): OIDC against company identity provider" in `docs/technical/architecture/security.md` and justifies the divergence
- [ ] ADR describes convergence path to OIDC (what must exist to migrate and what stays unchanged: RBAC by `role`, scope by `organization_id`/`tenant_ids`)
- [ ] ADR records compensating controls adopted (bcrypt salt 12, mandatory 2FA for ADMIN and COMPLIANCE, account lockout, `jti` blacklist, HttpOnly/Secure/SameSite=Strict cookie)
- [ ] `docs/technical/architecture/security.md` references new ADR on backoffice line, so architecture reading does not conflict with implementation

---

### P03M02: Create `BackofficeUser` entity and authentication repository

**Status:** 🚧 TODO
**ID:** P03M02

**Goal**

Map `backoffice_users` table in `backoffice-db` as TypeORM entity and expose read/write access required for authentication behind `IUserRepository` interface, without any service knowing TypeORM directly.

**Acceptance Criteria**

- [ ] `BackofficeUser` entity mapped in `src/users/entities/` with `id`, `organization_id`, `email`, `name`, `role`, `tenant_ids`, `active`, `password_hash`, `two_factor_enabled`, `created_at`, `updated_at`, `deleted_at`, `deleted_by`
- [ ] `password_hash` marked with `select: false` to never appear in generic query; login read uses explicit selection
- [ ] `IUserRepository` interface in `src/users/interfaces/` with `findByEmail(email)`, `findById(id)`, and `updatePasswordHash(id, hash)`; `UserRepository` implementation registered by token (`provide: 'IUserRepository'`) per `docs/technical/guidelines/dependency-injection.md`
- [ ] `findByEmail` normalizes email (trim + lowercase) and ignores records with `deleted_at` set
- [ ] Integration test against compose `backoffice-db` covers existing user, nonexistent user, inactive user, and soft-deleted user
- [ ] `npm run lint` and `npm run build` pass with no error or new warning

---

### P03M03: Implement `PasswordService` with bcrypt salt rounds 12

**Status:** 🚧 TODO
**ID:** P03M03

**Goal**

Centralize password hashing and verification in a single injectable service, with bcrypt and salt rounds 12 per PRD §10, so no other code point calls `bcrypt` directly.

**Acceptance Criteria**

- [ ] `PasswordService` created in `src/auth/services/` implementing `IPasswordService` with `hash(plain)` and `compare(plain, hash)`
- [ ] Salt rounds fixed at 12 and exposed as named constant; unit test reads generated hash prefix and asserts `$2b$12$`
- [ ] `compare` never throws on malformed hash — returns `false` and emits `warn` log without including password or hash
- [ ] `compare` runs against precomputed dummy hash when user does not exist, so response time for "nonexistent email" and "wrong password" is not distinguishable (user enumeration mitigation)
- [ ] No other repository file imports `bcrypt` directly — verified by code search and recorded as review criterion
- [ ] Unit tests cover hash + compare success, compare with wrong password, invalid hash, and dummy hash path

---

### P03M04: Implement OWASP password policy validator

**Status:** 🚧 TODO
**ID:** P03M04

**Goal**

Implement PRD §10 password policy (minimum 8 characters, at least one uppercase, one lowercase, one digit, and one special character) as reusable domain rule, applicable on password change and future Phase 8 user registration.

**Acceptance Criteria**

- [ ] `PasswordPolicyService` (or equivalent validator in `src/auth/services/`) exposes `validate(plain)` returning list of violated rules instead of boolean only
- [ ] Rules implemented: minimum length 8, uppercase, lowercase, digit, and special character presence
- [ ] Policy violation throws `WeakPasswordError` (`DomainError` subclass) with stable `code` and message describing unmet rules without echoing password
- [ ] Custom `class-validator` decorator (e.g. `@IsStrongPassword()`) exposes same rule for DTO use, without duplicating logic
- [ ] Parameterized unit tests cover one valid password and one rejection case per isolated rule, plus empty string and whitespace-only password

---

### P03M05: Reject passwords from top 10k most common list

**Status:** 🚧 TODO
**ID:** P03M05

**Goal**

Complement password policy with check against 10 thousand most common passwords list required by PRD §10, with constant lookup cost and no perceptible response time impact.

**Acceptance Criteria**

- [ ] Top 10k common passwords list versioned in repository (dedicated data file, one password per line), with origin documented in directory comment/README
- [ ] List loaded once at boot into in-memory `Set`; lookup is case-insensitive and does not reread file per request
- [ ] Password present in list is rejected with `CommonPasswordError` (`DomainError` with own `code`, distinct from `WeakPasswordError`)
- [ ] Check runs after complexity rules, so weak and common password reports most specific violation deterministically
- [ ] Unit test asserts loaded list has 10,000 entries, rejects at least three known list passwords (different cases), and accepts strong password outside list
- [ ] Test ensures list loading does not occur at request time (mock/spy on file reader)

---

### P03M06: Define authentication `DomainError` types and HTTP mapping

**Status:** 🚧 TODO
**ID:** P03M06

**Goal**

Create typed error hierarchy for auth module on Phase 2 `DomainError`, with stable `code`, and register each `code` as public contract, per `docs/technical/guidelines/error-handling.md`.

**Acceptance Criteria**

- [ ] `DomainError` subclasses created in `src/auth/errors/` for at least: `INVALID_CREDENTIALS`, `ACCOUNT_LOCKED`, `ACCOUNT_INACTIVE`, `TWO_FACTOR_SESSION_EXPIRED`, `INVALID_OTP`, `OTP_ATTEMPTS_EXCEEDED`, `OTP_RESEND_LIMIT_EXCEEDED`, `INVALID_REFRESH_TOKEN`, `TOKEN_REVOKED`, `WEAK_PASSWORD`, `COMMON_PASSWORD`, and `CURRENT_PASSWORD_MISMATCH`
- [ ] HTTP status mapping declared exclusively in Phase 2 `DomainExceptionFilter` — no auth controller translates error to status
- [ ] `INVALID_CREDENTIALS` is the only `code` returned to client for nonexistent email, wrong password, and inactive user, avoiding user enumeration; distinction stays in internal log only
- [ ] All `code` values added to error table in `docs/contract/contract.md`, with corresponding HTTP status
- [ ] No auth error message exposes email, password, OTP, or token; unit test asserts this for each subclass
- [ ] Unit test verifies each error produces expected `{ error: { code, message, correlationId } }` envelope when passing through filter

---
### P03M07: Implement `AuthCacheService` on Valkey Auth

**Status:** 🚧 TODO
**ID:** P03M07

**Goal**

Encapsulate all PRD §7 authentication keys (`jwt_blacklist:{jti}`, `2fa:otp:{user_id}`, `2fa:session:{session_token}`, `login_attempts:{email}`) in a single typed service on Valkey Auth connection (`REDIS_AUTH_URL`) created in Phase 1, so no service builds key strings by hand.

**Acceptance Criteria**

- [ ] `AuthCacheService` created in `src/auth/services/`, implementing `IAuthCacheService` and injecting `ICacheService` from Valkey Auth connection (never Redis Core)
- [ ] Key constructors centralized in single constants module, with exact PRD §7 prefixes and default TTL per key family (blacklist = token remaining time, `2fa:*` = 5min, `login_attempts:*` = 15min)
- [ ] `login_attempts:{email}` uses normalized email hash as key component, so plaintext email is not readable in Valkey `KEYS`/dump
- [ ] Exposed methods are semantic (`blacklistJti`, `isJtiBlacklisted`, `storeOtp`, `readOtp`, `storeTwoFactorSession`, ...), not generic `get`/`set`
- [ ] Integration test against compose Valkey Auth validates write, read, TTL expiration (with short TTL), and key absence
- [ ] Test asserts no key written by service collides with Redis Core prefixes (`tenant:*`, `routing:*`, `cb:*`)

---

### P03M08: Define JWT payload, `ITokenService` interface, and token configuration

**Status:** 🚧 TODO
**ID:** P03M08

**Goal**

Fix token contract before implementation: payload type with PRD §10 fields and validated secret and lifetime configuration (access 15min, refresh 2 days).

**Acceptance Criteria**

- [ ] Type `AuthTokenPayload` declared with `user_id`, `email`, `organization_id`, `role`, `tenant_ids`, `jti`, plus `iat` and `exp`, without additional optional field not foreseen in PRD
- [ ] `ITokenService` interface in `src/auth/interfaces/` declaring access and refresh token issuance and verification
- [ ] Phase 1 Zod schema extended with `JWT_SECRET` (required, minimum length), `JWT_ACCESS_TTL` (default `15m`), and `JWT_REFRESH_TTL` (default `2d`); boot fails if `JWT_SECRET` is missing or dev value in `NODE_ENV=production`
- [ ] NestJS `JwtModule` registered asynchronously from validated configuration, never reading `process.env` directly inside service
- [ ] Configuration schema unit test covers missing secret, short secret, invalid TTL, and defaults
- [ ] No `JWT_SECRET` value appears in boot log; test inspects bootstrap log transport

---

### P03M09: Issue and verify access token with `jti`

**Status:** 🚧 TODO
**ID:** P03M09

**Goal**

Implement in `TokenService` 15-minute access token issuance with full payload and unique `jti` per token, and verification rejecting expired token, invalid signature, or incomplete payload.

**Acceptance Criteria**

- [ ] `TokenService.issueAccessToken(user)` generates HS256 signed token, 15min TTL, and UUID v4 `jti` from CSPRNG, unique on each issuance
- [ ] Issued payload contains exactly `user_id`, `email`, `organization_id`, `role`, `tenant_ids`, and `jti`, populated from `BackofficeUser` entity; `tenant_ids` reflects persisted user value (empty list resolving to all Organization tenants is delivered in Phase 4)
- [ ] `TokenService.verifyAccessToken(token)` throws `InvalidTokenError` for expired token, invalid signature, algorithm different from configured, and payload missing required fields
- [ ] Verification fixes accepted algorithm explicitly, rejecting `alg: none` and algorithm swap — covered by test with forged token
- [ ] No log emitted by `TokenService` contains token, secret, or full `jti`
- [ ] Unit tests cover issuance, verification round-trip, expiration (with controlled clock), invalid signature, and distinct `jti` between two consecutive issuances

---

### P03M10: Issue, verify, and rotate refresh token

**Status:** 🚧 TODO
**ID:** P03M10

**Goal**

Implement 2-day refresh token with own identifier and Valkey Auth registration, so it can be individually invalidated on logout and password change.

**Acceptance Criteria**

- [ ] `TokenService.issueRefreshToken(user)` generates 2-day TTL token with own `jti`, distinct from access token `jti`, and marks token type in payload so refresh is not accepted as access
- [ ] Refresh `jti` is registered in Valkey Auth via `AuthCacheService`, linked to `user_id`, with TTL equal to token TTL
- [ ] `verifyRefreshToken` rejects token whose `jti` is not registered (already invalidated), expired token, invalid signature, and access-type token
- [ ] `revokeRefreshToken(jti)` removes registration and is idempotent (revoking twice does not throw)
- [ ] Integration test against compose Valkey covers issue → verify → revoke → verify again (rejected)
- [ ] Unit tests cover type confusion (access used as refresh and vice versa) and expired refresh

---

### P03M11: Implement `jti` blacklist with TTL equal to remaining time

**Status:** 🚧 TODO
**ID:** P03M11

**Goal**

Implement access token revocation via `jwt_blacklist:{jti}` on Valkey Auth with TTL calculated from token's own `exp`, ensuring key disappears exactly when token would no longer be valid on its own.

**Acceptance Criteria**

- [ ] `TokenService.revokeAccessToken(payload)` writes `jwt_blacklist:{jti}` with TTL = `exp - now` rounded up in seconds
- [ ] Token already expired at revocation time generates no key (TTL ≤ 0 is no-op), avoiding permanent Valkey garbage
- [ ] `isAccessTokenRevoked(jti)` returns `true` while key exists and `false` after expiration
- [ ] Valkey Auth connection failure during blacklist check results in request denial (fail-closed), never silent acceptance — behavior covered by test with cache unavailable
- [ ] Integration test against compose Valkey validates effective key TTL (`TTL` within expected margin) and automatic expiration with short TTL
- [ ] No log records full `jti` or token; correlation uses `correlationId` and `user_id`

---

### P03M12: Issue tokens in HttpOnly, Secure, SameSite=Strict cookies

**Status:** 🚧 TODO
**ID:** P03M12

**Goal**

Centralize access and refresh token cookie write and clear in a single helper, with security attributes required by PRD §10, so no controller builds `Set-Cookie` by hand.

**Acceptance Criteria**

- [ ] `AuthCookieService` (or equivalent helper in `src/auth/services/`) exposes `setAuthCookies(res, accessToken, refreshToken)` and `clearAuthCookies(res)`
- [ ] Both cookies are issued with `HttpOnly`, `SameSite=Strict`, and restricted `Path`; `Secure` is always `true` outside local development and behavior is derived from validated configuration, not ad-hoc `process.env` check
- [ ] Access cookie `Max-Age` is 15min and refresh is 2 days, derived from same TTL constants as `TokenService` (no duplicated magic numbers)
- [ ] Cookie names defined as shared constants, reused by `JwtStrategy` and refresh endpoint
- [ ] `cookie-parser` enabled in bootstrap and Phase 2 CORS configuration adjusted for `credentials: true` restricted to `FRONTEND_URL`
- [ ] E2e test inspects login response `Set-Cookie` header and asserts `HttpOnly`, `Secure`, `SameSite=Strict`, and correct `Max-Age` on each cookie

---
