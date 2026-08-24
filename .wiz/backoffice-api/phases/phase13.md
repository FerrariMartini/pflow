# Phase 13: Hardening, Full Coverage, and Deploy Readiness

**Duration**: ~3 days (26 milestones @ 1h each)
**Dependencies**: Phase 12 (all previous phases)
**Status**: 🚧 TODO

## Goal

Close V1 by raising the entire service to the Definition of Done in `docs/technical/quality/qa-guidelines.md` and the gates in `docs/technical/ci-cd.md` — covering what individual phases cannot cover alone: end-to-end paths, fuzzing of critical areas, hot-spot benchmarks, security scan, and the production image.

This phase is consolidation, not deferral: lint, test, and coverage gates have been running green since Phase 1.

Main deliverables:
- E2E suite for complete critical paths: login with 2FA → deposit query → balancing adjustment → Redis propagation → SSE event received.
- Coverage closure to ≥ 90% global and on business-rule classes, ≥ 85% on controllers, with threshold failing the build.
- Fuzzing of §13 critical areas: input DTOs (`LoginDto`, `CreateUserDto`, `UpdateBalancingDto`), Kafka event envelope parsing, and auth token parsing/validation.
- Hot-spot benchmarks: Kafka consumer throughput, paginated listing under load, and Redis write latency on config propagation.
- Multi-stage production `Dockerfile`, image versioned by commit SHA (never `:latest`) with attached SBOM.
- Complete Bitbucket pipeline: Build → Lint → Test → Migration Check → Scan (`npm audit` + image scan) → Build Image → Deploy, each stage a blocking gate.
- Service README with dev seed usage contract for other teams (§16.5) and Redis resync troubleshooting documentation.
- Risk-driven exploratory testing session before promotion, focused on malformed payload and error UX.

## Phase Acceptance Criteria

- `scripts/pre-commit.sh` passes green on clean checkout, and the full CI pipeline passes all stages without manual exception.
- Global coverage ≥ 90% (branches, functions, lines, statements), services and repositories ≥ 90%, controllers ≥ 85% — thresholds configured so regression fails the build, not only appears in the report.
- Zero failing tests and zero tests marked `skip`/`todo` in the entire suite; zero lint errors across the service.
- The four critical e2e flows pass against the real containerized stack (Postgres × 2, Redpanda, Valkey, LocalStack, MailHog), without mocking the service itself.
- Fuzzing of the three §13 areas runs in CI and no malformed input causes unhandled 500, process crash, or Kafka partition stall.
- The three hot-spot benchmarks run and record baseline in the repository; paginated listing p95 < 500ms, consumer lag < 5s, and SSE latency < 2s are met.
- `npm audit` and image scan return zero `critical`/`high` vulnerabilities without approved exception with documented deadline.
- Production image builds multi-stage, is tagged by commit SHA, and has SBOM attached; migration dry-run passes against a clean database.
- Every §8 PRD endpoint is documented in Swagger and reflected in `docs/contract/contract.md`; the service README lets another team bring up the stack following only written instructions.

## Milestones

<!-- Milestones appended by /wiz-milestones -->
