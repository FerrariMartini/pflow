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

**Produto:** backoffice-api  
**Ecossistema:** PayFlow Hub  
**Stack:** NestJS · TypeORM · PostgreSQL · Redis · Kafka (KafkaJS) · DataDog  
**Região AWS:** sa-east-1 (LGPD)  
**Escopo:** Versão 1 — fundações completas, features simplificadas  

---

## 1. Background

O **PayFlow Hub** centraliza operações de cash-in e cash-out como intermediário multi-tenant entre plataformas integradoras (Partners) e provedores bancários (BaaS). O ecossistema é composto por microservices em Go para o core transacional e um produto separado de backoffice (NestJS + Next.js) para gestão operacional.

O `backoffice-api` é o backend do painel administrativo. Ele **não faz parte do caminho crítico de pagamentos** — uma falha no backoffice não afeta a API de pagamentos. Sua função é fornecer visibilidade operacional (depósitos, saques, circuit breaker) e configuração de runtime (balanceamento de provedores, limites, tenants) para operadores internos.

### Referências de arquitetura

| Documento | Papel |
|---|---|
| [`PRD.md`](../../../../docs/product/PRD.md) | PRD do hub completo — escopo, personas e NFRs |
| [`architecture/overview.md`](../../../../docs/technical/architecture/overview.md) | Arquitetura do hub, protocolos internos, evolução v1 → v2 |
| [`architecture/security.md`](../../../../docs/technical/architecture/security.md) | Modelo de ameaças, autenticação por camada, proteção de dados |
| [`contract/contract.md`](../../../../docs/contract/contract.md) | Convenções de API REST e de eventos Kafka |
| [`guidelines/`](../../../../docs/technical/guidelines/) | Padrões de código, DI, tratamento de erro e logging |
| [`decisions/`](../../../../docs/decisions/) | ADR-0001 (outbox) e ADR-0002 (read model do backoffice) |

---

## 2. Problem Statement

O core transacional do Hub processa pagamentos instantâneos e gera eventos via Kafka. Sem o backoffice-api:

- **Operadores não têm visibilidade** sobre depósitos, saques, status de provedores e circuit breaker
- **Configurações de runtime** (pesos de balanceamento, limites por tenant, ativação/suspensão de provedores) exigem acesso direto ao banco ou Redis — risco operacional
- **Não existe trilha de auditoria** consultável para compliance
- **Não há gestão de usuários** com controle de acesso por perfil e organização

---

## 3. Goals

- Fornecer API REST completa para o painel operacional do PayFlow Hub
- Implementar read model via Kafka consumers para visibilidade de transações sem acoplar ao core
- Gerenciar configurações de balanceamento e circuit breaker com propagação em tempo real via Redis
- **CRUD completo de Tenants** com geração de Bearer Token e propagação (core-db → Redis)
- **CRUD completo de BaaS Providers** com credenciais exclusivamente no AWS Secrets Manager (IAM split: backoffice=write, core=read)
- Implementar RBAC com 5 perfis (Admin, Operações, Financeiro, Compliance, Atendimento) — deny-by-default
- **Autenticação segura com 2FA via email** (OTP, obrigatório para ADMIN/COMPLIANCE) + account lockout + password policy OWASP
- Introduzir conceito de Organization para agrupamento de tenants e scoping de acesso
- Garantir isolamento multi-tenant com RLS em ambos os bancos
- Atingir 90% de cobertura de testes nas classes que carregam regra de negócio
- Observabilidade com DataDog desde o dia 1 (Winston + dd-trace-js)
- Edge protection com WAF + API Gateway + ALB como baseline de segurança (OWASP Top 10)
- **SSE (Server-Sent Events)** para atualização em tempo real das telas de transações e circuit breaker — sem polling no frontend

## 4. Non-Goals (Excluído — V2+)

- Dashboard executivo com gráficos de volumetria
- Exportação CSV assíncrona
- Purge/retenção automática do read model (`cashin_transactions`, `cashout_transactions`) — V2 via EventBridge Scheduler + Lambda (sem lock distribuído na aplicação)
- Fila de retenção manual para cashouts `QUEUED` (depends on `rules-engine`)
- Integração gRPC com `rules-engine`
- Compliance dashboard e integração com `compliance-worker`
- OpenSearch para trilha regulatória de 5 anos
- Onboarding self-service de tenants
- Scheduler automático de recalibração de pesos (auto mode do balanceamento)
- CB auto-recovery com goroutine proativa
- CB flapping rule (janela 80%/10min)
- Rate limit por tenant no hub-gateway (JWT RSA-256 + IP whitelist)
- Reconciliação bancária
- Relatórios consolidados no nível de Organization (soma de todos os tenants)
- `partner_id` como entidade no core-db (plataforma de integração ≠ Organization)

---

## 5. Modelo de Domínio

### Hierarquia conceitual

```
Organization (Acme)          ← empresa dona dos tenants (backoffice only)
  ├── Tenant (Acme)       ← brand operacional (todo o ecossistema)
  │     └── Partner: Vertex  ← plataforma de integração (pode mudar)
  └── Tenant (Globex)
        └── Partner: Vertex

Backoffice User (operador)
  └── pertence a 1 Organization
        ├── tenant_ids = [] → ADMIN concedeu acesso a TODOS os tenants da Organization
        └── tenant_ids = [Acme] → ADMIN restringiu acesso a tenants específicos
```

### Distinção Organization vs. Partner vs. Tenant

| Conceito | Definição | Escopo | Mutabilidade |
|---|---|---|---|
| **Organization** | Empresa que possui e opera os tenants | Backoffice — agrupamento e controle de acesso | Estável |
| **Tenant** | Brand com configs independentes (provedores, limites, webhook) | Todo o ecossistema — `tenant_id` em todas as tabelas transacionais | Estável |
| **Partner** | Plataforma de integração (ex: Vertex) | Gateway/core — auth, callbacks, mapeamento de campos | Pode mudar por tenant |

A Organization é introduzida em V1 porque:
- Não afeta nenhum serviço transacional (cashin, cashout, webhook, outbox-relay)
- Não altera Kafka event contracts nem Redis keys
- Resolve uma necessidade real do backoffice: scoping de acesso e agrupamento de tenants
- É aditiva ao schema do `core-db` (tabela `organizations` + FK em `tenants`)

O `partner_id` do ecossistema PRD (V2) é um conceito diferente — representa a plataforma de integração, não o dono.

---

## 6. Usuários e Personas

| Persona | Perfil RBAC | Responsabilidade |
|---|---|---|
| Administrador | `ADMIN` | Gestão completa: usuários, organizações, configurações, auditoria |
| Operador | `OPERATIONS` | Monitoramento de transações, configuração de balanceamento e CB |
| Financeiro | `FINANCE` | Consulta de depósitos e saques, relatórios |
| Compliance | `COMPLIANCE` | Trilha de auditoria, histórico cronológico de transações |
| Atendimento | `SUPPORT` | Consulta básica de transações para suporte ao pagador |

### Matriz de permissões (V1)

