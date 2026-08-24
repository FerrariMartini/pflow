---
title: "Backoffice API — PayFlow Hub"
slug: "backoffice-api"
version: "1.0.0"
status: "Approved"
created: "2026-08-24"
owner: "Ivan Ferrari Martini"
primary_language: "TypeScript (NestJS)"
benchmarking_policy: "hot spots only"
fuzzing_policy: "core areas (DTOs, auth, validation)"
---

# PRD — Backoffice API (V1)

**Product:** backoffice-api  
**Ecosystem:** PayFlow Hub  
**Stack:** NestJS · TypeORM · PostgreSQL · Redis · Kafka (KafkaJS) · DataDog  
**AWS Region:** sa-east-1 (LGPD)  
**Scope:** Version 1 — complete foundations, simplified features  

---

## 1. Background

The **PayFlow Hub** centralizes cash-in and cash-out operations as a multi-tenant intermediary between integration platforms (Partners) and banking providers (BaaS). The ecosystem consists of Go microservices for the transactional core and a separate backoffice product (NestJS + Next.js) for operational management.

The `backoffice-api` is the backend of the administrative panel. It **is not part of the critical payment path** — a backoffice failure does not affect the payments API. Its role is to provide operational visibility (deposits, withdrawals, circuit breaker) and runtime configuration (provider balancing, limits, tenants) for internal operators.

### Architecture references

| Document | Role |
|---|---|
| [`PRD.md`](../../../../docs/product/PRD.md) | Full hub PRD — scope, personas, and NFRs |
| [`architecture/overview.md`](../../../../docs/technical/architecture/overview.md) | Hub architecture, internal protocols, v1 → v2 evolution |
| [`architecture/security.md`](../../../../docs/technical/architecture/security.md) | Threat model, authentication by layer, data protection |
| [`contract/contract.md`](../../../../docs/contract/contract.md) | REST API and Kafka event conventions |
| [`guidelines/`](../../../../docs/technical/guidelines/) | Code standards, DI, error handling, and logging |
| [`decisions/`](../../../../docs/decisions/) | ADR-0001 (outbox) and ADR-0002 (backoffice read model) |

---

## 2. Problem Statement

The Hub's transactional core processes instant payments and emits events via Kafka. Without the backoffice-api:

- **Operators lack visibility** into deposits, withdrawals, provider status, and circuit breaker
- **Runtime configuration** (balancing weights, per-tenant limits, provider activation/suspension) requires direct access to the database or Redis — operational risk
- **There is no queryable audit trail** for compliance
- **There is no user management** with access control by role and organization

---

## 3. Goals

- Provide a complete REST API for the PayFlow Hub operational panel
- Implement read model via Kafka consumers for transaction visibility without coupling to the core
- Manage balancing and circuit breaker configuration with real-time propagation via Redis
- **Full Tenant CRUD** with Bearer Token generation and propagation (core-db → Redis)
- **Full BaaS Provider CRUD** with credentials exclusively in AWS Secrets Manager (IAM split: backoffice=write, core=read)
- Implement RBAC with 5 roles (Admin, Operations, Finance, Compliance, Support) — deny-by-default
- **Secure authentication with email 2FA** (OTP, mandatory for ADMIN/COMPLIANCE) + account lockout + OWASP password policy
- Introduce Organization concept for tenant grouping and access scoping
- Ensure multi-tenant isolation with RLS in both databases
- Achieve 90% test coverage on classes that carry business rules
- Observability with DataDog from day 1 (Winston + dd-trace-js)
- Edge protection with WAF + API Gateway + ALB as security baseline (OWASP Top 10)
- **SSE (Server-Sent Events)** for real-time updates on transaction and circuit breaker screens — no polling on the frontend

## 4. Non-Goals (Excluded — V2+)

- Executive dashboard with volume charts
- Async CSV export
- Automatic read model purge/retention (`cashin_transactions`, `cashout_transactions`) — V2 via EventBridge Scheduler + Lambda (no distributed lock in the application)
- Manual retention queue for `QUEUED` cashouts (depends on `rules-engine`)
- gRPC integration with `rules-engine`
- Compliance dashboard and integration with `compliance-worker`
- OpenSearch for 5-year regulatory trail
- Self-service tenant onboarding
- Automatic weight recalibration scheduler (balancing auto mode)
- CB auto-recovery with proactive goroutine
- CB flapping rule (80%/10min window)
- Per-tenant rate limit on hub-gateway (JWT RSA-256 + IP whitelist)
- Bank reconciliation
- Consolidated reports at Organization level (sum of all tenants)
- `partner_id` as an entity in core-db (integration platform ≠ Organization)

---

## 5. Domain Model

### Conceptual hierarchy

```
Organization (Acme)          ← company that owns the tenants (backoffice only)
  ├── Tenant (Acme)       ← operational brand (entire ecosystem)
  │     └── Partner: Vertex  ← integration platform (may change)
  └── Tenant (Globex)
        └── Partner: Vertex

Backoffice User (operator)
  └── belongs to 1 Organization
        ├── tenant_ids = [] → ADMIN granted access to ALL tenants in the Organization
        └── tenant_ids = [Acme] → ADMIN restricted access to specific tenants
```

### Organization vs. Partner vs. Tenant distinction

| Concept | Definition | Scope | Mutability |
|---|---|---|---|
| **Organization** | Company that owns and operates the tenants | Backoffice — grouping and access control | Stable |
| **Tenant** | Brand with independent configs (providers, limits, webhook) | Entire ecosystem — `tenant_id` in all transactional tables | Stable |
| **Partner** | Integration platform (e.g. Vertex) | Gateway/core — auth, callbacks, field mapping | May change per tenant |

Organization is introduced in V1 because:
- It does not affect any transactional service (cashin, cashout, webhook, outbox-relay)
- It does not change Kafka event contracts or Redis keys
- It addresses a real backoffice need: access scoping and tenant grouping
- It is additive to the `core-db` schema (`organizations` table + FK on `tenants`)

The ecosystem PRD's `partner_id` (V2) is a different concept — it represents the integration platform, not the owner.

---

## 6. Users and Personas

| Persona | RBAC Role | Responsibility |
|---|---|---|
| Administrator | `ADMIN` | Full management: users, organizations, configuration, audit |
| Operator | `OPERATIONS` | Transaction monitoring, balancing and CB configuration |
| Finance | `FINANCE` | Deposit and withdrawal queries, reports |
| Compliance | `COMPLIANCE` | Audit trail, chronological transaction history |
| Support | `SUPPORT` | Basic transaction queries for payer support |

### Permission matrix (V1)

| Screen / Action | ADMIN | OPERATIONS | FINANCE | COMPLIANCE | SUPPORT |
|---|---|---|---|---|---|
| Deposit query | ✓ | ✓ | ✓ | ✓ | basic read |
| Withdrawal query | ✓ | ✓ | ✓ | ✓ | basic read |
| CSV export (V2) | ✓ | ✓ | ✓ | ✓ | ✗ |
| Balancing config | ✓ | ✓ | ✗ | ✗ | ✗ |
| Circuit breaker config | ✓ | ✓ | ✗ | ✗ | ✗ |
| Kick history | ✓ | ✓ | ✗ | ✗ | ✗ |
| Organization management | ✓ | ✗ | ✗ | ✗ | ✗ |
| Tenant management (CRUD) | ✓ | ✗ | ✗ | ✗ | ✗ |
| Tenant query | ✓ | ✓ | ✗ | ✗ | ✗ |
| BaaS provider management (CRUD + SM credentials) | ✓ | ✗ | ✗ | ✗ | ✗ |
| BaaS provider query (no credentials) | ✓ | ✓ | ✗ | ✗ | ✗ |
| User management | ✓ | ✗ | ✗ | ✗ | ✗ |
| Audit trail | ✓ | ✗ | ✗ | ✓ | ✗ |

