# Phase 7: Kafka Consumers and Idempotent Read Model Projections

**Duration**: ~4 days (32 milestones @ 1h each)
**Dependencies**: Phase 4 (authorization) and Phase 1 (read model migrations). Can start in parallel with Phase 6.
**Status**: 🚧 TODO

## Goal

Build Kafka infrastructure and projections feeding the backoffice read model (ADR-0002), with idempotency guaranteed by `eventId` — prerequisite for operational screens, per PRD §15 restriction.

Main deliverables:
- `infrastructure/kafka/` with `@nestjs/microservices` + KafkaJS, consumer group `backoffice-api`, partition key `tenant_id`, and event envelope validation (`eventId`, `correlationId`, `occurredAt`, `payload`) per `docs/contract/contract.md`.
- `cashin.projection.ts`: `transaction.cashin.initiated.v1` (INSERT PENDING), `transaction.cashin.completed.v1` and `transaction.cashin.failed.v1` (UPDATE status).
- `cashout.projection.ts`: `transaction.cashout.requested.v1` (INSERT PROCESSING), `transaction.cashout.completed.v1`, `transaction.cashout.failed.v1`, `transaction.cashout.reversed.v1` (UPDATE status).
- `circuit-breaker.projection.ts`: `circuit_breaker.kicked.v1` and `circuit_breaker.recovered.v1` → INSERT into `circuit_breaker_events`.
- Consumer for `balancing.recalibrated.v1` (operational log) and `dlq.projection.ts` for `webhook.dlq.v1` (operational alert).
- Deduplication by `eventId` and protection against out-of-order events (do not regress status from older `occurredAt`).
- Malformed payload handling without stalling partition (rejection recorded, offset advances in controlled way).
- Consumer lag and processing rate metrics via `dd-trace-js`, and `GET /api/health` extended to include Kafka.

## Phase Acceptance Criteria

- Reprocessing same offset/`eventId` does not create duplicate or change projected state — integration test against compose Redpanda reprocesses each of the 7 transactional events (P0 — idempotency).
- Out-of-order event (`completed` arriving before `initiated`, or `occurredAt` older than current state) does not regress transaction status — edge case with dedicated test per flow.
- Invalid envelope or malformed payload is rejected with structured `error` log and does not block partition consumption — test proves consumer continues processing next event.
- Contract test validates schema of each of the 11 consumed topics against `docs/contract/contract.md`, and divergence fails the build.
- All projections write `tenant_id` correctly and respect `backoffice-db` RLS; no projection writes row without `tenant_id`.
- Consumer lag and processing rate exposed as custom DataDog metric and `GET /api/health` reports Kafka state.
- Every projection log carries `correlationId` propagated from event envelope — verified by test.
- Coverage ≥ 90% on projection handlers; `scripts/pre-commit.sh` green.

## Milestones

<!-- Milestones appended by /wiz-milestones -->
### P07M01: Add Kafka environment configuration to Zod schema

**Status:** 🚧 TODO
**ID:** P07M01

**Goal**

Extend Phase 1 `config/` module with Kafka connection variables (`KAFKA_BROKERS`, `KAFKA_CLIENT_ID`, `KAFKA_CONSUMER_GROUP`, timeouts and retry) validated by Zod, ensuring service fails on boot when configuration is missing or invalid.

**Acceptance Criteria**

- [ ] Zod schema validates `KAFKA_BROKERS` (comma-separated list, minimum 1), `KAFKA_CLIENT_ID`, `KAFKA_CONSUMER_GROUP` (default `backoffice-api`), `KAFKA_SESSION_TIMEOUT_MS`, `KAFKA_HEARTBEAT_INTERVAL_MS`, and `KAFKA_RETRY_MAX_ATTEMPTS`
- [ ] Default consumer group value is `backoffice-api`, per PRD §7
- [ ] Boot with empty or malformed `KAFKA_BROKERS` aborts with explicit error message, without infrastructure stack trace
- [ ] `.env.example` and `backoffice-api` service in `docker-compose.yml` expose `KAFKA_BROKERS: redpanda:9092`
- [ ] Unit tests cover valid, missing, and malformed configuration
- [ ] `scripts/pre-commit.sh` green