| Tela / Ação | ADMIN | OPERATIONS | FINANCE | COMPLIANCE | SUPPORT |
|---|---|---|---|---|---|
| Consulta depósitos | ✓ | ✓ | ✓ | ✓ | leitura básica |
| Consulta saques | ✓ | ✓ | ✓ | ✓ | leitura básica |
| Exportação CSV (V2) | ✓ | ✓ | ✓ | ✓ | ✗ |
| Config balanceamento | ✓ | ✓ | ✗ | ✗ | ✗ |
| Config circuit breaker | ✓ | ✓ | ✗ | ✗ | ✗ |
| Histórico de kicks | ✓ | ✓ | ✗ | ✗ | ✗ |
| Gestão de organizações | ✓ | ✗ | ✗ | ✗ | ✗ |
| Gestão de tenants (CRUD) | ✓ | ✗ | ✗ | ✗ | ✗ |
| Consulta de tenants | ✓ | ✓ | ✗ | ✗ | ✗ |
| Gestão de BaaS providers (CRUD + credenciais SM) | ✓ | ✗ | ✗ | ✗ | ✗ |
| Consulta de BaaS providers (sem credenciais) | ✓ | ✓ | ✗ | ✗ | ✗ |
| Gestão de usuários | ✓ | ✗ | ✗ | ✗ | ✗ |
| Trilha de auditoria | ✓ | ✗ | ✗ | ✓ | ✗ |

---

## 7. Arquitetura Técnica

### Posição no ecossistema

```
Core Transacional (Go Microservices)
        ↓  publica eventos no Kafka
  Event Backbone (MSK Kafka)
        ↓  consome e projeta
  backoffice-api (NestJS)
    ├── lê: backoffice-db (read model + audit ledger)
    ├── escreve config: core-db → Redis
    ├── emite SSE: projections → EventsService → GET /api/events/*
    └── serve: backoffice-frontend (Next.js)
        ↑  REST + SSE (Server-Sent Events)
  Operadores / Financeiro / Compliance / Admin
```

### Bancos de dados

O backoffice-api conecta em **dois bancos PostgreSQL** com propósitos distintos:

**DataSource primária — `backoffice-db` (read model + auditoria):**
- `cashin_transactions` — projeção de depósitos (estado atual)
- `cashout_transactions` — projeção de saques (estado atual)
- `circuit_breaker_events` — histórico de kicks e recoveries
- `transaction_audit_ledger` — ledger cronológico append-only (escrito pelo `audit-worker`)
- `backoffice_users` — usuários internos com RBAC

**DataSource secundária — `core-db` (configuração):**
- `organizations` — **novo em V1** — empresas donas dos tenants
- `tenants` — brands com `organization_id` FK
- `provider_configs` — configurações de provedores por tenant
- `routing_configs` — pesos de balanceamento por tenant e flow_type
- `circuit_breaker_configs` — thresholds do CB por tenant, provedor e flow_type
- `tenant_limits` — limites operacionais (cashin min/max, cashout min/max, daily limit)
- `tenant_auth` — hash do Bearer Token por tenant (gateway lookup)

**Abordagem TypeORM:** DataSource primária (`backoffice-db`) via `TypeOrmModule.forRoot()` + DataSource secundária (`core-db`) via `TypeOrmModule.forRoot('core')` com named connection. Entities e repositories são associados à conexão correta via `@InjectRepository(Entity, 'core')`.

### Schema novo: tabela `organizations` (core-db)

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

Alterações em tabelas existentes:

```sql
-- core-db: tenants
ALTER TABLE tenants ADD COLUMN organization_id UUID NOT NULL REFERENCES organizations(id);
CREATE INDEX idx_tenants_organization ON tenants(organization_id);

-- backoffice-db: backoffice_users
-- organization_id define a Organization; tenant_ids controla acesso granular
ALTER TABLE backoffice_users ADD COLUMN organization_id UUID NOT NULL;
-- tenant_ids permanece: se vazio ({}), usuário vê TODOS os tenants da Organization
-- se preenchido, vê APENAS os tenants listados (devem pertencer à Organization)
```

### Redis

O `backoffice-api` usa **dois Redis distintos** para isolar responsabilidades e evitar contenção:

#### Redis Core (`REDIS_URL`) — ElastiCache Redis 7 (compartilhado com core)

Responsável exclusivamente por dados que os microservices do core precisam ler. O backoffice-api **escreve** essas configurações e o core as **lê** em tempo real:

**Configurações de tenant e roteamento (escritas pelo backoffice-api, lidas pelo core):**

| Chave | Escrito por | Propósito |
|---|---|---|
| `tenant:config:{tenant_id}` | backoffice-api | IP whitelist, webhook_url, active, rate_limit |
| `tenant:limits:{tenant_id}` | backoffice-api | cashin/cashout min/max, daily_limit |
| `tenant:providers:{tenant_id}` | backoffice-api | lista de providers |
| `routing:weights:{tenant_id}:{flow_type}` | backoffice-api | pesos por provider |

`tenant:config:{tenant_id}` não é fonte de parâmetros de Circuit Breaker. A chave oficial de configuração de CB é `circuit_breaker_configs:{tenant_id}:{provider_id}:{flow_type}`.

Chaves de CB (`cb:state:*`, `cb:halfopen:*`) são lidas pelo backoffice para exibição de status, mas **escritas apenas pelos services core**.

#### Valkey Auth (`REDIS_AUTH_URL`) — ElastiCache for Valkey (exclusivo backoffice-api, AOF habilitado)

Instância isolada para dados de autenticação e segurança exclusivos do backoffice-api. Isolada do Redis core para evitar contenção e garantir que uma sobrecarga nos microservices core não afete a segurança do painel. **AOF habilitado**: dados sobrevivem a restarts (perder a JWT blacklist equivale a revalidar tokens já revogados).

| Chave | Escrito por | Propósito | TTL |
|---|---|---|---|
| `jwt_blacklist:{jti}` | backoffice-api | Blacklist de logout | Tempo restante do token |
| `2fa:otp:{user_id}` | backoffice-api | OTP de 2FA (max 3 tentativas) | 5min |
| `2fa:session:{session_token}` | backoffice-api | Sessão temporária pré-2FA | 5min |
| `login_attempts:{email}` | backoffice-api | Contador de tentativas falhas (account lockout) | 15min |
| `provider:credentials:arn:{tid}:{code}` | backoffice-api | Cache do ARN do Secrets Manager para lookup | 5min |

#### Redis Pub/Sub (`REDIS_PUBSUB_URL`) — ElastiCache for Valkey (isolado, sem persistência)

Responsável exclusivamente pelo fanout de eventos SSE entre instâncias. Sem este Redis, clientes SSE conectados a instâncias que não consomem o evento Kafka nunca receberiam a notificação (ver ADR 001).

| Canal | Tipo de payload | Propósito |
|---|---|---|
| `tx-events` | `TransactionEvent` (JSON) | Fanout de eventos de cashin/cashout para todas as instâncias |
| `cb-events` | `CircuitBreakerEvent` (JSON) | Fanout de eventos de circuit breaker para todas as instâncias |

