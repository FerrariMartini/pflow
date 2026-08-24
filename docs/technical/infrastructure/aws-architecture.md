# Infrastructure — AWS

## Overview

```
                         Route53 → ACM (TLS) → ALB
                                     │
                            ┌────────┴────────┐
                            │  ECS Fargate     │  payflow-gateway (public)
                            │  (public service)│
                            └────────┬─────────┘
                                     │ private network
        ┌────────────────────────────┼────────────────────────────┐
        ▼                            ▼                             ▼
┌───────────────┐           ┌───────────────┐             ┌───────────────┐
│ ECS Fargate    │           │ ECS Fargate    │             │ ECS Fargate    │
│ cashin/cashout │           │ webhook/audit/ │             │ backoffice-api │
│ (private)      │           │ outbox-relay   │             │ (private,      │
└───────┬────────┘           └───────┬────────┘             │  corp IdP)     │
        │                            │                       └───────┬───────┘
        ▼                            ▼                               ▼
┌────────────────┐          ┌────────────────┐              ┌────────────────┐
│ RDS PostgreSQL  │          │ Amazon MSK      │              │ RDS PostgreSQL  │
│ (multi-AZ,      │◄────────►│ (managed Kafka, │             │ (read model)    │
│  per service)   │          │  3 AZs)         │              └────────────────┘
└────────────────┘          └────────────────┘
```

## Components

| Component | AWS service | Notes |
|---|---|---|
| Compute | ECS Fargate | No EC2 instance management; task sizing per service according to load profile (`cashin`/`cashout` with more CPU, `audit` more I/O). |
| Event broker | Amazon MSK | 3 AZs, enough replicas to tolerate loss of 1 AZ without data loss (`min.insync.replicas` > 1). |
| Relational database | RDS PostgreSQL (multi-AZ) | One logical database per service (no shared database across domains) — reinforces ADR-0001/ADR-0002 isolation. |
| Secrets | AWS Secrets Manager | Integrator HMAC keys and database credentials; automatic rotation where supported. |
| Network | VPC with public subnets (ALB only) and private subnets (everything else) | No domain service has a public IP; `payflow-gateway` is the only exposed boundary. |
| Image registry | Amazon ECR | Image versioned by SHA (see `docs/technical/ci-cd.md`). |
| Observability | CloudWatch Logs (ingestion) + metrics/tracing backend compatible with OpenTelemetry | See `docs/technical/architecture/observability.md` for collected signals. |
| IAM | Role per service (ECS task role), no static credential | Each service has permission only for resources it actually uses (least privilege) — `webhook-service`, for example, has no write permission on `cashin-service` database. |

## Environments

| Environment | Purpose | Data |
|---|---|---|
| `dev` | Continuous integration, automatic deploy on every merge | Synthetic/anonymized |
| `staging` | Pre-production validation, infrastructure parity with prod | Synthetic/anonymized |
| `prod` | Production | Real, with all controls from `docs/technical/architecture/security.md` active |

## Multi-tenant isolation (infrastructure level)

Each integrator is a logical tenant, not an isolated infrastructure resource (no VPC per client) — isolation happens at the application layer (authentication per integrator + filter by `integratorId` on every query). This decision prioritizes operational cost over total physical isolation; if an integrator requires dedicated physical isolation (e.g., contractual/regulatory requirement), that is treated as a documented architectural exception, not the default.

## Provisioning

This document defines the target infrastructure design, which is the architecture context consumed by SRE and those who operate the system. Provisioning as code (Terraform or CDK) derives from this design and is tracked as its own work, planned via the PayFlow SDLC Kit (`/wiz-prd`) when prioritized — the architectural decision precedes automation, not the other way around.