---

## 7. Technical Architecture

### Position in the ecosystem

```
Transactional Core (Go Microservices)
        ↓  publishes events to Kafka
  Event Backbone (MSK Kafka)
        ↓  consumes and projects
  backoffice-api (NestJS)
    ├── reads: backoffice-db (read model + audit ledger)
    ├── writes config: core-db → Redis
    ├── emits SSE: projections → EventsService → GET /api/events/*
    └── serves: backoffice-frontend (Next.js)
        ↑  REST + SSE (Server-Sent Events)
  Operators / Finance / Compliance / Admin
```

### Databases

The backoffice-api connects to **two PostgreSQL databases** with distinct purposes:

**Primary DataSource — `backoffice-db` (read model + audit):**
- `cashin_transactions` — deposit projection (current state)
- `cashout_transactions` — withdrawal projection (current state)
- `circuit_breaker_events` — kick and recovery history
- `transaction_audit_ledger` — append-only chronological ledger (written by `audit-worker`)
- `backoffice_users` — internal users with RBAC

**Secondary DataSource — `core-db` (configuration):**
- `organizations` — **new in V1** — companies that own tenants
- `tenants` — brands with `organization_id` FK
- `provider_configs` — provider configurations per tenant
- `routing_configs` — balancing weights per tenant and flow_type
- `circuit_breaker_configs` — CB thresholds per tenant, provider, and flow_type
- `tenant_limits` — operational limits (cashin min/max, cashout min/max, daily limit)
- `tenant_auth` — Bearer Token hash per tenant (gateway lookup)

**TypeORM approach:** Primary DataSource (`backoffice-db`) via `TypeOrmModule.forRoot()` + secondary DataSource (`core-db`) via `TypeOrmModule.forRoot('core')` with named connection. Entities and repositories are associated with the correct connection via `@InjectRepository(Entity, 'core')`.

### New schema: `organizations` table (core-db)

```sql
CREATE TABLE organizations (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        VARCHAR(100) NOT NULL,
  slug        VARCHAR(50)  NOT NULL UNIQUE,
  active      BOOLEAN      NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  deleted_at  TIMESTAMPTZ,
  deleted_by  UUID
);
```

Changes to existing tables:

```sql
-- core-db: tenants
ALTER TABLE tenants ADD COLUMN organization_id UUID NOT NULL REFERENCES organizations(id);
CREATE INDEX idx_tenants_organization ON tenants(organization_id);

-- backoffice-db: backoffice_users
-- organization_id defines the Organization; tenant_ids controls granular access
ALTER TABLE backoffice_users ADD COLUMN organization_id UUID NOT NULL;
-- tenant_ids remains: if empty ({}), user sees ALL tenants in the Organization
-- if populated, user sees ONLY the listed tenants (must belong to the Organization)
```

### Redis

The `backoffice-api` uses **two distinct Redis instances** to isolate responsibilities and avoid contention:

#### Core Redis (`REDIS_URL`) — ElastiCache Redis 7 (shared with core)

Exclusively responsible for data that core microservices need to read. The backoffice-api **writes** these configurations and the core **reads** them in real time:

**Tenant and routing configuration (written by backoffice-api, read by core):**

| Key | Written by | Purpose |
|---|---|---|
| `tenant:config:{tenant_id}` | backoffice-api | IP whitelist, webhook_url, active, rate_limit |
| `tenant:limits:{tenant_id}` | backoffice-api | cashin/cashout min/max, daily_limit |
| `tenant:providers:{tenant_id}` | backoffice-api | provider list |
| `routing:weights:{tenant_id}:{flow_type}` | backoffice-api | weights per provider |

`tenant:config:{tenant_id}` is not the source of Circuit Breaker parameters. The official CB configuration key is `circuit_breaker_configs:{tenant_id}:{provider_id}:{flow_type}`.

CB keys (`cb:state:*`, `cb:halfopen:*`) are read by the backoffice for status display, but **written only by core services**.

#### Valkey Auth (`REDIS_AUTH_URL`) — ElastiCache for Valkey (backoffice-api exclusive, AOF enabled)

Isolated instance for authentication and security data exclusive to backoffice-api. Isolated from core Redis to avoid contention and ensure that core microservice overload does not affect panel security. **AOF enabled**: data survives restarts (losing the JWT blacklist is equivalent to re-validating already revoked tokens).

| Key | Written by | Purpose | TTL |
|---|---|---|---|
| `jwt_blacklist:{jti}` | backoffice-api | Logout blacklist | Remaining token lifetime |
| `2fa:otp:{user_id}` | backoffice-api | 2FA OTP (max 3 attempts) | 5min |
| `2fa:session:{session_token}` | backoffice-api | Pre-2FA temporary session | 5min |
| `login_attempts:{email}` | backoffice-api | Failed attempt counter (account lockout) | 15min |
| `provider:credentials:arn:{tid}:{code}` | backoffice-api | Secrets Manager ARN cache for lookup | 5min |

#### Redis Pub/Sub (`REDIS_PUBSUB_URL`) — ElastiCache for Valkey (isolated, no persistence)

Exclusively responsible for SSE event fanout between instances. Without this Redis, SSE clients connected to instances that do not consume the Kafka event would never receive the notification (see ADR 001).

| Channel | Payload type | Purpose |
|---|---|---|
| `tx-events` | `TransactionEvent` (JSON) | Fanout of cashin/cashout events to all instances |
| `cb-events` | `CircuitBreakerEvent` (JSON) | Fanout of circuit breaker events to all instances |

- Valkey is wire-compatible with Redis — zero code change for Pub/Sub commands
- Separate ioredis connections: one for `PUBLISH`, another for `SUBSCRIBE` (protocol requirement)
- No AOF/RDB in production — data is ephemeral by nature

### Kafka

**Consumer topics** (read model projection + alerts):

| Topic | Action |
|---|---|
| `transaction.cashin.initiated.v1` | INSERT `cashin_transactions` (PENDING) |
| `transaction.cashin.completed.v1` | UPDATE status `cashin_transactions` |
| `transaction.cashin.failed.v1` | UPDATE status `cashin_transactions` |
| `transaction.cashout.requested.v1` | INSERT `cashout_transactions` (PROCESSING) |
| `transaction.cashout.completed.v1` | UPDATE status `cashout_transactions` |
| `transaction.cashout.failed.v1` | UPDATE status `cashout_transactions` |
| `transaction.cashout.reversed.v1` | UPDATE status `cashout_transactions` |
| `circuit_breaker.kicked.v1` | INSERT `circuit_breaker_events` |
| `circuit_breaker.recovered.v1` | INSERT `circuit_breaker_events` |
| `balancing.recalibrated.v1` | Operational log |
| `webhook.dlq.v1` | Operational alert |

**Producer topics:**

| Topic | When |
|---|---|
| `balancing.recalibrated.v1` | Operator manually adjusts weights |

**Client:** `@nestjs/microservices` with Kafka transport (integrated KafkaJS). Consumer group: `backoffice-api`. Partition key: `tenant_id`.