- Valkey é wire-compatible com Redis — zero mudança de código para comandos Pub/Sub
- Conexões ioredis separadas: uma para `PUBLISH`, outra para `SUBSCRIBE` (requisito do protocolo)
- Sem AOF/RDB em produção — dados são efêmeros por natureza

### Kafka

**Consumer topics** (projeção do read model + alertas):

| Tópico | Ação |
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
| `balancing.recalibrated.v1` | Log operacional |
| `webhook.dlq.v1` | Alerta operacional |

**Producer topics:**

| Tópico | Quando |
|---|---|
| `balancing.recalibrated.v1` | Operador ajusta pesos manualmente |

**Client:** `@nestjs/microservices` com transport Kafka (KafkaJS integrado). Consumer group: `backoffice-api`. Partition key: `tenant_id`.

### Observabilidade

| Camada | Tecnologia | Papel |
|---|---|---|
| Logging | Winston (JSON estruturado) | Logs para DataDog Log Management |
| APM / Tracing | dd-trace-js | Distributed tracing, auto-instrumentation |
| Métricas | dd-trace-js custom metrics | Request latency, Kafka consumer lag, error rates |
| Dashboards | DataDog | Operacional + alertas |

Pino e Prometheus são **removidos** do boilerplate. Winston é escolhido pela integração nativa com DataDog (winston-datadog-logs transport).

**Tags obrigatórias em todos os logs e traces:** `tenant_id`, `organization_id`, `user_id`, `request_id`, `trace_id`.

**PII masking:** CPF, email, telefone e nomes nunca aparecem em logs. Mesmas regras do ecossistema:
- CPF: `***.***.789-01`
- Email: `c***@example.com`
- Telefone: `***4321`

---

## 8. Endpoints da API (V1)

### Infraestrutura

| Método | Endpoint | Descrição | Auth |
|---|---|---|---|
| `GET` | `/api/health` | Health check (DB, Redis, Kafka) | Público |
| `GET` | `/api/health/redis-propagation` | Snapshot do backlog de reconciliação Redis (`redis_propagation_pending_total`) | Público |

### Autenticação + 2FA

| Método | Endpoint | Descrição | Auth |
|---|---|---|---|
| `POST` | `/api/auth/login` | Login email/senha → se 2FA habilitado: retorna `{ two_factor_required, session_token }`; se não: JWT + refresh token (HttpOnly cookie) | Público |
| `POST` | `/api/auth/2fa/verify` | Valida OTP enviado por email → JWT + refresh token | session_token |
| `POST` | `/api/auth/2fa/resend` | Reenvia OTP por email (max 3 reenvios) | session_token |
| `POST` | `/api/auth/refresh` | Renova JWT com refresh token válido | Cookie |
| `POST` | `/api/auth/logout` | Invalida sessão (blacklist JWT + refresh token no Redis) | JWT |
| `PUT` | `/api/auth/password` | Altera senha do usuário autenticado (exige senha atual) | JWT |

### Organizations (novo em V1)

| Método | Endpoint | Descrição | Perfil |
|---|---|---|---|
| `GET` | `/api/organizations` | Lista organizações | ADMIN |
| `POST` | `/api/organizations` | Cria organização | ADMIN |
| `PUT` | `/api/organizations/:id` | Atualiza organização | ADMIN |
| `DELETE` | `/api/organizations/:id` | Desativa organização (soft delete) | ADMIN |

### Tenants

| Método | Endpoint | Descrição | Perfil |
|---|---|---|---|
| `GET` | `/api/tenants` | Lista tenants da organization do usuário | ADMIN, OPERATIONS |
| `GET` | `/api/tenants/:id` | Detalhe de um tenant | ADMIN, OPERATIONS |
| `POST` | `/api/tenants` | Cria tenant (gera Bearer Token em `tenant_auth`) | ADMIN |
| `PUT` | `/api/tenants/:id` | Atualiza tenant | ADMIN |
| `DELETE` | `/api/tenants/:id` | Desativa tenant (soft delete) | ADMIN |
| `POST` | `/api/tenants/:id/resync-redis` | Reprocessa manualmente as chaves Redis do tenant | ADMIN |

### BaaS Providers

| Método | Endpoint | Descrição | Perfil |
|---|---|---|---|
| `GET` | `/api/tenants/:tid/providers` | Lista BaaS providers do tenant (sem credenciais) | ADMIN, OPERATIONS |
| `GET` | `/api/tenants/:tid/providers/:pid` | Detalhe (credenciais mascaradas) | ADMIN, OPERATIONS |
| `POST` | `/api/tenants/:tid/providers` | Cadastra provider + armazena credenciais no AWS Secrets Manager | ADMIN |
| `PUT` | `/api/tenants/:tid/providers/:pid` | Atualiza metadados do provider | ADMIN |
| `PUT` | `/api/tenants/:tid/providers/:pid/credentials` | Rotaciona credenciais (novo secret no SM) | ADMIN |
| `DELETE` | `/api/tenants/:tid/providers/:pid` | Desativa provider (soft delete) | ADMIN |
| `POST` | `/api/tenants/:tid/providers/:pid/test-connection` | Testa conectividade com o BaaS | ADMIN |
| `POST` | `/api/tenants/:tid/providers/resync-redis` | Reprocessa manualmente a chave `tenant:providers` no Redis | ADMIN |

> **Credenciais de BaaS Providers:** armazenadas exclusivamente no AWS Secrets Manager (path: `payflow/{env}/tenants/{tenant_id}/providers/{provider_code}`). O `backoffice-api` tem IAM write-only (`PutSecretValue`, `CreateSecret`); o core (cashin/cashout-service) tem IAM read-only (`GetSecretValue`). Credenciais nunca persistem em banco, cache ou logs.

### Transações (read model)

| Método | Endpoint | Descrição | Perfil |
|---|---|---|---|
| `GET` | `/api/deposits` | Lista depósitos com filtros (período, status, tenant, provedor, CPF, ID) | ALL |
| `GET` | `/api/deposits/:id` | Detalhe de um depósito | ALL |
| `GET` | `/api/withdrawals` | Lista saques com filtros equivalentes | ALL |
| `GET` | `/api/withdrawals/:id` | Detalhe de um saque | ALL |

**Filtros comuns:** `tenant_id`, `status`, `provider_id`, `date_from`, `date_to`, `document_number`, `merchant_transaction_id`, `payer_id`. Paginação: `page` + `limit` (default 20, max 100).

> `SUPPORT` tem acesso de leitura básica (sem campos sensíveis como `document_number` completo).

### Provedores e Balanceamento

| Método | Endpoint | Descrição | Perfil |
|---|---|---|---|
| `GET` | `/api/providers` | Lista provedores por tenant | ADMIN, OPERATIONS |
| `GET` | `/api/providers/:id/kicks` | Histórico de kicks do provedor | ADMIN, OPERATIONS |
| `GET` | `/api/providers/:id/performance` | Métricas de conversão e volumetria | ADMIN, OPERATIONS |
| `GET` | `/api/balancing/:tenant_id` | Config atual de balanceamento | ADMIN, OPERATIONS |
| `PUT` | `/api/balancing/:tenant_id` | Atualiza pesos e modo (manual) | ADMIN, OPERATIONS |

