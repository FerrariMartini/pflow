# SRE — runbook and operations

## Incident severities

| Severity | Criterion | Example | Expected response |
|---|---|---|---|
| SEV1 | Value movement impacted (cash-in/cash-out unavailable or processing incorrectly) | `payflow-cashin-service` down | Immediate escalation, war room, stakeholder communication within 15 min |
| SEV2 | Degradation without direct value impact | High lag in `outbox-relay`, webhook delay | Escalation within 30 min, no mandatory war room |
| SEV3 | Impact limited to operations/observability | `payflow-audit-service` with ingestion delay | Handled in business hours, no off-hours escalation |

## Reference alerts and associated runbook

### Alert: consumer lag above SLO (`payflow-outbox-relay`)
- **Symptom**: events take long to reach consumers (webhook, audit, backoffice).
- **First action**: verify whether it is read lag (poll not keeping up with volume) or publication lag (broker accepting slowly) — dashboards separate the two metrics.
- **Immediate mitigation**: scale `outbox-relay` horizontally (it is stateless and uses `SELECT ... FOR UPDATE SKIP LOCKED`, safe to scale without additional coordination).
- **Escalation**: if lag persists after scale-out, check MSK health (under-replicated partitions, ISR shrink) before investigating the application.

### Alert: `payflow-gateway` error rate above 1%
- **First action**: verify whether it is concentrated on one integrator (rate limit/HMAC of a specific client) or general (bad rollout, downstream dependency down).
- **Immediate mitigation**: if general and correlated with recent deploy, rollback follows the automatic criterion from `docs/technical/ci-cd.md` (but can be triggered manually earlier).

### Alert: unreconciled transactions above threshold (`payflow-backoffice-api`)
- **Symptom**: business metric (see `docs/technical/architecture/observability.md`) rising — indicates growing discrepancy between hub and provider, not just a technical problem.
- **First action**: operations team (not SRE) investigates via `GET /v1/transactions?status=...`; SRE is only escalated if root cause is technical (e.g., read model event consumer stopped).

## Operational readiness (definition of "production ready")

A new service only goes to production when:
1. RED dashboards (or consumer dashboards, according to type) published and reviewed by SRE.
2. At least one critical alert configured and tested (simulated trigger, not just configured "on paper").
3. Minimum runbook documented on this page (or in appendix) for the critical alert above.
4. Automatic rollback configured per `docs/technical/ci-cd.md`.

## On-call

Weekly rotation, scope by domain (not a single generic on-call for all 7 services) — whoever is on call for `cashin`/`cashout` is not necessarily whoever responds for `audit-service`, given the very different severity profile between those groups.
