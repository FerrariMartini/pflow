---
description: "Authoritative standards for this repository — the binding rules live in docs/ and MUST be read before planning or implementing"
tags: [architecture, coding-standards, contracts, testing, security, process]
languages: []
applies_to: []
---

# Read these before planning or implementing

This file carries no rules of its own. Every rule that governs this repository lives in `docs/`, which is the single source of truth.

**Read the files below now and treat them as authoritative.** For anything they cover, do not fall back to your defaults and do not research alternatives — if a guideline here specifies a framework, a pattern or a tool, use it as written. Where a document below contradicts your general recommendations, the document wins.

| File | Governs |
|---|---|
| `docs/product/PRD.md` | Scope, personas, NFR priority order, v1 boundaries and explicit non-goals |
| `docs/technical/architecture/overview.md` | System shape, internal protocol per flow, v1 → v2 evolution |
| `docs/technical/architecture/security.md` | Threat model, authentication per layer, data protection |
| `docs/technical/architecture/observability.md` | Logs, metrics, tracing and reference SLOs |
| `docs/technical/guidelines/coding-standards.md` | Locked stack and conventions per group (CORE in Go, Backoffice in NestJS), plus language policy |
| `docs/technical/guidelines/dependency-injection.md` | Injection by interface/token; domain free of infrastructure imports |
| `docs/technical/guidelines/error-handling.md` | Business error vs. technical failure; typed errors; no `panic` in business flow |
| `docs/technical/guidelines/logging.md` | Structured logging, mandatory `correlationId`, what must never be logged |
| `docs/technical/quality/qa-guidelines.md` | Test pyramid, Definition of Ready and Definition of Done |
| `docs/technical/ci-cd.md` | Quality gates and the acceptance criterion of each pipeline stage |
| `docs/contract/contract.md` | REST and Kafka event conventions, versioning, deprecation policy |
| `docs/decisions/` | ADRs — architectural decisions already settled, not open for revision |

## Repository state

Inspect the repository to determine the current implementation state of each service — which ones have code, which are empty, what test infrastructure exists. Do not assume a scaffold, dependency or test suite is present, and do not assume it is absent.

`scripts/pre-commit.sh` runs the same checks as CI. Prefer acceptance criteria that this script can verify.

## Service codes for traceability IDs

`payflow-gateway` GTW · `payflow-cashin-service` CIN · `payflow-cashout-service` COUT · `payflow-webhook-service` WHK · `payflow-outbox-relay` OBX · `payflow-audit-service` AUD · `payflow-backoffice-api` BKO