### Circuit Breaker

| Método | Endpoint | Descrição | Perfil |
|---|---|---|---|
| `GET` | `/api/circuit-breaker/:tenant_id` | Estado atual do CB por provedor e flow_type (lê Redis) | ADMIN, OPERATIONS |
| `PUT` | `/api/circuit-breaker/:tenant_id/config` | Atualiza thresholds do CB | ADMIN, OPERATIONS |
| `POST` | `/api/circuit-breaker/:tenant_id/kick` | Kick manual de provedor/flow (body: `provider_id`, `flow_type`) | ADMIN, OPERATIONS |
| `POST` | `/api/circuit-breaker/:tenant_id/reinstate` | Reinstate manual de provedor/flow (body: `provider_id`, `flow_type`) | ADMIN, OPERATIONS |

### Usuários

| Método | Endpoint | Descrição | Perfil |
|---|---|---|---|
| `GET` | `/api/users` | Lista usuários da organization do JWT (`active`, `roleId`, paginação) | ADMIN |
| `GET` | `/api/users/:id` | Retorna usuário da organization do JWT por ID | ADMIN |
| `POST` | `/api/users` | Cadastra novo usuário e dispara notificação por e-mail (retry/outbox em falha) | ADMIN |
| `PUT` | `/api/users/:id` | Atualiza perfil, escopo (`tenantIds`), `active` e `twoFactorEnabled` | ADMIN |
| `DELETE` | `/api/users/:id` | Desativa usuário (soft delete) | ADMIN |

### Auditoria

> O sistema mantém **dois ledgers de auditoria distintos**:
> - `transaction_audit_ledger` — trilha cronológica de eventos financeiros (cashin/cashout), escrita exclusivamente pelo `audit-worker` via Kafka. Acessada pelos endpoints abaixo (leitura).
> - `backoffice_audit_log` — trilha de ações administrativas privilegiadas (CREATE/UPDATE/DEACTIVATE/CONFIG_UPDATE/KICK/REINSTATE), escrita pelo `backoffice-api` em toda operação de escrita. Cobre roles ADMIN e OPERATIONS (OWASP ASVS V7).

| Método | Endpoint | Descrição | Perfil |
|---|---|---|---|
| `GET` | `/api/audit/transactions/:id` | Histórico cronológico completo de uma transação | ADMIN, COMPLIANCE |
| `GET` | `/api/audit` | Trilha de eventos com filtros (período, tipo, tenant, direção) | ADMIN, COMPLIANCE |

### Eventos em Tempo Real (SSE)

| Método | Endpoint | Descrição | Perfil |
|---|---|---|---|
| `GET` | `/api/events/transactions` | Stream SSE de mudanças de status de depósitos e saques | ALL |
| `GET` | `/api/events/circuit-breaker` | Stream SSE de kicks e recoveries de circuit breaker | ADMIN, OPERATIONS |

**Comportamento:**
- Protocolo: `text/event-stream` (Server-Sent Events) — HTTP/1.1, unidirecional (servidor → cliente)
- Auth: JWT HttpOnly cookie (mesmo guard dos demais endpoints)
- Escopo: eventos filtrados por `user.tenant_ids` — operador nunca recebe eventos de tenants fora do seu acesso
- Cada evento SSE carrega campo `id` (`transaction_id` ou ULID), `data` como **array** de eventos (batching 500ms)
- Batching: `bufferTime(500ms)` no pipeline RxJS — reduz re-renders de 50×/s para 2×/s em picos de carga
- At-least-once delivery: cada evento SSE carrega `id`; browser reenvia `Last-Event-ID` na reconexão; endpoint replaya eventos do DB mais recentes que esse ID antes de retomar o stream ao vivo
- Reconexão automática gerenciada pelo browser via `EventSource` nativo (sem biblioteca extra no frontend)
- O frontend substitui polling por uma conexão SSE persistente por tela

**Fluxo interno (multi-instância):**
```
Kafka event → Projection Handler (instância A)
  ├── escrita no backoffice-db (durável)
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

## 9. Arquitetura de Módulos (NestJS)

### Estrutura de diretórios

```
src/
├── main.ts                          → Bootstrap, guards globais, CORS, prefix /api
├── app.module.ts                    → Root module, DataSources, global providers
│
├── common/                          → Código compartilhado cross-module
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
├── infrastructure/                  → Adaptadores de infra
│   ├── database/                    → TypeORM modules (backoffice-db + core-db)
│   ├── cache/                       → Redis module, CacheService + ICacheService
│   ├── kafka/                       → Kafka consumer/producer setup, base handlers
│   ├── secrets/                     → AWS Secrets Manager module (ISecretsService, SecretsManagerService)
│   └── observability/               → Winston config, dd-trace setup, health check
│
├── auth/                            → Autenticação e autorização
│   ├── interfaces/                  → IAuthService, ITokenService, ITwoFactorService
│   ├── controllers/                 → AuthController
│   ├── services/                    → AuthService, TokenService, TwoFactorService
│   ├── strategies/                  → JwtStrategy (Passport)
│   └── dto/                         → LoginDto, RefreshDto, TwoFactorVerifyDto, ChangePasswordDto
│
├── organizations/                   → CRUD de organizações (core-db)
│   ├── interfaces/                  → IOrganizationRepository, IOrganizationService
│   ├── controllers/                 → OrganizationController
│   ├── services/                    → OrganizationService
│   ├── repositories/                → OrganizationRepository (core-db connection)
│   ├── entities/                    → Organization entity
│   └── dto/                         → CreateOrganizationDto, UpdateOrganizationDto
│
├── tenants/                         → Consulta e config de tenants (core-db)
│   ├── interfaces/                  → ITenantRepository, ITenantService
│   ├── controllers/                 → TenantController
│   ├── services/                    → TenantService
│   ├── repositories/                → TenantRepository (core-db connection)
│   ├── entities/                    → Tenant, ProviderConfig, RoutingConfig, etc.
│   └── dto/                         → Query DTOs, config DTOs
│
├── deposits/                        → Consulta de cash-in (backoffice-db)
│   ├── interfaces/                  → IDepositRepository, IDepositService
│   ├── controllers/                 → DepositController
│   ├── services/                    → DepositService
│   ├── repositories/                → DepositRepository
│   ├── entities/                    → CashinTransaction entity
│   └── dto/                         → DepositsQueryDto
│
├── withdrawals/                     → Consulta de cash-out (backoffice-db)
│   ├── interfaces/                  → IWithdrawalRepository, IWithdrawalService
│   ├── controllers/                 → WithdrawalController
│   ├── services/                    → WithdrawalService
│   ├── repositories/                → WithdrawalRepository
│   ├── entities/                    → CashoutTransaction entity
│   └── dto/                         → WithdrawalsQueryDto
│
├── providers/                       → BaaS Providers (CRUD + credenciais SM) e Circuit Breaker
│   ├── interfaces/                  → IProviderRepository, IProviderService, ICBService, ISecretsService
│   ├── controllers/                 → ProviderController, CircuitBreakerController
│   ├── services/                    → ProviderService, CircuitBreakerService
│   ├── repositories/                → ProviderConfigRepository, CBEventRepository
│   ├── entities/                    → ProviderConfig entity, CircuitBreakerEvent entity
│   └── dto/                         → CreateProviderDto, UpdateProviderDto, CredentialsDto, KickDto, ReinstateDto, CBConfigDto
│
├── balancing/                       → Configuração de balanceamento
│   ├── interfaces/                  → IBalancingRepository, IBalancingService
│   ├── controllers/                 → BalancingController
│   ├── services/                    → BalancingService
│   ├── repositories/                → RoutingConfigRepository (core-db)
│   └── dto/                         → UpdateBalancingDto
│
├── users/                           → Gestão de usuários internos
│   ├── interfaces/                  → IUserRepository, IUserService
│   ├── controllers/                 → UserController
│   ├── services/                    → UserService
│   ├── repositories/                → UserRepository (backoffice-db)
│   ├── entities/                    → BackofficeUser entity
│   └── dto/                         → CreateUserDto, UpdateUserDto
│
├── audit/                           → Trilha de auditoria
│   ├── interfaces/                  → IAuditRepository, IAuditService
│   ├── controllers/                 → AuditController
│   ├── services/                    → AuditService
│   ├── repositories/                → AuditLedgerRepository (backoffice-db, read-only)
│   ├── entities/                    → TransactionAuditLedger entity
│   └── dto/                         → AuditQueryDto
│
├── events/                          → SSE — stream de eventos em tempo real
│   ├── interfaces/                  → IEventsService
│   ├── controllers/                 → EventsController (@Sse decorator)
│   ├── services/                    → EventsService (RxJS Subject alimentado por Redis Pub/Sub)
│   └── dto/                         → TransactionEventDto, CircuitBreakerEventDto
│
└── projections/                     → Kafka consumers → read model + emissão de eventos SSE
    ├── interfaces/                  → IProjectionHandler
    ├── cashin.projection.ts         → Consumer: transaction.cashin.*.v1 → atualiza DB + emite SSE
    ├── cashout.projection.ts        → Consumer: transaction.cashout.*.v1 → atualiza DB + emite SSE
    ├── circuit-breaker.projection.ts → Consumer: circuit_breaker.*.v1 → atualiza DB + emite SSE
    └── dlq.projection.ts           → Consumer: webhook.dlq.v1 → alerta operacional
