# Phase 9: Balanceamento de Provedores e Operação do Circuit Breaker

**Duration**: ~4 days (30 milestones @ 1h each)
**Dependencies**: Phase 5 (propagação Redis), Phase 7 (eventos de CB), Phase 8 (read model consultável)
**Status**: 🚧 TODO

## Goal

Entregar o controle operacional de runtime do Hub: visibilidade de provedores, ajuste manual de pesos de balanceamento com propagação em tempo real, e operação do circuit breaker (estado, thresholds, kick e reinstate manuais).

Entregas principais:
- `GET /api/providers` (lista por tenant), `GET /api/providers/:id/kicks` (histórico a partir de `circuit_breaker_events`) e `GET /api/providers/:id/performance` (conversão e volumetria calculadas on-the-fly em V1).
- `GET /api/balancing/:tenant_id` e `PUT /api/balancing/:tenant_id` (pesos e modo `MANUAL`), gravando em `routing_configs` e propagando `routing:weights:{tenant_id}:{flow_type}` pelo serviço da Fase 5.
- Producer Kafka de `balancing.recalibrated.v1` quando o operador ajusta pesos manualmente.
- `GET /api/circuit-breaker/:tenant_id` lendo `cb:state:*` e `cb:halfopen:*` do Redis Core (somente leitura — essas chaves são escritas pelo core).
- `PUT /api/circuit-breaker/:tenant_id/config` gravando em `circuit_breaker_configs` (`circuit_breaker_configs:{tenant_id}:{provider_id}:{flow_type}` como chave oficial, nunca `tenant:config`).
- `POST /api/circuit-breaker/:tenant_id/kick` e `POST /api/circuit-breaker/:tenant_id/reinstate` (body: `provider_id`, `flow_type`).

## Phase Acceptance Criteria

- Todos os 9 endpoints exigem ADMIN ou OPERATIONS e negam FINANCE, COMPLIANCE e SUPPORT — negativos cobertos por e2e conforme a matriz da §6.
- `PUT /api/balancing/:tenant_id` valida que a soma dos pesos e o conjunto de providers são consistentes com os providers ativos do tenant, rejeitando com `DomainError` tipado nos casos inválidos (peso negativo, provider inexistente, provider inativo, flow_type inválido) — um teste por caso.
- Ajuste de pesos grava no `core-db`, propaga `routing:weights:*` no Redis e publica `balancing.recalibrated.v1` com o envelope do `docs/contract/contract.md` — verificado por teste de integração contra Redpanda.
- Falha de Redis no ajuste de pesos cai no `redis_propagation_outbox` sem perder a escrita no `core-db`, e o resync da Fase 5 reconstrói a chave — teste dedicado.
- `GET /api/circuit-breaker/:tenant_id` nunca escreve em `cb:state:*`/`cb:halfopen:*`; o teste prova que a operação é read-only sobre essas chaves.
- Kick e reinstate manuais geram registro em `backoffice_audit_log` com `KICK`/`REINSTATE`, `actor_*` e `flow_type`, e são idempotentes (kick sobre provider já kickado não duplica estado) — cobertos por teste.
- `GET /api/providers/:id/performance` calcula conversão e volumetria a partir do read model com resultado determinístico sobre massa fixa de teste, incluindo o caso de zero transações no período (sem divisão por zero).
- Cobertura ≥ 90% em `BalancingService` e `CircuitBreakerService`; `scripts/pre-commit.sh` verde e `docs/contract/contract.md` atualizado no mesmo PR.

## Milestones

<!-- Milestones appended by /wiz-milestones -->

### P09M01: Mapear entities de routing e circuit breaker no core-db e criar o módulo `balancing/`

**Status:** 🚧 TODO
**ID:** P09M01

**Goal**

Mapear as entities TypeORM de `routing_configs` e `circuit_breaker_configs` na conexão `core` e criar o módulo `balancing/` no padrão Hexagonal Light da §9 do PRD, deixando os tokens de DI prontos para os milestones seguintes.

**Acceptance Criteria**

- [ ] `src/balancing/entities/routing-config.entity.ts` mapeia `routing_configs` (`tenant_id`, `provider_id`, `flow_type`, `position`, `weight`, `mode`) na conexão `core`
- [ ] `src/providers/entities/circuit-breaker-config.entity.ts` mapeia `circuit_breaker_configs` (`tenant_id`, `provider_id`, `flow_type`, `consecutive_threshold`, `suspension_minutes`) na conexão `core`
- [ ] `src/balancing/balancing.module.ts` criado com `interfaces/`, `controllers/`, `services/`, `repositories/` e `dto/` conforme o padrão por módulo da §9
- [ ] Tokens `IBalancingService` e `IBalancingRepository` registrados via `provide`/`useClass`; nenhuma injeção por classe concreta
- [ ] `providers.module.ts` estendido com os tokens `ICircuitBreakerService` e `ICBEventRepository`
- [ ] Repositories acessam as entities via `@InjectRepository(Entity, 'core')` e a aplicação sobe sem erro de metadata
- [ ] `scripts/pre-commit.sh` verde

---

### P09M02: Implementar a consulta de provedores por tenant no repositório

**Status:** 🚧 TODO

**ID:** P09M02

**Goal**

Implementar no repositório de providers a consulta que alimenta `GET /api/providers`, lendo `provider_configs` no `core-db` já restrita aos tenants visíveis pelo usuário autenticado.

**Acceptance Criteria**