### Observability

| Layer | Technology | Role |
|---|---|---|
| Logging | Winston (structured JSON) | Logs for DataDog Log Management |
| APM / Tracing | dd-trace-js | Distributed tracing, auto-instrumentation |
| Metrics | dd-trace-js custom metrics | Request latency, Kafka consumer lag, error rates |
| Dashboards | DataDog | Operational + alerts |

Pino and Prometheus are **removed** from the boilerplate. Winston is chosen for native DataDog integration (winston-datadog-logs transport).

**Mandatory tags on all logs and traces:** `tenant_id`, `organization_id`, `user_id`, `request_id`, `trace_id`.

**PII masking:** CPF, email, phone, and names never appear in logs. Same rules as the ecosystem:
- CPF: `***.***.789-01`
- Email: `c***@example.com`
- Phone: `***4321`

---

## 8. API Endpoints (V1)

### Infrastructure

| Method | Endpoint | Description | Auth |
|---|---|---|---|
| `GET` | `/api/health` | Health check (DB, Redis, Kafka) | Public |
| `GET` | `/api/health/redis-propagation` | Redis reconciliation backlog snapshot (`redis_propagation_pending_total`) | Public |

### Authentication + 2FA

| Method | Endpoint | Description | Auth |
|---|---|---|---|
| `POST` | `/api/auth/login` | Email/password login → if 2FA enabled: returns `{ two_factor_required, session_token }`; if not: JWT + refresh token (HttpOnly cookie) | Public |
| `POST` | `/api/auth/2fa/verify` | Validates OTP sent by email → JWT + refresh token | session_token |
| `POST` | `/api/auth/2fa/resend` | Resends OTP by email (max 3 resends) | session_token |
| `POST` | `/api/auth/refresh` | Renews JWT with valid refresh token | Cookie |
| `POST` | `/api/auth/logout` | Invalidates session (JWT blacklist + refresh token in Redis) | JWT |
| `PUT` | `/api/auth/password` | Changes authenticated user's password (requires current password) | JWT |

### Organizations (new in V1)

| Method | Endpoint | Description | Role |
|---|---|---|---|
| `GET` | `/api/organizations` | Lists organizations | ADMIN |
| `POST` | `/api/organizations` | Creates organization | ADMIN |
| `PUT` | `/api/organizations/:id` | Updates organization | ADMIN |
| `DELETE` | `/api/organizations/:id` | Deactivates organization (soft delete) | ADMIN |

### Tenants

| Method | Endpoint | Description | Role |
|---|---|---|---|
| `GET` | `/api/tenants` | Lists tenants in the user's organization | ADMIN, OPERATIONS |
| `GET` | `/api/tenants/:id` | Tenant detail | ADMIN, OPERATIONS |
| `POST` | `/api/tenants` | Creates tenant (generates Bearer Token in `tenant_auth`) | ADMIN |
| `PUT` | `/api/tenants/:id` | Updates tenant | ADMIN |
| `DELETE` | `/api/tenants/:id` | Deactivates tenant (soft delete) | ADMIN |
| `POST` | `/api/tenants/:id/resync-redis` | Manually reprocesses tenant Redis keys | ADMIN |

### BaaS Providers

| Method | Endpoint | Description | Role |
|---|---|---|---|
| `GET` | `/api/tenants/:tid/providers` | Lists tenant BaaS providers (no credentials) | ADMIN, OPERATIONS |
| `GET` | `/api/tenants/:tid/providers/:pid` | Detail (masked credentials) | ADMIN, OPERATIONS |
| `POST` | `/api/tenants/:tid/providers` | Registers provider + stores credentials in AWS Secrets Manager | ADMIN |
| `PUT` | `/api/tenants/:tid/providers/:pid` | Updates provider metadata | ADMIN |
| `PUT` | `/api/tenants/:tid/providers/:pid/credentials` | Rotates credentials (new secret in SM) | ADMIN |
| `DELETE` | `/api/tenants/:tid/providers/:pid` | Deactivates provider (soft delete) | ADMIN |
| `POST` | `/api/tenants/:tid/providers/:pid/test-connection` | Tests connectivity with BaaS | ADMIN |
| `POST` | `/api/tenants/:tid/providers/resync-redis` | Manually reprocesses `tenant:providers` key in Redis | ADMIN |

> **BaaS Provider credentials:** stored exclusively in AWS Secrets Manager (path: `payflow/{env}/tenants/{tenant_id}/providers/{provider_code}`). The `backoffice-api` has IAM write-only (`PutSecretValue`, `CreateSecret`); the core (cashin/cashout-service) has IAM read-only (`GetSecretValue`). Credentials never persist in database, cache, or logs.

### Transactions (read model)

| Method | Endpoint | Description | Role |
|---|---|---|---|
| `GET` | `/api/deposits` | Lists deposits with filters (period, status, tenant, provider, CPF, ID) | ALL |
| `GET` | `/api/deposits/:id` | Deposit detail | ALL |
| `GET` | `/api/withdrawals` | Lists withdrawals with equivalent filters | ALL |
| `GET` | `/api/withdrawals/:id` | Withdrawal detail | ALL |

**Common filters:** `tenant_id`, `status`, `provider_id`, `date_from`, `date_to`, `document_number`, `merchant_transaction_id`, `payer_id`. Pagination: `page` + `limit` (default 20, max 100).

> `SUPPORT` has basic read access (no sensitive fields such as full `document_number`).

### Providers and Balancing

| Method | Endpoint | Description | Role |
|---|---|---|---|
| `GET` | `/api/providers` | Lists providers by tenant | ADMIN, OPERATIONS |
| `GET` | `/api/providers/:id/kicks` | Provider kick history | ADMIN, OPERATIONS |
| `GET` | `/api/providers/:id/performance` | Conversion and volume metrics | ADMIN, OPERATIONS |
| `GET` | `/api/balancing/:tenant_id` | Current balancing config | ADMIN, OPERATIONS |
| `PUT` | `/api/balancing/:tenant_id` | Updates weights and mode (manual) | ADMIN, OPERATIONS |

### Circuit Breaker

| Method | Endpoint | Description | Role |
|---|---|---|---|
| `GET` | `/api/circuit-breaker/:tenant_id` | Current CB state by provider and flow_type (reads Redis) | ADMIN, OPERATIONS |
| `PUT` | `/api/circuit-breaker/:tenant_id/config` | Updates CB thresholds | ADMIN, OPERATIONS |
| `POST` | `/api/circuit-breaker/:tenant_id/kick` | Manual provider/flow kick (body: `provider_id`, `flow_type`) | ADMIN, OPERATIONS |
| `POST` | `/api/circuit-breaker/:tenant_id/reinstate` | Manual provider/flow reinstate (body: `provider_id`, `flow_type`) | ADMIN, OPERATIONS |

### Users

| Method | Endpoint | Description | Role |
|---|---|---|---|
| `GET` | `/api/users` | Lists users in the JWT organization (`active`, `roleId`, pagination) | ADMIN |
| `GET` | `/api/users/:id` | Returns user in the JWT organization by ID | ADMIN |
| `POST` | `/api/users` | Registers new user and triggers email notification (retry/outbox on failure) | ADMIN |
| `PUT` | `/api/users/:id` | Updates profile, scope (`tenantIds`), `active`, and `twoFactorEnabled` | ADMIN |
| `DELETE` | `/api/users/:id` | Deactivates user (soft delete) | ADMIN |