```

### Padrão por módulo (Hexagonal Light + interfaces SOLID)

Cada módulo de domínio segue o padrão:

```
module/
  ├── interfaces/
  │   ├── module-service.interface.ts    → IModuleService
  │   └── module-repository.interface.ts → IModuleRepository
  ├── controllers/
  │   └── module.controller.ts           → Injeta IModuleService
  ├── services/
  │   └── module.service.ts              → Implementa IModuleService, injeta IModuleRepository
  ├── repositories/
  │   └── module.repository.ts           → Implementa IModuleRepository, usa TypeORM
  ├── entities/
  │   └── entity.ts                      → TypeORM entity
  ├── dto/
  │   └── *.dto.ts                       → class-validator + class-transformer
  └── module.module.ts                   → NestJS module com providers vinculados por token
```

**Regra:** Controller nunca acessa Repository diretamente. Service é injetado via interface token (`provide: 'IModuleService', useClass: ModuleService`). Repository é injetado no Service via interface token. Testes unitários mocam as interfaces.

---

## 10. Segurança

> **Baseline:** OWASP Top 10 (2021). Edge protection via WAF + API Gateway + ALB (`x-api-key` nativa do API Gateway gerenciada via Terraform/SRE — `backoffice-api` em subnet privada, não exposto diretamente à internet).

| Mecanismo | Implementação |
|---|---|
| **Auth** | JWT com HttpOnly cookie (`Secure`, `SameSite=Strict`) — access token 15min + refresh token 2 dias. Payload inclui `user_id`, `email`, `organization_id`, `role`, `tenant_ids`, `jti` |
| **2FA** | OTP 6 dígitos via email (AWS SES), obrigatório para perfis ADMIN e COMPLIANCE. Sessão temporária pré-2FA no Redis (TTL 5min). Max 3 reenvios por sessão |
| **Password hashing** | bcrypt (salt rounds: 12) |
| **Password policy** | Mínimo 8 chars, maiúscula + minúscula + dígito + caractere especial, rejeita top 10k senhas comuns (OWASP) |
| **Account lockout** | 5 tentativas de login falhas → bloqueio de 15min. Contador no Redis (`login_attempts:{email}`, TTL 15min) |
| **Logout** | Blacklist JWT via Redis (`jwt_blacklist:{jti}`, TTL = tempo restante do token) + invalidação do refresh token |
| **RBAC** | Guard NestJS que valida `role` do JWT contra decorador `@Roles()`. Deny-by-default |
| **Multi-tenant isolation** | RLS em todas as tabelas do `backoffice-db`. User vê apenas tenants autorizados pelo ADMIN (todos da Organization ou subset específico via `tenant_ids`) |
| **PII masking** | MaskingInterceptor global para responses. Logs nunca contêm PII em claro |
| **Security headers** | Helmet.js com configuração OWASP (CSP, HSTS, X-Frame-Options, etc.) |
| **CORS** | Restrito ao domínio do frontend (FRONTEND_URL) |
| **Rate limiting** | ThrottlerModule global (100 req/min default) + WAF rate limit por IP na borda |
| **Input validation** | ValidationPipe global (whitelist + forbidNonWhitelisted + transform) |
| **Edge protection** | WAF (DDoS, OWASP rules) + API Gateway (throttling global, `x-api-key`) + ALB (VPC Link → ECS subnet privada) |
| **Secrets** | Zero secrets em env vars em produção — AWS Secrets Manager. Credenciais de BaaS providers: IAM write-only (`PutSecretValue`/`CreateSecret`) no backoffice; IAM read-only (`GetSecretValue`) no core. HMAC keys e Bearer Tokens nunca passam pelo backoffice |
| **Audit trail admin (OWASP ASVS V7)** | Toda ação de escrita privilegiada (CREATE, UPDATE, DEACTIVATE, CONFIG_UPDATE, KICK, REINSTATE, CREDENTIALS_ROTATE) gera registro append-only em `backoffice_audit_log` com `actor_id`, `actor_email`, `actor_role`, `resource_type`, `resource_id`, `payload_before`, `payload_after`, `ip_address`, `performed_at`. Campos sensíveis são sanitizados antes do log (`password_hash`, credenciais). Cobre todas as roles com escrita (ADMIN e OPERATIONS). Entidades afetadas persistem `deleted_at` + `deleted_by` no soft delete |

### Scoping de acesso por Organization + tenant_ids

O ADMIN controla o acesso granular de cada usuário:

1. Login retorna JWT com `{ user_id, organization_id, role, tenant_ids[] }`
2. `tenant_ids[]` é calculado no login:
   - Se `backoffice_users.tenant_ids` está **vazio** (`{}`): `SELECT id FROM tenants WHERE organization_id = $1 AND active = true` → acesso a **todos** os tenants da Organization
   - Se `backoffice_users.tenant_ids` está **preenchido**: usa a lista direta (validada como subconjunto dos tenants ativos da Organization)
3. Todo endpoint que acessa dados por tenant valida `tenant_id ∈ user.tenant_ids`
4. RLS no `backoffice-db`: `SET LOCAL app.current_tenant_id` por request (para queries de transações)
5. Queries ao `core-db`: filtro explícito `WHERE organization_id = $1` (sem RLS no core-db para simplificar, já que o gateway também lê core-db)

> **Regra de negócio:** o ADMIN define no cadastro/edição do usuário se ele vê todos os tenants (tenant_ids vazio) ou apenas tenants específicos (tenant_ids preenchido). Tenants listados devem pertencer à Organization do usuário — a API valida isso no `POST /users` e `PUT /users/:id`.

---

## 11. Propagação de Configuração

Quando o operador atualiza uma configuração no backoffice (pesos, limites, provider ativo/inativo):

```
1. backoffice-api valida input (DTO + business rules)
2. Escreve no core-db (fonte de verdade)
3. Atualiza cache Redis (fast-path para o core)
4. Finaliza a propagação no Redis (sem fanout Kafka de configuração)
```

Este fluxo garante:
- **Consistência:** core-db é a fonte de verdade
- **Performance:** Redis serve as leituras do core em microsegundos
- **Desacoplamento:** backoffice não faz chamadas HTTP síncronas ao core
- **Auditabilidade:** trilha via audit log e histórico operacional no próprio backoffice

### 11.1 Resiliência Redis (retry + outbox + resync)

Implementação atual para falhas de Redis durante propagação de configuração:

- **Retry local com backoff+jitter** em todas as operações de escrita Redis do módulo de propagação (`TenantConfigPropagationService`).
- **Contrato forte (rollback + 500)** para fluxos críticos de criação e rotação de token:
  - criação de tenant
  - criação de provider
  - rotação de bearer token de tenant
- **Contrato com reconciliação operacional** para updates/deletes de configuração:
  - em falha de Redis após persistência no `core-db`, registra item na tabela `redis_propagation_outbox` (`core-db`) e mantém rastreabilidade por log estruturado.
- **Resync operacional explícito** via endpoints administrativos:
  - `POST /api/tenants/:id/resync-redis`
  - `POST /api/tenants/:tid/providers/resync-redis`
- **Observabilidade mínima**:
  - evento de log `redis_propagation_failed`
  - métrica operacional via `GET /api/health/redis-propagation`

Variáveis de tuning do retry:

- `REDIS_PROPAGATION_MAX_RETRIES`
- `REDIS_PROPAGATION_BASE_DELAY_MS`
- `REDIS_PROPAGATION_MAX_DELAY_MS`

---

## 12. Infraestrutura e Deploy

### Docker Compose (desenvolvimento local)

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
      AWS_ENDPOINT_URL: http://localstack:4566   # Secrets Manager emulado
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
      - "8025:8025"   # Web UI para inspeção de emails 2FA
```