- [ ] Método `findByTenant(tenantIds, filtros)` em `ProviderConfigRepository` lê `provider_configs` na conexão `core` e retorna `tenant_id`, `provider_id`, `base_url` e `active`
- [ ] Filtro opcional `tenant_id`; sem filtro, retorna apenas os tenants de `user.tenant_ids` (ou todos os tenants da organization quando `tenant_ids` está vazio)
- [ ] Provider de tenant fora do escopo do usuário nunca aparece no resultado
- [ ] Registros com `deleted_at` preenchido são excluídos por padrão
- [ ] Nenhuma credencial de provider é lida ou retornada — apenas metadados
- [ ] Testes unitários com repositório mockado cobrem escopo total, escopo restrito e resultado vazio
- [ ] `scripts/pre-commit.sh` verde

---

### P09M03: Expor `GET /api/providers`

**Status:** 🚧 TODO
**ID:** P09M03

**Goal**

Publicar o endpoint de listagem de provedores por tenant, restrito a ADMIN e OPERATIONS, com paginação e escopo multi-tenant aplicados.

**Acceptance Criteria**

- [ ] `ProviderController` expõe `GET /api/providers` com `@Roles('ADMIN', 'OPERATIONS')`
- [ ] Query DTO valida `tenant_id` (UUID opcional) e paginação `page`/`limit` (default 20, max 100) reusando o `PaginationDto` da Fase 2
- [ ] Resposta usa `PaginatedResponseDto` e expõe `tenant_id`, `provider_id`, `base_url` e `active`
- [ ] `tenant_id` fora de `user.tenant_ids` retorna 403 via `DomainError` tipado
- [ ] Controller injeta apenas `IProviderService` por token, nunca o repositório
- [ ] e2e positivo para ADMIN e OPERATIONS, e 401 sem JWT
- [ ] `scripts/pre-commit.sh` verde

---

### P09M04: Implementar a consulta de histórico de kicks em `circuit_breaker_events`

**Status:** 🚧 TODO
**ID:** P09M04

**Goal**

Implementar no `CBEventRepository` a consulta paginada do histórico de kicks e recoveries de um provedor a partir da tabela `circuit_breaker_events` do `backoffice-db`, projetada na Fase 7.

**Acceptance Criteria**

- [ ] `CBEventRepository.findKicksByProvider(providerId, tenantIds, filtros)` consulta `circuit_breaker_events` na conexão primária
- [ ] Filtros `tenant_id`, `flow_type`, `date_from` e `date_to` suportados, com paginação `page`/`limit`
- [ ] Resultado ordenado por `occurred_at` decrescente, incluindo tipo do evento (kick/recovery), `provider_id`, `flow_type`, motivo e timestamp
- [ ] Query respeita a RLS do `backoffice-db` (`SET LOCAL app.current_tenant_id`) e o escopo de `user.tenant_ids`
- [ ] Índice de suporte por (`provider_id`, `occurred_at`) criado por migration caso ainda não exista
- [ ] Testes de integração sobre massa fixa cobrem filtro por período e provider sem nenhum evento
- [ ] `scripts/pre-commit.sh` verde

---

### P09M05: Expor `GET /api/providers/:id/kicks`

**Status:** 🚧 TODO
**ID:** P09M05

**Goal**

Publicar o endpoint de histórico de kicks do provedor para ADMIN e OPERATIONS, com validação de período e escopo por tenant.

**Acceptance Criteria**

- [ ] `GET /api/providers/:id/kicks` exposto no `ProviderController` com `@Roles('ADMIN', 'OPERATIONS')`
- [ ] `:id` resolvido como `provider_id` existente para algum tenant no escopo do usuário; inexistente retorna `PROVIDER_NOT_FOUND` (404)
- [ ] Query DTO valida `tenant_id`, `flow_type` (`CASHIN`|`CASHOUT`), `date_from`, `date_to`, `page` e `limit`
- [ ] Intervalo de datas invertido é rejeitado com `DomainError` tipado (400)
- [ ] Resposta paginada, ordenada do evento mais recente para o mais antigo
- [ ] e2e cobre ADMIN, OPERATIONS, provider sem kicks e provider de tenant fora do escopo (403)
- [ ] `scripts/pre-commit.sh` verde

---

### P09M06: Implementar o cálculo de conversão e volumetria sobre o read model

**Status:** 🚧 TODO
**ID:** P09M06

**Goal**

Implementar no `ProviderService` o cálculo on-the-fly de conversão e volumetria por provedor a partir de `cashin_transactions` e `cashout_transactions`, tratando o período sem transações sem divisão por zero.

**Acceptance Criteria**

- [ ] Método `getPerformance(providerId, tenantIds, periodo)` agrega contagem total, aprovadas, falhas e soma de valores por `flow_type`
- [ ] Taxa de conversão calculada como aprovadas/total, arredondada com precisão fixa e documentada (2 casas decimais)
- [ ] Período com zero transações retorna conversão `0` e volumetria zerada, sem exceção, sem divisão por zero e sem `NaN`/`Infinity`
- [ ] Agregação executada em SQL (`COUNT`/`SUM` com `GROUP BY`), não em memória sobre o conjunto completo de linhas
- [ ] Query restrita ao `provider_id` informado e aos tenants do escopo do usuário
- [ ] Testes unitários cobrem total > 0, total = 0 e cenário só com transações falhas
- [ ] `scripts/pre-commit.sh` verde

---