### Audit

> The system maintains **two distinct audit ledgers**:
> - `transaction_audit_ledger` — chronological trail of financial events (cashin/cashout), written exclusively by `audit-worker` via Kafka. Accessed by the endpoints below (read-only).
> - `backoffice_audit_log` — trail of privileged administrative actions (CREATE/UPDATE/DEACTIVATE/CONFIG_UPDATE/KICK/REINSTATE), written by `backoffice-api` on every write operation. Covers ADMIN and OPERATIONS roles (OWASP ASVS V7).

| Method | Endpoint | Description | Role |
|---|---|---|---|
| `GET` | `/api/audit/transactions/:id` | Complete chronological history of a transaction | ADMIN, COMPLIANCE |
| `GET` | `/api/audit` | Event trail with filters (period, type, tenant, direction) | ADMIN, COMPLIANCE |

### Real-Time Events (SSE)

| Method | Endpoint | Description | Role |
|---|---|---|---|
| `GET` | `/api/events/transactions` | SSE stream of deposit and withdrawal status changes | ALL |
| `GET` | `/api/events/circuit-breaker` | SSE stream of circuit breaker kicks and recoveries | ADMIN, OPERATIONS |

**Behavior:**
- Protocol: `text/event-stream` (Server-Sent Events) — HTTP/1.1, unidirectional (server → client)
- Auth: JWT HttpOnly cookie (same guard as other endpoints)
- Scope: events filtered by `user.tenant_ids` — operator never receives events from tenants outside their access
- Each SSE event carries `id` field (`transaction_id` or ULID), `data` as **array** of events (500ms batching)
- Batching: `bufferTime(500ms)` in the RxJS pipeline — reduces re-renders from 50×/s to 2×/s under load spikes
- At-least-once delivery: each SSE event carries `id`; browser resends `Last-Event-ID` on reconnection; endpoint replays events from DB more recent than that ID before resuming the live stream
- Automatic reconnection managed by the browser via native `EventSource` (no extra library on the frontend)
- The frontend replaces polling with one persistent SSE connection per screen

**Internal flow (multi-instance):**
```
Kafka event → Projection Handler (instance A)
  ├── write to backoffice-db (durable)
  └── EventsService.emit() → RedisPubSubService.publish("tx-events" | "cb-events")
                                       │
                       ┌───────────────┼───────────────┐
                       ▼               ▼               ▼
                 inst-A sub       inst-B sub       inst-C sub
               Subject.next()   Subject.next()   Subject.next()
                       │               │               │
                bufferTime(500ms) …               …
                       │
                 SSE clients A
```

---

## 9. Module Architecture (NestJS)

### Directory structure

```
src/
├── main.ts                          → Bootstrap, global guards, CORS, prefix /api
├── app.module.ts                    → Root module, DataSources, global providers
│
├── common/                          → Cross-module shared code
│   ├── decorators/                  → @Roles(), @Public(), @CurrentUser()
│   ├── guards/                      → JwtAuthGuard, RolesGuard, TwoFactorGuard, MaintenanceGuard
│   ├── interceptors/                → LoggingInterceptor, MaskingInterceptor, ErrorInterceptor
│   ├── filters/                     → HttpExceptionFilter, AllExceptionsFilter
│   ├── interfaces/                  → ILogger, IConfigService
│   ├── dto/                         → PaginationDto, PaginatedResponseDto
│   ├── entities/                    → BaseEntity (id, created_at, updated_at)
│   └── services/                    → EncryptionService, AuthContextService
│
├── config/                          → Env validation (Zod), config schemas
│
├── infrastructure/                  → Infrastructure adapters
│   ├── database/                    → TypeORM modules (backoffice-db + core-db)
│   ├── cache/                       → Redis module, CacheService + ICacheService
│   ├── kafka/                       → Kafka consumer/producer setup, base handlers
│   ├── secrets/                     → AWS Secrets Manager module (ISecretsService, SecretsManagerService)
│   └── observability/               → Winston config, dd-trace setup, health check
│
├── auth/                            → Authentication and authorization
│   ├── interfaces/                  → IAuthService, ITokenService, ITwoFactorService
│   ├── controllers/                 → AuthController
│   ├── services/                    → AuthService, TokenService, TwoFactorService
│   ├── strategies/                  → JwtStrategy (Passport)
│   └── dto/                         → LoginDto, RefreshDto, TwoFactorVerifyDto, ChangePasswordDto
│
├── organizations/                   → Organization CRUD (core-db)
│   ├── interfaces/                  → IOrganizationRepository, IOrganizationService
│   ├── controllers/                 → OrganizationController
│   ├── services/                    → OrganizationService
│   ├── repositories/                → OrganizationRepository (core-db connection)
│   ├── entities/                    → Organization entity
│   └── dto/                         → CreateOrganizationDto, UpdateOrganizationDto
│
├── tenants/                         → Tenant query and config (core-db)
│   ├── interfaces/                  → ITenantRepository, ITenantService
│   ├── controllers/                 → TenantController
│   ├── services/                    → TenantService
│   ├── repositories/                → TenantRepository (core-db connection)
│   ├── entities/                    → Tenant, ProviderConfig, RoutingConfig, etc.
│   └── dto/                         → Query DTOs, config DTOs
│
├── deposits/                        → Cash-in query (backoffice-db)
│   ├── interfaces/                  → IDepositRepository, IDepositService
│   ├── controllers/                 → DepositController
│   ├── services/                    → DepositService
│   ├── repositories/                → DepositRepository
│   ├── entities/                    → CashinTransaction entity
│   └── dto/                         → DepositsQueryDto
│
├── withdrawals/                     → Cash-out query (backoffice-db)
│   ├── interfaces/                  → IWithdrawalRepository, IWithdrawalService
│   ├── controllers/                 → WithdrawalController
│   ├── services/                    → WithdrawalService
│   ├── repositories/                → WithdrawalRepository
│   ├── entities/                    → CashoutTransaction entity
│   └── dto/                         → WithdrawalsQueryDto
│
├── providers/                       → BaaS Providers (CRUD + SM credentials) and Circuit Breaker
│   ├── interfaces/                  → IProviderRepository, IProviderService, ICBService, ISecretsService
│   ├── controllers/                 → ProviderController, CircuitBreakerController
│   ├── services/                    → ProviderService, CircuitBreakerService
│   ├── repositories/                → ProviderConfigRepository, CBEventRepository
│   ├── entities/                    → ProviderConfig entity, CircuitBreakerEvent entity
│   └── dto/                         → CreateProviderDto, UpdateProviderDto, CredentialsDto, KickDto, ReinstateDto, CBConfigDto
│
├── balancing/                       → Balancing configuration
│   ├── interfaces/                  → IBalancingRepository, IBalancingService
│   ├── controllers/                 → BalancingController
│   ├── services/                    → BalancingService
│   ├── repositories/                → RoutingConfigRepository (core-db)
│   └── dto/                         → UpdateBalancingDto
│
├── users/                           → Internal user management
│   ├── interfaces/                  → IUserRepository, IUserService
│   ├── controllers/                 → UserController
│   ├── services/                    → UserService
│   ├── repositories/                → UserRepository (backoffice-db)
│   ├── entities/                    → BackofficeUser entity
│   └── dto/                         → CreateUserDto, UpdateUserDto
│
├── audit/                           → Audit trail
│   ├── interfaces/                  → IAuditRepository, IAuditService
│   ├── controllers/                 → AuditController
│   ├── services/                    → AuditService
│   ├── repositories/                → AuditLedgerRepository (backoffice-db, read-only)
│   ├── entities/                    → TransactionAuditLedger entity
│   └── dto/                         → AuditQueryDto
│
├── events/                          → SSE — real-time event stream
│   ├── interfaces/                  → IEventsService
│   ├── controllers/                 → EventsController (@Sse decorator)
│   ├── services/                    → EventsService (RxJS Subject fed by Redis Pub/Sub)
│   └── dto/                         → TransactionEventDto, CircuitBreakerEventDto
│
└── projections/                     → Kafka consumers → read model + SSE event emission
    ├── interfaces/                  → IProjectionHandler
    ├── cashin.projection.ts         → Consumer: transaction.cashin.*.v1 → updates DB + emits SSE
    ├── cashout.projection.ts        → Consumer: transaction.cashout.*.v1 → updates DB + emits SSE
    ├── circuit-breaker.projection.ts → Consumer: circuit_breaker.*.v1 → updates DB + emits SSE
    └── dlq.projection.ts           → Consumer: webhook.dlq.v1 → operational alert
```

