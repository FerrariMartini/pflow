# Phase 12: Real-Time SSE with Fanout via Redis Pub/Sub

**Duration**: ~3 days (24 milestones @ 1h each)
**Dependencies**: Phase 7 (emitting projections), Phase 8 (queryable read model), Phase 9 (operational CB events)
**Status**: 🚧 TODO

## Goal

Replace polling with persistent SSE streams (`src/events/`), delivering real-time screen updates for transactions and circuit breaker with correct fanout in multi-instance deployment.

Main deliverables:
- Dedicated Valkey Pub/Sub connection (`REDIS_PUBSUB_URL`) with separate ioredis clients for `PUBLISH` and `SUBSCRIBE`, channels `tx-events` and `cb-events`.
- `EventsService` with `RxJS Subject` fed by Redis subscription; Phase 7 projections emit after durable write to `backoffice-db`.
- `GET /api/events/transactions` (all profiles) and `GET /api/events/circuit-breaker` (ADMIN, OPERATIONS) with `@Sse`, authenticated by the same `JwtAuthGuard` via HttpOnly cookie.
- Event filter by `user.tenant_ids` before delivery to client.
- Batching with `bufferTime(500ms)`; each event carries `id` (`transaction_id` or ULID) and `data` as an array.
- At-least-once: `Last-Event-ID` on reconnect triggers replay from `backoffice-db` of events newer than that ID before resuming the live stream.
- Clean connection teardown (client disconnect, instance shutdown) without subscription leak.
- ADR recording the choice of SSE over WebSocket and fanout via isolated Redis Pub/Sub.

## Phase Acceptance Criteria

- Event consumed on instance A is delivered to an SSE client connected on instance B — integration test with two app instances against compose Valkey (the scenario that motivates Pub/Sub).
- Operator never receives an event from a tenant outside `user.tenant_ids` — test with two users of different scopes on the same Pub/Sub connection (P0).
- `bufferTime(500ms)` groups bursts: 50 events in 1s reach the client in at most 2 messages, each with `data` as array — verified by test.
- Reconnect with `Last-Event-ID` replays from the database exactly the events after that ID, without duplicate or skip, and no replay when the header is absent — three test cases.
- `GET /api/events/circuit-breaker` denies FINANCE, COMPLIANCE, and SUPPORT; both streams deny request without valid JWT.
- Client disconnect and instance shutdown release the subscription and leave no hanging handler — test verifies no leak after N connections opened and closed.
- Latency from Kafka event to connected client is < 2s in recorded hot-spot benchmark (P4 of §14).
- Coverage ≥ 90% in `EventsService` and `RedisPubSubService`; `scripts/pre-commit.sh` green, ADR created in `docs/decisions/` and `docs/contract/contract.md` updated with SSE contract.

## Milestones

<!-- Milestones appended by /wiz-milestones -->