### Produção (AWS)

| Componente | Serviço AWS |
|---|---|
| backoffice-api | ECS Fargate |
| backoffice-db | RDS PostgreSQL 16 |
| core-db | RDS PostgreSQL 16 (compartilhado com hub-gateway read) |
| Redis (core) | ElastiCache Redis 7 (compartilhado com core) |
| Valkey (auth) | ElastiCache for Valkey (exclusivo backoffice-api, AOF habilitado) |
| Valkey (Pub/Sub eventos) | ElastiCache for Valkey (isolado, sem persistência) |
| Kafka | MSK (compartilhado com core) |
| Observabilidade | DataDog (agent no ECS, logs via CloudWatch → DataDog) |
| IaC | Terraform (responsabilidade SRE) |

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

## 13. Estratégia de Testes

### Abordagem

Toda regra de negócio entregue vem acompanhada do teste que a valida, cobrindo o caminho de sucesso e ao menos um caso de rejeição. A ordem em que teste e implementação são escritos fica a critério de quem implementa — o que é verificado no gate é a cobertura da regra, não a sequência.

### Tipos de testes

| Tipo | Ferramenta | Target | DB |
|---|---|---|---|
| **Unit** | Jest | Services, guards, interceptors, validators | Mocks (interfaces) |
| **Integration** | Jest + SQLite in-memory | Repositories, modules com DI real | SQLite |
| **E2E** | Jest + Supertest | Endpoints completos (HTTP → DB → Response) | SQLite in-memory |

### Cobertura

| Escopo | Mínimo |
|---|---|
| Global (branches, functions, lines, statements) | 90% |
| Services (`*.service.ts`) | 90% |
| Repositories (`*.repository.ts`) | 90% |
| Controllers | 85% (lógica delegada ao service) |
| DTOs / Entities | Cobertura indireta via integration/e2e |

### O que testar com prioridade

- **Auth flow:** login, refresh, logout, JWT validation, blacklist
- **2FA flow:** login → OTP email → verify → JWT; reenvio; max 3 tentativas; sessão expirada
- **Account lockout:** 5 falhas → bloqueio 15min; reset após bloqueio
- **Password policy:** rejeição de senhas fracas; hash bcrypt correto
- **RBAC:** cada endpoint valida role corretamente (deny-by-default)
- **Kafka consumers:** projeções inserem/atualizam corretamente no read model
- **Config propagation:** core-db → Redis
- **Organization scoping:** user não vê tenants de outra organization; user com tenant_ids restrito não vê tenants fora da lista
- **RLS:** queries filtradas por tenant_id
- **BaaS Providers:** credenciais armazenadas no SM, nunca retornadas em claro; rotação de credenciais; test-connection

### Benchmarking (hot spots only)

- Kafka consumer throughput (events/second)
- Endpoint de listagem com paginação (deposits, withdrawals) sob carga
- Redis write latency para config propagation

### Fuzzing (áreas críticas)

- DTOs de input (LoginDto, CreateUserDto, UpdateBalancingDto)
- Kafka event payload parsing (envelope validation)
- Auth token parsing e validation

---

## 14. Requisitos Não-Funcionais