### Pattern per module (Hexagonal Light + SOLID interfaces)

Each domain module follows the pattern:

```
module/
  ├── interfaces/
  │   ├── module-service.interface.ts    → IModuleService
  │   └── module-repository.interface.ts → IModuleRepository
  ├── controllers/
  │   └── module.controller.ts           → Injects IModuleService
  ├── services/
  │   └── module.service.ts              → Implements IModuleService, injects IModuleRepository
  ├── repositories/
  │   └── module.repository.ts           → Implements IModuleRepository, uses TypeORM
  ├── entities/
  │   └── entity.ts                      → TypeORM entity
  ├── dto/
  │   └── *.dto.ts                       → class-validator + class-transformer
  └── module.module.ts                   → NestJS module with providers bound by token
```

**Rule:** Controller never accesses Repository directly. Service is injected via interface token (`provide: 'IModuleService', useClass: ModuleService`). Repository is injected into Service via interface token. Unit tests mock the interfaces.

---

## 10. Security

> **Baseline:** OWASP Top 10 (2021). Edge protection via WAF + API Gateway + ALB (`x-api-key` native to API Gateway managed via Terraform/SRE — `backoffice-api` in private subnet, not directly exposed to the internet).

| Mechanism | Implementation |
|---|---|
| **Auth** | JWT with HttpOnly cookie (`Secure`, `SameSite=Strict`) — access token 15min + refresh token 2 days. Payload includes `user_id`, `email`, `organization_id`, `role`, `tenant_ids`, `jti` |
| **2FA** | 6-digit OTP via email (AWS SES), mandatory for ADMIN and COMPLIANCE roles. Pre-2FA temporary session in Redis (TTL 5min). Max 3 resends per session |
| **Password hashing** | bcrypt (salt rounds: 12) |
| **Password policy** | Minimum 8 chars, uppercase + lowercase + digit + special character, rejects top 10k common passwords (OWASP) |
| **Account lockout** | 5 failed login attempts → 15min lockout. Counter in Redis (`login_attempts:{email}`, TTL 15min) |
| **Logout** | JWT blacklist via Redis (`jwt_blacklist:{jti}`, TTL = remaining token lifetime) + refresh token invalidation |
| **RBAC** | NestJS guard that validates JWT `role` against `@Roles()` decorator. Deny-by-default |
| **Multi-tenant isolation** | RLS on all `backoffice-db` tables. User sees only tenants authorized by ADMIN (all in Organization or specific subset via `tenant_ids`) |
| **PII masking** | Global MaskingInterceptor for responses. Logs never contain plaintext PII |
| **Security headers** | Helmet.js with OWASP configuration (CSP, HSTS, X-Frame-Options, etc.) |
| **CORS** | Restricted to frontend domain (FRONTEND_URL) |
| **Rate limiting** | Global ThrottlerModule (100 req/min default) + WAF rate limit per IP at the edge |
| **Input validation** | Global ValidationPipe (whitelist + forbidNonWhitelisted + transform) |
| **Edge protection** | WAF (DDoS, OWASP rules) + API Gateway (global throttling, `x-api-key`) + ALB (VPC Link → ECS private subnet) |
| **Secrets** | Zero secrets in env vars in production — AWS Secrets Manager. BaaS provider credentials: IAM write-only (`PutSecretValue`/`CreateSecret`) on backoffice; IAM read-only (`GetSecretValue`) on core. HMAC keys and Bearer Tokens never pass through the backoffice |
| **Admin audit trail (OWASP ASVS V7)** | Every privileged write action (CREATE, UPDATE, DEACTIVATE, CONFIG_UPDATE, KICK, REINSTATE, CREDENTIALS_ROTATE) generates an append-only record in `backoffice_audit_log` with `actor_id`, `actor_email`, `actor_role`, `resource_type`, `resource_id`, `payload_before`, `payload_after`, `ip_address`, `performed_at`. Sensitive fields are sanitized before logging (`password_hash`, credentials). Covers all write roles (ADMIN and OPERATIONS). Affected entities persist `deleted_at` + `deleted_by` on soft delete |

### Access scoping by Organization + tenant_ids

ADMIN controls granular access for each user:

1. Login returns JWT with `{ user_id, organization_id, role, tenant_ids[] }`
2. `tenant_ids[]` is computed at login:
   - If `backoffice_users.tenant_ids` is **empty** (`{}`): `SELECT id FROM tenants WHERE organization_id = $1 AND active = true` → access to **all** tenants in the Organization
   - If `backoffice_users.tenant_ids` is **populated**: uses the direct list (validated as a subset of active tenants in the Organization)
3. Every endpoint that accesses data by tenant validates `tenant_id ∈ user.tenant_ids`
4. RLS on `backoffice-db`: `SET LOCAL app.current_tenant_id` per request (for transaction queries)
5. Queries to `core-db`: explicit filter `WHERE organization_id = $1` (no RLS on core-db for simplicity, since the gateway also reads core-db)

> **Business rule:** ADMIN defines at user registration/editing whether they see all tenants (empty tenant_ids) or only specific tenants (populated tenant_ids). Listed tenants must belong to the user's Organization — the API validates this on `POST /users` and `PUT /users/:id`.

---

## 11. Configuration Propagation

When the operator updates a configuration in the backoffice (weights, limits, active/inactive provider):

```
1. backoffice-api validates input (DTO + business rules)
2. Writes to core-db (source of truth)
3. Updates Redis cache (fast-path for core)
4. Finalizes propagation in Redis (no Kafka config fanout)
```

This flow ensures:
- **Consistency:** core-db is the source of truth
- **Performance:** Redis serves core reads in microseconds
- **Decoupling:** backoffice does not make synchronous HTTP calls to the core
- **Auditability:** trail via audit log and operational history in the backoffice itself

### 11.1 Redis Resilience (retry + outbox + resync)

Current implementation for Redis failures during configuration propagation:

- **Local retry with backoff+jitter** on all Redis write operations in the propagation module (`TenantConfigPropagationService`).
- **Strong contract (rollback + 500)** for critical creation and token rotation flows:
  - tenant creation
  - provider creation
  - tenant bearer token rotation
- **Contract with operational reconciliation** for configuration updates/deletes:
  - on Redis failure after persistence in `core-db`, records item in `redis_propagation_outbox` table (`core-db`) and maintains traceability via structured log.