---

### P07M02: Create Kafka infrastructure module with @nestjs/microservices

**Status:** 🚧 TODO
**ID:** P07M02

**Goal**

Create `src/infrastructure/kafka/kafka.module.ts` registering Kafka transport from `@nestjs/microservices` (integrated KafkaJS), with consumer group `backoffice-api` and partition key `tenant_id`, exposed by injection token per `docs/technical/guidelines/dependency-injection.md`.

**Acceptance Criteria**

- [ ] `KafkaModule` registers `Transport.KAFKA` with brokers, `clientId`, and `groupId` from `ConfigService` — no hardcoded values
- [ ] Partition key of produced messages is `tenant_id`, per PRD §7
- [ ] Client exposed via interface token (`IKafkaClient`), never concrete KafkaJS class
- [ ] `allowAutoTopicCreation` disabled; topics are broker responsibility
- [ ] Module importable by `AppModule` without circular dependency
- [ ] Integration test boots module with real DI and validates resolved configuration
- [ ] `scripts/pre-commit.sh` green

---

### P07M03: Hybrid HTTP + Kafka microservice bootstrap in main.ts

**Status:** 🚧 TODO
**ID:** P07M03

**Goal**

Adjust `main.ts` to connect Kafka microservice alongside HTTP application (`connectMicroservice` + `startAllMicroservices`), with graceful shutdown closing consumer before process exit.

**Acceptance Criteria**

- [ ] `connectMicroservice` registered before `listen()`, and `startAllMicroservices()` called on bootstrap
- [ ] `enableShutdownHooks()` enabled; `SIGTERM` disconnects consumer from group before exit
- [ ] Broker connection failure on boot logged with structured `error` and process exits with non-zero exit code
- [ ] HTTP server continues responding on `/api` with unchanged global prefix
- [ ] E2e test boots hybrid application and confirms Nest context initializes with connected consumer
- [ ] `scripts/pre-commit.sh` green

---

### P07M04: Define event envelope types and IProjectionHandler interface

**Status:** 🚧 TODO
**ID:** P07M04

**Goal**

Create in `src/projections/interfaces/` typed event envelope contract (`eventId`, `correlationId`, `occurredAt`, `payload`) and `IProjectionHandler` interface, common base for all projections.

**Acceptance Criteria**

- [ ] Type `EventEnvelope<TPayload>` with `eventId`, `correlationId`, `occurredAt`, and generic `payload`, exactly the fields from `docs/contract/contract.md`
- [ ] `IProjectionHandler<TPayload>` defines `handle(envelope: EventEnvelope<TPayload>): Promise<void>` and the topic it serves
- [ ] Payload types declared for all 11 consumed topics from §7, without `any`
- [ ] TypeScript `strict` with no errors and no `@ts-ignore` suppression
- [ ] Domain free of infrastructure imports, per `docs/technical/guidelines/dependency-injection.md`
- [ ] `scripts/pre-commit.sh` green

---

### P07M05: Implement event envelope validation

**Status:** 🚧 TODO
**ID:** P07M05

**Goal**

Create `EnvelopeValidator` in `infrastructure/kafka/` that validates via Zod every received event against envelope from `docs/contract/contract.md`, rejecting messages without `eventId`, valid `correlationId`, valid `occurredAt`, or `payload`.

**Acceptance Criteria**