| Requisito | Meta | Prioridade |
|---|---|---|
| **P0 — Correctness** | | |
| Multi-tenant isolation | Zero leak entre tenants (RLS + Organization scoping) | P0 |
| Kafka consumer idempotência | Reprocessamento de offset não gera duplicatas | P0 |
| Config propagation atomicidade | core-db + Redis em sequência; rollback quando aplicável | P0 |
| **P1 — Regression Prevention** | | |
| Test coverage | ≥ 90% nas classes de regra de negócio | P1 |
| CI pipeline | Lint + test + coverage em todo push | P1 |
| Pre-commit hooks | Husky: lint-staged + test | P1 |
| **P2 — Security** | | |
| JWT HttpOnly cookie | Token não acessível via JavaScript | P2 |
| 2FA via email | OTP 6 dígitos, obrigatório para ADMIN/COMPLIANCE | P2 |
| Account lockout | 5 tentativas falhas → bloqueio 15min | P2 |
| PII masking | Nenhum dado pessoal em logs ou responses não autorizadas | P2 |
| Password policy | bcrypt salt 12, min 8 chars, complexidade OWASP, rejeita top 10k | P2 |
| RBAC enforcement | Backend valida role em todo endpoint (deny-by-default) | P2 |
| Security headers | Helmet.js — CSP, HSTS, X-Frame-Options, etc. | P2 |
| Edge protection | WAF + API Gateway + ALB (subnet privada, `x-api-key` via Terraform/SRE) | P2 |
| **P3 — Quality** | | |
| Structured logging | JSON com trace_id, tenant_id, user_id | P3 |
| Error handling | HttpExceptionFilter global, erros tipados, sem stack traces em prod | P3 |
| API documentation | Swagger/OpenAPI auto-gerado via decorators | P3 |
| Code style | ESLint + Prettier + Husky (Conventional Commits) | P3 |
| **P4 — Performance** | | |
| API latency P95 | < 500ms (consultas paginadas no read model) | P4 |
| Kafka consumer lag | < 5s (projeções near real-time) | P4 |
| SSE latência de entrega | < 2s do evento Kafka ao cliente conectado | P4 |
| Health check | < 100ms | P4 |
| Disponibilidade | 99.5% (backoffice não é caminho crítico) | P4 |

---

## 15. Fases de Implementação

As fases e milestones deste serviço são geradas por `/wiz-phases` e `/wiz-milestones` a partir deste PRD, e ficam em `.wiz/backoffice-api/phases/`. Este documento define **o que** entregar e sob quais critérios; o **como** e em que ordem é resultado do planejamento.

Restrições que o planejamento deve respeitar:

- A fundação (scaffold, persistência, autenticação) precede qualquer feature de consulta ou configuração.
- A projeção do read model depende da fundação e é pré-requisito das telas operacionais.
- Segurança é P1, empatada com testes — nenhuma fase entrega endpoint sem autenticação e autorização.

## 16. Dev Seed Strategy

> O dev seed é parte obrigatória da Fase 1. Seu objetivo é permitir que qualquer desenvolvedor dos outros microservices (`hub-gateway`, `cashin-service`, `cashout-service`, `webhook-service`, `audit-worker`) suba a stack localmente usando o `backoffice-api` como fonte de dados de configuração, sem precisar inserir dados manualmente.

### Como usar (outros times)

```bash
# 1. Subir a infra do backoffice
docker compose up -d

# 2. Rodar migrations + seed completo
npm run migration:run
npm run seed:all    # equivale a: seed:db + seed:redis + seed:secrets
```

Após esses comandos, o `core-db`, Redis e LocalStack estarão populados com os dados de dev documentados abaixo. Os valores são fixos e versionados — não mudam entre execuções.

---

### 16.1 Seed do `core-db` (Migration seed)

IDs fixos para dev — garantem que outros serviços possam referenciar por UUID sem lookup:

```sql
-- Organization
INSERT INTO organizations (id, name, slug, active) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Acme', 'acme', true);

-- Tenants
-- ATENÇÃO: webhook_url NÃO é o endpoint que recebe callbacks dos provedores BaaS.
-- Os BaaS sempre chamam o webhook-service em POST /webhook/{provider} (URL fixa do Hub).
-- webhook_url é o endereço do PARCEIRO (Vertex) para onde o webhook-service
-- envia as notificações de saída (outbound) após processar o callback do BaaS.
-- Fluxo: BaaS → webhook-service → lê webhook_url do Redis → POST {webhook_url} + HMAC → Vertex
-- Em dev, aponta para um servidor mock local que simula o endpoint receptor da Vertex.
INSERT INTO tenants (id, organization_id, name, slug, webhook_url, active) VALUES
  ('00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000001',
   'Acme', 'acme', 'http://mock-partner:3100/webhook/acme', true),
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001',
   'Globex', 'globex', 'http://mock-partner:3100/webhook/globex', true);

-- Provider configs (Acme — Aurora + Nimbus)
INSERT INTO provider_configs (tenant_id, provider_id, base_url, active) VALUES
  ('00000000-0000-0000-0000-000000000010', 'aurora', 'http://mock-aurora:8080', true),
  ('00000000-0000-0000-0000-000000000010', 'nimbus', 'http://mock-nimbus:8080', true);

-- Routing configs — pesos iniciais (CASHIN + CASHOUT)
INSERT INTO routing_configs (tenant_id, provider_id, flow_type, position, weight, mode) VALUES
  ('00000000-0000-0000-0000-000000000010', 'aurora', 'CASHIN',  1, 70, 'MANUAL'),
  ('00000000-0000-0000-0000-000000000010', 'nimbus', 'CASHIN',  2, 30, 'MANUAL'),
  ('00000000-0000-0000-0000-000000000010', 'aurora', 'CASHOUT', 1, 70, 'MANUAL'),
  ('00000000-0000-0000-0000-000000000010', 'nimbus', 'CASHOUT', 2, 30, 'MANUAL');

-- Circuit Breaker configs — thresholds padrão
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
-- Token bruto fica no LocalStack (ver 16.3)
INSERT INTO tenant_auth (tenant_id, token_hash, token_hint, active) VALUES
  ('00000000-0000-0000-0000-000000000010',
   'a3f1e2d4b5c6789012345678abcdef0123456789abcdef0123456789abcdef01',
   'sk-dev-', true);
```

---

### 16.2 Seed do `backoffice-db` (Migration seed)

```sql
-- Usuário ADMIN padrão
-- Senha: Admin@123456 (bcrypt hash — alterar no primeiro login em produção)
INSERT INTO backoffice_users
  (id, organization_id, email, name, role, tenant_ids, active, password_hash) VALUES
  ('00000000-0000-0000-0000-000000000100',
   '00000000-0000-0000-0000-000000000001',
   'admin@acme.local', 'Admin Default', 'ADMIN', '{}', true,
   '$2b$12$<hash_gerado_na_migration>');
```

---

### 16.3 Seed do Redis (`npm run seed:redis`)

Script executado após as migrations. Lê os dados do `core-db` e popula as chaves exatamente como o backoffice-api faria ao salvar uma configuração via endpoint. Garante que `hub-gateway`, `cashin-service` e `cashout-service` encontrem os dados no Redis no primeiro request.

Chaves populadas (tenant_id = `00000000-0000-0000-0000-000000000010`):

```
tenant:config:00000000-0000-0000-0000-000000000010
  → { "webhook_url": "http://mock-partner:3100/webhook/acme",
      -- webhook_url = endereço do PARCEIRO (Vertex) para notificações outbound
      -- NÃO é o endpoint dos provedores BaaS. Os BaaS sempre chamam /webhook/{provider} no Hub.
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
  TTL: 300s (5 min — renovado automaticamente no lookup do hub-gateway)
```

---

### 16.4 Seed do LocalStack — Secrets Manager (`npm run seed:secrets`)

Script shell ou Node.js que cria os secrets no LocalStack via AWS CLI ou SDK. Esses secrets são lidos pelos serviços core em dev.