- **Explicit operational resync** via administrative endpoints:
  - `POST /api/tenants/:id/resync-redis`
  - `POST /api/tenants/:tid/providers/resync-redis`
- **Minimum observability**:
  - log event `redis_propagation_failed`
  - operational metric via `GET /api/health/redis-propagation`

Retry tuning variables:

- `REDIS_PROPAGATION_MAX_RETRIES`
- `REDIS_PROPAGATION_BASE_DELAY_MS`
- `REDIS_PROPAGATION_MAX_DELAY_MS`

---

## 12. Infrastructure and Deploy

### Docker Compose (local development)

```yaml
services:
  backoffice-api:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports: ["3001:3001"]
    depends_on: [postgres-backoffice, postgres-core, redis, redpanda, localstack, mailhog]
    environment:
      DATABASE_URL: postgresql://backoffice:backoffice@postgres-backoffice:5432/backoffice
      CORE_DATABASE_URL: postgresql://core:core@postgres-core:5432/core
      REDIS_URL: redis://redis:6379
      KAFKA_BROKERS: redpanda:9092
      JWT_SECRET: dev-secret
      NODE_ENV: development
      AWS_ENDPOINT_URL: http://localstack:4566   # Emulated Secrets Manager
      AWS_REGION: sa-east-1
      SMTP_HOST: mailhog
      SMTP_PORT: 1025

  postgres-backoffice:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: backoffice
      POSTGRES_USER: backoffice
      POSTGRES_PASSWORD: backoffice
    ports: ["5432:5432"]

  postgres-core:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: core
      POSTGRES_USER: core
      POSTGRES_PASSWORD: core
    ports: ["5433:5432"]

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]

  redpanda:
    image: redpandadata/redpanda:latest
    command: redpanda start --smp 1 --memory 512M --overprovisioned
    ports:
      - "9092:9092"
      - "8081:8081"   # Schema Registry
      - "8082:8082"   # REST Proxy
      - "9644:9644"   # Admin

  localstack:
    image: localstack/localstack:latest
    environment:
      SERVICES: secretsmanager
      DEFAULT_REGION: sa-east-1
    ports: ["4566:4566"]

  mailhog:
    image: mailhog/mailhog:latest
    ports:
      - "1025:1025"   # SMTP
      - "8025:8025"   # Web UI for 2FA email inspection
```

### Production (AWS)

| Component | AWS Service |
|---|---|
| backoffice-api | ECS Fargate |
| backoffice-db | RDS PostgreSQL 16 |
| core-db | RDS PostgreSQL 16 (shared with hub-gateway read) |
| Redis (core) | ElastiCache Redis 7 (shared with core) |
| Valkey (auth) | ElastiCache for Valkey (backoffice-api exclusive, AOF enabled) |
| Valkey (Pub/Sub events) | ElastiCache for Valkey (isolated, no persistence) |
| Kafka | MSK (shared with core) |
| Observability | DataDog (agent on ECS, logs via CloudWatch → DataDog) |
| IaC | Terraform (SRE responsibility) |

### CI/CD — Bitbucket Pipelines

```
Pipeline: Build → Lint → Test → Migration Check → Build Image → Deploy

Pre-commit (Husky):
  - lint-staged: eslint + prettier
  - npm test (affected files)

Push:
  - Full lint
  - Full test suite (unit + integration)
  - Coverage check (≥ 90%)
  - Build
  - Migration dry-run

Merge to main:
  - All above + E2E tests
  - Docker build + push to ECR
  - Deploy to staging
  - Smoke tests
  - Deploy to production (manual approval)
```

---

## 13. Testing Strategy

### Approach

Every delivered business rule comes with the test that validates it, covering the success path and at least one rejection case. The order in which test and implementation are written is at the implementer's discretion — what the gate verifies is rule coverage, not sequence.

### Test types

| Type | Tool | Target | DB |
|---|---|---|---|
| **Unit** | Jest | Services, guards, interceptors, validators | Mocks (interfaces) |
| **Integration** | Jest + SQLite in-memory | Repositories, modules with real DI | SQLite |
| **E2E** | Jest + Supertest | Complete endpoints (HTTP → DB → Response) | SQLite in-memory |

### Coverage

| Scope | Minimum |
|---|---|
| Global (branches, functions, lines, statements) | 90% |
| Services (`*.service.ts`) | 90% |
| Repositories (`*.repository.ts`) | 90% |
| Controllers | 85% (logic delegated to service) |
| DTOs / Entities | Indirect coverage via integration/e2e |

### Priority test areas

- **Auth flow:** login, refresh, logout, JWT validation, blacklist
- **2FA flow:** login → OTP email → verify → JWT; resend; max 3 attempts; expired session
- **Account lockout:** 5 failures → 15min lockout; reset after lockout
- **Password policy:** weak password rejection; correct bcrypt hash
- **RBAC:** each endpoint validates role correctly (deny-by-default)
- **Kafka consumers:** projections insert/update correctly in read model
- **Config propagation:** core-db → Redis
- **Organization scoping:** user does not see tenants from another organization; user with restricted tenant_ids does not see tenants outside the list
- **RLS:** queries filtered by tenant_id
- **BaaS Providers:** credentials stored in SM, never returned in plaintext; credential rotation; test-connection

### Benchmarking (hot spots only)

- Kafka consumer throughput (events/second)
- Listing endpoint with pagination (deposits, withdrawals) under load
- Redis write latency for config propagation

### Fuzzing (critical areas)

- Input DTOs (LoginDto, CreateUserDto, UpdateBalancingDto)
- Kafka event payload parsing (envelope validation)
- Auth token parsing and validation

---

## 14. Non-Functional Requirements

| Requirement | Target | Priority |
|---|---|---|
| **P0 — Correctness** | | |
| Multi-tenant isolation | Zero leak between tenants (RLS + Organization scoping) | P0 |
| Kafka consumer idempotency | Offset reprocessing does not generate duplicates | P0 |
| Config propagation atomicity | core-db + Redis in sequence; rollback when applicable | P0 |
| **P1 — Regression Prevention** | | |
| Test coverage | ≥ 90% on business rule classes | P1 |
| CI pipeline | Lint + test + coverage on every push | P1 |
| Pre-commit hooks | Husky: lint-staged + test | P1 |
| **P2 — Security** | | |
| JWT HttpOnly cookie | Token not accessible via JavaScript | P2 |
| Email 2FA | 6-digit OTP, mandatory for ADMIN/COMPLIANCE | P2 |
| Account lockout | 5 failed attempts → 15min lockout | P2 |
| PII masking | No personal data in logs or unauthorized responses | P2 |
| Password policy | bcrypt salt 12, min 8 chars, OWASP complexity, rejects top 10k | P2 |
| RBAC enforcement | Backend validates role on every endpoint (deny-by-default) | P2 |
| Security headers | Helmet.js — CSP, HSTS, X-Frame-Options, etc. | P2 |
| Edge protection | WAF + API Gateway + ALB (private subnet, `x-api-key` via Terraform/SRE) | P2 |
| **P3 — Quality** | | |
| Structured logging | JSON with trace_id, tenant_id, user_id | P3 |
| Error handling | Global HttpExceptionFilter, typed errors, no stack traces in prod | P3 |
| API documentation | Swagger/OpenAPI auto-generated via decorators | P3 |
| Code style | ESLint + Prettier + Husky (Conventional Commits) | P3 |
| **P4 — Performance** | | |
| API latency P95 | < 500ms (paginated read model queries) | P4 |
| Kafka consumer lag | < 5s (near real-time projections) | P4 |
| SSE delivery latency | < 2s from Kafka event to connected client | P4 |
| Health check | < 100ms | P4 |
| Availability | 99.5% (backoffice is not critical path) | P4 |