- [ ] `eventId` and `correlationId` validated as UUID; `occurredAt` as ISO-8601 with timezone; `payload` as non-empty object
- [ ] Return is typed result (`Ok`/`Err`) with `DomainError` on rejection — no `throw` for validation error, per `docs/technical/guidelines/error-handling.md`
- [ ] Message that is not valid JSON is treated as rejection, not uncaught exception
- [ ] No `payload` field is logged on rejection — only `eventId`, topic, partition, offset, and reason
- [ ] Unit tests cover valid envelope and one rejection case per missing field, wrong type, and invalid JSON
- [ ] Coverage ≥ 90% on validator; `scripts/pre-commit.sh` green

---

### P07M06: Create base projection handler with processing pipeline

**Status:** 🚧 TODO
**ID:** P07M06

**Goal**

Implement `BaseProjectionHandler` in `infrastructure/kafka/`, encapsulating common pipeline for every projection: deserialization, envelope validation, delegation to concrete handler, and single error boundary.

**Acceptance Criteria**

- [ ] Pipeline executes in order: deserialize → validate envelope → delegate to concrete handler → record result
- [ ] Concrete handlers implement only `IProjectionHandler`, without repeating validation or error handling
- [ ] Extension point for SSE event emission documented in code as Phase 12 pending, without implementation in this phase
- [ ] No exception escapes pipeline to KafkaJS consumer
- [ ] Unit tests with fake concrete handler cover success, invalid envelope, and exception thrown by handler
- [ ] Coverage ≥ 90% on base handler; `scripts/pre-commit.sh` green

---
### P07M07: Create processed_events table migration

**Status:** 🚧 TODO
**ID:** P07M07

**Goal**

Add `processed_events` table to `backoffice-db`, base for `eventId` deduplication required by P0 of §14, with RLS by `tenant_id` in same pattern as other Phase 1 tables.

**Acceptance Criteria**

- [ ] Migration creates `processed_events` with `event_id` UUID, `topic`, `tenant_id` UUID NOT NULL, `occurred_at` TIMESTAMPTZ, and `processed_at` TIMESTAMPTZ DEFAULT now()
- [ ] UNIQUE constraint on (`event_id`, `topic`) guarantees database-level deduplication
- [ ] RLS enabled with policy by `app.current_tenant_id`, identical to other `backoffice-db` table pattern
- [ ] Index on `processed_at` to allow future cleanup without full scan
- [ ] Migration has functional `down` and runs cleanly from empty database
- [ ] Integration test applies migration and proves duplicate INSERT of same (`event_id`, `topic`) violates constraint
- [ ] `scripts/pre-commit.sh` green

---

### P07M08: Implement eventId deduplication repository and service

**Status:** 🚧 TODO
**ID:** P07M08

**Goal**

Create `IProcessedEventRepository` and `EventDeduplicationService` in `src/projections/`, responsible for registering processed `eventId` and reporting whether an event was already applied.

**Acceptance Criteria**

- [ ] `IProcessedEventRepository` exposes `registerIfNew(eventId, topic, tenantId, occurredAt)` returning duplicate indication without throwing exception
- [ ] Implementation uses `INSERT ... ON CONFLICT DO NOTHING` and treats unique violation as duplicate, never as technical failure
- [ ] Registration always writes `tenant_id`; attempt without `tenant_id` is rejected with `DomainError` before touching database
- [ ] Service injected by interface token; unit test mocks repository
- [ ] Integration test proves second call with same `eventId` returns duplicate
- [ ] Coverage ≥ 90% on service and repository; `scripts/pre-commit.sh` green

---

### P07M09: Integrate deduplication into base handler pipeline

**Status:** 🚧 TODO
**ID:** P07M09

**Goal**

Couple `EventDeduplicationService` to `BaseProjectionHandler` so `eventId` registration and projection write occur in the same database transaction, guaranteeing P0 idempotency.

**Acceptance Criteria**

- [ ] Registration in `processed_events` and projection write happen inside a single TypeORM transaction
- [ ] Already processed event is discarded before any write, with `info` log containing `eventId`, topic, and `correlationId`
- [ ] Projection write failure rolls back `processed_events` registration, allowing reprocessing
- [ ] Deduplicated event counter exposed for later metric use
- [ ] Integration test reprocesses same event and confirms projected state does not change and no row is duplicated
- [ ] Coverage ≥ 90% on pipeline; `scripts/pre-commit.sh` green