```bash
# Bearer Token do Acme (lido pelo hub-gateway no Secrets Manager como fallback)
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name "payflow/dev/tenants/acme/api-key" \
  --secret-string "sk-dev-acme-localtoken01"

# Credentials mock do provedor Aurora (lidas pelo cashin-service e cashout-service)
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name "payflow/dev/tenants/acme/providers/aurora" \
  --secret-string '{"api_key":"dev-aurora-key-001","api_secret":"dev-aurora-secret-001","client_id":"aurora-dev-client"}'

# Credentials mock do provedor Nimbus (lidas pelo cashin-service e cashout-service)
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name "payflow/dev/tenants/acme/providers/nimbus" \
  --secret-string '{"api_key":"dev-nimbus-key-001","api_secret":"dev-nimbus-secret-001","client_id":"nimbus-dev-client"}'

# HMAC key do Acme para validação de webhooks (lida pelo webhook-service)
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name "payflow/dev/tenants/acme/hmac-key" \
  --secret-string "dev-hmac-key-acme-local-0001"
```

---

### 16.5 Referência rápida para outros times

| Dado | Valor dev |
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
| **mock-partner (simula Vertex)** | `http://mock-partner:3100` |

> **Nota:** o Bearer Token `sk-dev-acme-localtoken01` é exclusivo para ambiente de desenvolvimento. Nunca usar em staging ou produção. O token e seu hash são fixos para reprodutibilidade — qualquer desenvolvedor pode referenciar o `tenant_id` por UUID sem lookup.

> **Sobre `webhook_url`:** o campo `webhook_url` no tenant **não é** o endpoint que recebe callbacks dos provedores BaaS. Os BaaS (Aurora, Nimbus) sempre chamam o `webhook-service` em `POST /webhook/{provider}` — URL fixa do Hub. O `webhook_url` é o endereço do **parceiro** (Vertex) para onde o `webhook-service` envia as notificações de saída após processar o callback do BaaS. Fluxo: `BaaS → webhook-service → lê webhook_url do Redis → POST {webhook_url} + HMAC → Vertex`. Em dev, `mock-partner` é um servidor HTTP simples (ex: [Mockoon](https://mockoon.com/) ou `json-server`) que simula o receptor da Vertex.

---

## 17. Open Questions

Todas as questões foram resolvidas. Registradas abaixo para rastreabilidade.

| # | Questão | Decisão | Impacto |
|---|---|---|---|
| 1 | Política de retenção do read model (`cashin_transactions`, `cashout_transactions`) | **Fora do escopo de V1.** V2 implementará via EventBridge Scheduler + Lambda (sem lock distribuído na aplicação). Sem purge em V1 — tabelas crescem sem limite até V2 ser entregue | Movido para Non-Goals |
| 2 | `GET /providers/:id/performance` — on-the-fly ou pré-computado? | **On-the-fly em V1** (volume baixo). **V2** evolui para tabela pré-computada com job de agregação periódico. | Sem impacto no schema V1. Nota adicionada no endpoint |
| 3 | Atualização em tempo real das telas de transações | **SSE (Server-Sent Events)** — unidirecional, sem polling. `EventsService` alimentado por Redis Pub/Sub (Valkey) para fanout multi-instância; `bufferTime(500ms)` para batching; `Last-Event-ID` para at-least-once. | `events/` module + 2 endpoints SSE na Fase 2 |

---

## 18. Appendix

### 18.1 Decisões de design

| Decisão | Opção escolhida | Justificativa |
|---|---|---|
| Scaffold | Limpo (descartar Palmtree) | Módulos do boilerplate não se aplicam ao Hub |
| Dual DataSource | Primária (backoffice-db) + Named (core-db) | Separação clara de responsabilidades |
| Kafka client | @nestjs/microservices + KafkaJS | Integração nativa com NestJS, menos boilerplate |
| Docker Compose | Stack completa (2xPG + Redis + Redpanda + LocalStack + MailHog) | Permite testar Kafka, Secrets Manager e 2FA localmente |
| Testes | Unit (mock) + Integration (SQLite) + E2E | 90% de cobertura na regra de negócio |
| Observabilidade | Winston + dd-trace-js (sem Pino/Prometheus) | DataDog como stack única do ecossistema |
| CI/CD | Bitbucket Pipelines + Husky | Alinhado ao ecossistema multi-repo |
| Admin seed | Migration default | Garantia de primeiro acesso sem script manual |
| Arquitetura | Hexagonal Light + interfaces SOLID | Desacoplamento completo com testabilidade |
| Organization | Tabela `organizations` em V1 | Necessidade real de agrupamento; aditiva e sem impacto no core |
| 2FA | OTP via email (AWS SES), obrigatório ADMIN/COMPLIANCE | Segurança OWASP sem fricção para perfis operacionais |
| JWT refresh | 2 dias (não 7) | Equilíbrio entre segurança e UX; alinhado ao ecossistema |
| Secrets Manager | infrastructure/secrets/ com LocalStack em dev | Credenciais de BaaS providers nunca em banco, cache ou logs |
| Tenants CRUD | POST/PUT/DELETE com geração de Bearer Token | CRUD completo em V1 — onboarding de novos tenants pelo operador |
| Dev Seed | UUIDs fixos + `seed:all` (DB + Redis + Secrets) | Outros times (hub-gateway, cashin-service, etc.) sobem com dados prontos sem configuração manual |
| UUIDs de dev | Fixos e versionados na migration seed | Reprodutibilidade — outros services referenciam tenant_id por UUID sem lookup |
| SSE vs. WebSocket | SSE (`text/event-stream`) | Unidirecional (servidor → cliente) — suficiente para notificações de transação. Sem overhead de full-duplex. Reconexão nativa do browser via `EventSource` |
| SSE fanout multi-instância | Redis Pub/Sub via Valkey isolado (`REDIS_PUBSUB_URL`) | RxJS Subject (in-process) falha em deploys multi-instância. Redis Pub/Sub garante fanout para todas as instâncias com latência sub-ms. Instância separada isola falhas do Redis core. Ver ADR 001. |
| SSE batching | `bufferTime(500ms)` no pipeline RxJS | Cenários de alta frequência (50+ eventos/s) causariam re-renders excessivos. Janela de 500ms reduz atualizações de UI para 2/s sem perda de dados. |
| SSE at-least-once | `Last-Event-ID` + replay do DB | Redis Pub/Sub é at-most-once. `Last-Event-ID` permite ao endpoint replavar eventos perdidos do DB na reconexão, garantindo at-least-once para o frontend. |
| Retenção read model | **V2** via EventBridge Scheduler + Lambda | V1 sem purge — multi-instância tornaria lock distribuído necessário, o que é complexidade desnecessária para V1. V2 delega ao SRE via Terraform |
| Performance on-the-fly V1 | `GET /providers/:id/performance` faz query direta | Volume baixo em V1 — aceitável. V2 adiciona job de pré-computação periódica |

### 18.2 PRD do hub — alterações sugeridas

Nenhuma pendência identificada: o PRD do hub (`docs/product/PRD.md`) já cobre as definições de Organization, Partner e Tenant usadas aqui.