---

## 15. Implementation Phases

Phases and milestones for this service are generated by `/wiz-phases` and `/wiz-milestones` from this PRD, and live in `.wiz/backoffice-api/phases/`. This document defines **what** to deliver and under which criteria; **how** and in what order is the result of planning.

Constraints that planning must respect:

- Foundation (scaffold, persistence, authentication) precedes any query or configuration feature.
- Read model projection depends on foundation and is a prerequisite for operational screens.
- Security is P1, tied with tests — no phase delivers an endpoint without authentication and authorization.

## 16. Dev Seed Strategy

> The dev seed is a mandatory part of Phase 1. Its goal is to allow any developer on the other microservices (`hub-gateway`, `cashin-service`, `cashout-service`, `webhook-service`, `audit-worker`) to bring up the local stack using `backoffice-api` as the configuration data source, without manually inserting data.

### How to use (other teams)

```bash
# 1. Start backoffice infrastructure
docker compose up -d

# 2. Run migrations + full seed
npm run migration:run
npm run seed:all    # equivalent to: seed:db + seed:redis + seed:secrets
```

After these commands, `core-db`, Redis, and LocalStack will be populated with the dev data documented below. Values are fixed and versioned — they do not change between runs.

---

### 16.1 `core-db` Seed (Migration seed)

Fixed IDs for dev — ensure other services can reference by UUID without lookup:

```sql
-- Organization
INSERT INTO organizations (id, name, slug, active) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Acme', 'acme', true);

-- Tenants
-- NOTE: webhook_url is NOT the endpoint that receives BaaS provider callbacks.
-- BaaS providers always call webhook-service at POST /webhook/{provider} (fixed Hub URL).
-- webhook_url is the PARTNER (Vertex) address where webhook-service
-- sends outbound notifications after processing the BaaS callback.
-- Flow: BaaS → webhook-service → reads webhook_url from Redis → POST {webhook_url} + HMAC → Vertex
-- In dev, points to a local mock server that simulates the Vertex receiver endpoint.
INSERT INTO tenants (id, organization_id, name, slug, webhook_url, active) VALUES
  ('00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000001',
   'Acme', 'acme', 'http://mock-partner:3100/webhook/acme', true),
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001',
   'Globex', 'globex', 'http://mock-partner:3100/webhook/globex', true);

-- Provider configs (Acme — Aurora + Nimbus)
INSERT INTO provider_configs (tenant_id, provider_id, base_url, active) VALUES
  ('00000000-0000-0000-0000-000000000010', 'aurora', 'http://mock-aurora:8080', true),
  ('00000000-0000-0000-0000-000000000010', 'nimbus', 'http://mock-nimbus:8080', true);

-- Routing configs — initial weights (CASHIN + CASHOUT)
INSERT INTO routing_configs (tenant_id, provider_id, flow_type, position, weight, mode) VALUES
  ('00000000-0000-0000-0000-000000000010', 'aurora', 'CASHIN',  1, 70, 'MANUAL'),
  ('00000000-0000-0000-0000-000000000010', 'nimbus', 'CASHIN',  2, 30, 'MANUAL'),
  ('00000000-0000-0000-0000-000000000010', 'aurora', 'CASHOUT', 1, 70, 'MANUAL'),
  ('00000000-0000-0000-0000-000000000010', 'nimbus', 'CASHOUT', 2, 30, 'MANUAL');

-- Circuit Breaker configs — default thresholds
INSERT INTO circuit_breaker_configs
  (tenant_id, provider_id, flow_type, consecutive_threshold, suspension_minutes) VALUES
  ('00000000-0000-0000-0000-000000000010', 'aurora', 'CASHIN',  20, 30),
  ('00000000-0000-0000-0000-000000000010', 'nimbus', 'CASHIN',  20, 30),
  ('00000000-0000-0000-0000-000000000010', 'aurora', 'CASHOUT', 20, 30),
  ('00000000-0000-0000-0000-000000000010', 'nimbus', 'CASHOUT', 20, 30);

-- Tenant limits
INSERT INTO tenant_limits
  (tenant_id, cashin_min, cashin_max, cashout_min, cashout_max, cashout_daily_limit) VALUES
  ('00000000-0000-0000-0000-000000000010', 10.00, 50000.00, 20.00, 20000.00, 100000.00);

-- Tenant auth — sha256('sk-dev-acme-localtoken01')
-- Raw token lives in LocalStack (see 16.3)
INSERT INTO tenant_auth (tenant_id, token_hash, token_hint, active) VALUES
  ('00000000-0000-0000-0000-000000000010',
   'a3f1e2d4b5c6789012345678abcdef0123456789abcdef0123456789abcdef01',
   'sk-dev-', true);
```

---

### 16.2 `backoffice-db` Seed (Migration seed)

```sql
-- Default ADMIN user
-- Password: Admin@123456 (bcrypt hash — change on first login in production)
INSERT INTO backoffice_users
  (id, organization_id, email, name, role, tenant_ids, active, password_hash) VALUES
  ('00000000-0000-0000-0000-000000000100',
   '00000000-0000-0000-0000-000000000001',
   'admin@acme.local', 'Admin Default', 'ADMIN', '{}', true,
   '$2b$12$<hash_gerado_na_migration>');
```

---

### 16.3 Redis Seed (`npm run seed:redis`)

Script executed after migrations. Reads data from `core-db` and populates keys exactly as backoffice-api would when saving a configuration via endpoint. Ensures `hub-gateway`, `cashin-service`, and `cashout-service` find data in Redis on the first request.

Populated keys (tenant_id = `00000000-0000-0000-0000-000000000010`):

```
tenant:config:00000000-0000-0000-0000-000000000010
  → { "webhook_url": "http://mock-partner:3100/webhook/acme",
      -- webhook_url = PARTNER (Vertex) address for outbound notifications
      -- NOT the BaaS provider endpoint. BaaS providers always call /webhook/{provider} on the Hub.
      "active": true, "rate_limit_rps": 100, "ip_whitelist": [] }

tenant:limits:00000000-0000-0000-0000-000000000010
  → { "cashin_min": 10, "cashin_max": 50000,
      "cashout_min": 20, "cashout_max": 20000, "cashout_daily_limit": 100000 }

tenant:providers:00000000-0000-0000-0000-000000000010
  → [ { "provider_id": "aurora", "base_url": "http://mock-aurora:8080", "active": true },
      { "provider_id": "nimbus", "base_url": "http://mock-nimbus:8080", "active": true } ]

routing:weights:00000000-0000-0000-0000-000000000010:CASHIN
  → { "aurora": 70, "nimbus": 30 }

routing:weights:00000000-0000-0000-0000-000000000010:CASHOUT
  → { "aurora": 70, "nimbus": 30 }

auth:token:a3f1e2d4b5c6789012345678abcdef0123456789abcdef0123456789abcdef01
  → "00000000-0000-0000-0000-000000000010"
  TTL: 300s (5 min — automatically renewed on hub-gateway lookup)
```

---

### 16.4 LocalStack Seed — Secrets Manager (`npm run seed:secrets`)

