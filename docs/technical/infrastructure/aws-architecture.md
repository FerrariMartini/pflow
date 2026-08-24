# Infraestrutura — AWS

## Visão geral

```
                         Route53 → ACM (TLS) → ALB
                                     │
                            ┌────────┴────────┐
                            │  ECS Fargate     │  payflow-gateway (público)
                            │  (serviço público)│
                            └────────┬─────────┘
                                     │ rede privada
        ┌────────────────────────────┼────────────────────────────┐
        ▼                            ▼                             ▼
┌───────────────┐           ┌───────────────┐             ┌───────────────┐
│ ECS Fargate    │           │ ECS Fargate    │             │ ECS Fargate    │
│ cashin/cashout │           │ webhook/audit/ │             │ backoffice-api │
│ (privado)      │           │ outbox-relay   │             │ (privado, atrás│
└───────┬────────┘           └───────┬────────┘             │  do IdP corp.) │
        │                            │                       └───────┬───────┘
        ▼                            ▼                               ▼
┌────────────────┐          ┌────────────────┐              ┌────────────────┐
│ RDS PostgreSQL  │          │ Amazon MSK      │              │ RDS PostgreSQL  │
│ (multi-AZ,      │◄────────►│ (Kafka gerenciado│             │ (read model)    │
│  por serviço)   │          │  , 3 AZs)        │              └────────────────┘
└────────────────┘          └────────────────┘
```

## Componentes

| Componente | Serviço AWS | Notas |
|---|---|---|
| Compute | ECS Fargate | Sem gestão de instância EC2; task sizing por serviço conforme perfil de carga (`cashin`/`cashout` com mais CPU, `audit` mais I/O). |
| Broker de eventos | Amazon MSK | 3 AZs, réplicas suficientes para tolerar perda de 1 AZ sem perda de dado (`min.insync.replicas` > 1). |
| Banco relacional | RDS PostgreSQL (multi-AZ) | Um banco lógico por serviço (sem banco compartilhado entre domínios) — reforça o isolamento do ADR-0001/ADR-0002. |
| Secrets | AWS Secrets Manager | Chaves HMAC de integradores e credenciais de banco; rotação automática onde suportado. |
| Rede | VPC com subnets públicas (só ALB) e privadas (todo o resto) | Nenhum serviço de domínio tem IP público; `payflow-gateway` é a única borda exposta. |
| Registry de imagem | Amazon ECR | Imagem versionada por SHA (ver `docs/technical/ci-cd.md`). |
| Observabilidade | CloudWatch Logs (ingestão) + backend de métricas/tracing compatível com OpenTelemetry | Ver `docs/technical/architecture/observability.md` para os sinais coletados. |
| IAM | Role por serviço (task role do ECS), sem credencial estática | Cada serviço só tem permissão para os recursos que efetivamente usa (princípio de menor privilégio) — `webhook-service`, por exemplo, não tem permissão de escrita no banco de `cashin-service`. |

## Ambientes

| Ambiente | Propósito | Dado |
|---|---|---|
| `dev` | Integração contínua, deploy automático a cada merge | Sintético/anonimizado |
| `staging` | Validação pré-produção, paridade de infraestrutura com prod | Sintético/anonimizado |
| `prod` | Produção | Real, com todos os controles de `docs/technical/architecture/security.md` ativos |

## Isolamento multi-tenant (nível de infraestrutura)

Cada integrador é um tenant lógico, não um recurso de infraestrutura isolado (sem VPC por cliente) — o isolamento acontece na camada de aplicação (autenticação por integrador + filtro por `integratorId` em toda query). Essa decisão prioriza custo operacional sobre isolamento físico total; caso um integrador exija isolamento físico dedicado (ex: requisito contratual/regulatório), isso é tratado como exceção arquitetural documentada, não como padrão.

## Provisionamento

Este documento define o desenho-alvo de infraestrutura, que é o contexto de arquitetura consumido por SRE e por quem opera o sistema. O provisionamento por código (Terraform ou CDK) deriva deste desenho e é rastreado como trabalho próprio, planejado via o PayFlow SDLC Kit (`/wiz-prd`) quando priorizado — a decisão arquitetural precede a automação, não o contrário.