---

### P07M10: Implement occurredAt ordering guard

**Status:** 🚧 TODO
**ID:** P07M10

**Goal**

Create state transition helper preventing status regression when event arrives with `occurredAt` older than already projected, addressing out-of-order event consequence noted in ADR-0002.

**Acceptance Criteria**

- [ ] Pure function `shouldApplyTransition(currentOccurredAt, incomingOccurredAt, currentStatus, incomingStatus)` decides whether to apply or discard update
- [ ] Event with `occurredAt` before last applied on same transaction is discarded with `warn` log containing `eventId` and `correlationId`
- [ ] Terminal status (`COMPLETED`, `FAILED`, `REVERSED`) never regresses to `PENDING` or `PROCESSING`
- [ ] Column storing last applied event `occurredAt` is updated together with status
- [ ] Unit tests cover in-order event, out-of-order event, `occurredAt` tie, and terminal status regression attempt
- [ ] Coverage ≥ 90% on helper; `scripts/pre-commit.sh` green

---

### P07M11: Create cash-in projection repository

**Status:** 🚧 TODO
**ID:** P07M11

**Goal**

Implement `ICashinProjectionRepository` and its TypeORM implementation on `cashin_transactions`, with `SET LOCAL app.current_tenant_id` per transaction to respect `backoffice-db` RLS.

**Acceptance Criteria**

- [ ] Repository exposes `insertPending(...)` and `updateStatus(...)` operating on `CashinTransaction` entity
- [ ] Every operation executes `SET LOCAL app.current_tenant_id` with event `tenant_id` before SQL command
- [ ] Write without `tenant_id` is rejected with `DomainError` before reaching database
- [ ] Repository injected by interface token, without leaking TypeORM to projection layer
- [ ] Integration test proves write and read respect RLS and query with another `tenant_id` does not see the row
- [ ] Coverage ≥ 90% on repository; `scripts/pre-commit.sh` green

---

### P07M12: Project transaction.cashin.initiated.v1 as INSERT PENDING

**Status:** 🚧 TODO
**ID:** P07M12

**Goal**

Implement in `cashin.projection.ts` handler for `transaction.cashin.initiated.v1`, inserting transaction into `cashin_transactions` with status `PENDING`.

**Acceptance Criteria**

- [ ] Handler registered on topic `transaction.cashin.initiated.v1` and inserts row with status `PENDING`
- [ ] All payload fields mapped to read model columns, including `tenant_id`, `provider_id`, and envelope `occurredAt`
- [ ] Redelivery of same `eventId` does not create second row (P07M09 deduplication exercised by test)
- [ ] Payload missing required field is rejected with structured `error` log, without partial write
- [ ] Unit tests cover successful insert and at least one rejection case
- [ ] Coverage ≥ 90% on handler; `scripts/pre-commit.sh` green

---

### P07M13: Project transaction.cashin.completed.v1 and failed.v1 as status UPDATE

**Status:** 🚧 TODO
**ID:** P07M13

**Goal**

Implement handlers for `transaction.cashin.completed.v1` and `transaction.cashin.failed.v1`, updating row status in `cashin_transactions` with P07M10 ordering guard.

**Acceptance Criteria**

- [ ] `completed` sets status to `COMPLETED` and `failed` to `FAILED`, both writing reason/metadata from payload when present
- [ ] Both pass through `shouldApplyTransition` and discard event with `occurredAt` older than already applied
- [ ] UPDATE not finding transaction logs `warn` and does not silently create row through this path
- [ ] Redelivery of same `eventId` does not change projected state
- [ ] Unit tests cover success for each topic, out-of-order event, and nonexistent transaction
- [ ] Coverage ≥ 90% on handlers; `scripts/pre-commit.sh` green

---