Shell or Node.js script that creates secrets in LocalStack via AWS CLI or SDK. These secrets are read by core services in dev.

```bash
# Acme Bearer Token (read by hub-gateway in Secrets Manager as fallback)
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name "payflow/dev/tenants/acme/api-key" \
  --secret-string "sk-dev-acme-localtoken01"

# Mock Aurora provider credentials (read by cashin-service and cashout-service)
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name "payflow/dev/tenants/acme/providers/aurora" \
  --secret-string '{"api_key":"dev-aurora-key-001","api_secret":"dev-aurora-secret-001","client_id":"aurora-dev-client"}'

# Mock Nimbus provider credentials (read by cashin-service and cashout-service)
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name "payflow/dev/tenants/acme/providers/nimbus" \
  --secret-string '{"api_key":"dev-nimbus-key-001","api_secret":"dev-nimbus-secret-001","client_id":"nimbus-dev-client"}'

# Acme HMAC key for webhook validation (read by webhook-service)
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name "payflow/dev/tenants/acme/hmac-key" \
  --secret-string "dev-hmac-key-acme-local-0001"
```

---

### 16.5 Quick reference for other teams

| Data | Dev value |
|---|---|
| **Tenant ID (Acme)** | `00000000-0000-0000-0000-000000000010` |
| **Organization ID (Acme)** | `00000000-0000-0000-0000-000000000001` |
| **Bearer Token (hub-gateway Authorization header)** | `Bearer sk-dev-acme-localtoken01` |
| **Bearer Token hash (core-db lookup)** | `a3f1e2d4b5c6789012345678abcdef0123456789abcdef0123456789abcdef01` |
| **core-db host:port** | `localhost:5433` |
| **backoffice-db host:port** | `localhost:5432` |
| **Redis host:port** | `localhost:6379` |
| **Kafka broker** | `localhost:9092` |
| **LocalStack (Secrets Manager)** | `http://localhost:4566` |
| **backoffice-api** | `http://localhost:3001` |
| **Admin login** | `admin@acme.local` / `Admin@123456` |
| **MailHog (2FA emails)** | `http://localhost:8025` |
| **mock-partner (simulates Vertex)** | `http://mock-partner:3100` |

> **Note:** Bearer Token `sk-dev-acme-localtoken01` is exclusive to the development environment. Never use in staging or production. The token and its hash are fixed for reproducibility — any developer can reference `tenant_id` by UUID without lookup.

> **About `webhook_url`:** the `webhook_url` field on the tenant **is not** the endpoint that receives BaaS provider callbacks. BaaS providers (Aurora, Nimbus) always call `webhook-service` at `POST /webhook/{provider}` — fixed Hub URL. `webhook_url` is the **partner** (Vertex) address where `webhook-service` sends outbound notifications after processing the BaaS callback. Flow: `BaaS → webhook-service → reads webhook_url from Redis → POST {webhook_url} + HMAC → Vertex`. In dev, `mock-partner` is a simple HTTP server (e.g. [Mockoon](https://mockoon.com/) or `json-server`) that simulates the Vertex receiver.

---

## 17. Open Questions

All questions have been resolved. Recorded below for traceability.

| # | Question | Decision | Impact |
|---|---|---|---|
| 1 | Read model retention policy (`cashin_transactions`, `cashout_transactions`) | **Out of V1 scope.** V2 will implement via EventBridge Scheduler + Lambda (no distributed lock in the application). No purge in V1 — tables grow without limit until V2 is delivered | Moved to Non-Goals |
| 2 | `GET /providers/:id/performance` — on-the-fly or pre-computed? | **On-the-fly in V1** (low volume). **V2** evolves to pre-computed table with periodic aggregation job. | No impact on V1 schema. Note added to endpoint |
| 3 | Real-time transaction screen updates | **SSE (Server-Sent Events)** — unidirectional, no polling. `EventsService` fed by Redis Pub/Sub (Valkey) for multi-instance fanout; `bufferTime(500ms)` for batching; `Last-Event-ID` for at-least-once. | `events/` module + 2 SSE endpoints in Phase 2 |

---

## 18. Appendix

### 18.1 Design decisions

| Decision | Chosen option | Rationale |
|---|---|---|
| Scaffold | Clean (discard Palmtree) | Boilerplate modules do not apply to the Hub |
| Dual DataSource | Primary (backoffice-db) + Named (core-db) | Clear separation of responsibilities |
| Kafka client | @nestjs/microservices + KafkaJS | Native NestJS integration, less boilerplate |
| Docker Compose | Full stack (2xPG + Redis + Redpanda + LocalStack + MailHog) | Enables local testing of Kafka, Secrets Manager, and 2FA |
| Tests | Unit (mock) + Integration (SQLite) + E2E | 90% coverage on business rules |
| Observability | Winston + dd-trace-js (no Pino/Prometheus) | DataDog as the ecosystem's single stack |
| CI/CD | Bitbucket Pipelines + Husky | Aligned with multi-repo ecosystem |
| Admin seed | Default migration | Guaranteed first access without manual script |
| Architecture | Hexagonal Light + SOLID interfaces | Full decoupling with testability |
| Organization | `organizations` table in V1 | Real grouping need; additive with no core impact |
| 2FA | OTP via email (AWS SES), mandatory ADMIN/COMPLIANCE | OWASP security without friction for operational roles |
| JWT refresh | 2 days (not 7) | Balance between security and UX; aligned with ecosystem |
| Secrets Manager | infrastructure/secrets/ with LocalStack in dev | BaaS provider credentials never in database, cache, or logs |
| Tenants CRUD | POST/PUT/DELETE with Bearer Token generation | Full CRUD in V1 — onboarding new tenants by operator |
| Dev Seed | Fixed UUIDs + `seed:all` (DB + Redis + Secrets) | Other teams (hub-gateway, cashin-service, etc.) start with ready data without manual configuration |
| Dev UUIDs | Fixed and versioned in migration seed | Reproducibility — other services reference tenant_id by UUID without lookup |
| SSE vs. WebSocket | SSE (`text/event-stream`) | Unidirectional (server → client) — sufficient for transaction notifications. No full-duplex overhead. Native browser reconnection via `EventSource` |
| SSE multi-instance fanout | Redis Pub/Sub via isolated Valkey (`REDIS_PUBSUB_URL`) | RxJS Subject (in-process) fails on multi-instance deploys. Redis Pub/Sub ensures fanout to all instances with sub-ms latency. Separate instance isolates core Redis failures. See ADR 001. |
| SSE batching | `bufferTime(500ms)` in RxJS pipeline | High-frequency scenarios (50+ events/s) would cause excessive re-renders. 500ms window reduces UI updates to 2/s without data loss. |
| SSE at-least-once | `Last-Event-ID` + DB replay | Redis Pub/Sub is at-most-once. `Last-Event-ID` allows the endpoint to replay missed events from DB on reconnection, ensuring at-least-once for the frontend. |
| Read model retention | **V2** via EventBridge Scheduler + Lambda | V1 without purge — multi-instance would require distributed lock, which is unnecessary complexity for V1. V2 delegates to SRE via Terraform |
| On-the-fly performance V1 | `GET /providers/:id/performance` does direct query | Low volume in V1 — acceptable. V2 adds periodic pre-computation job |

### 18.2 Hub PRD — suggested changes

No pending items identified: the hub PRD (`docs/product/PRD.md`) already covers the Organization, Partner, and Tenant definitions used here.
