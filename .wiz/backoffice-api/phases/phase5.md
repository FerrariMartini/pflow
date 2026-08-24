# Phase 5: Organizations e Tenants — CRUD, Bearer Token e Propagação Redis Resiliente

**Duration**: ~4 days (34 milestones @ 1h each)
**Dependencies**: Phase 4
**Status**: 🚧 TODO

## Goal

Entregar a gestão de Organizations e Tenants no `core-db` junto com o mecanismo de propagação de configuração para o Redis descrito na §11 e §11.1 do PRD — o ponto onde o backoffice deixa de ser só leitura e passa a alimentar o core em tempo real.

Entregas principais:
- `GET/POST/PUT/DELETE /api/organizations` (ADMIN, soft delete), com `slug` único.
- `GET /api/tenants`, `GET /api/tenants/:id`, `POST`, `PUT`, `DELETE /api/tenants/:id` — CRUD completo com geração de Bearer Token em `tenant_auth` (hash + `token_hint`, token bruto exibido uma única vez na resposta de criação).
- `TenantConfigPropagationService`: escrita no `core-db` como fonte de verdade seguida da atualização das chaves `tenant:config:*`, `tenant:limits:*`, `tenant:providers:*` e `routing:weights:*` no Redis Core.
- Retry local com backoff + jitter parametrizado por `REDIS_PROPAGATION_MAX_RETRIES`, `REDIS_PROPAGATION_BASE_DELAY_MS`, `REDIS_PROPAGATION_MAX_DELAY_MS`.
- Contrato forte (rollback da transação + 500) para criação de tenant, criação de provider e rotação de bearer token.
- Contrato com reconciliação (persistir em `redis_propagation_outbox` no `core-db` + log `redis_propagation_failed`) para updates e deletes de configuração.
- `POST /api/tenants/:id/resync-redis` (ADMIN) para reprocessamento manual.
- `GET /api/health/redis-propagation` expondo `redis_propagation_pending_total`.

## Phase Acceptance Criteria

- CRUD de organizations e tenants completo, com RBAC aplicado por endpoint conforme a matriz (§6): tenants é ADMIN para escrita e ADMIN+OPERATIONS para leitura, organizations é ADMIN-only — coberto por teste e2e positivo e negativo.
- Criação de tenant grava `tenant_auth` com hash do Bearer Token e `token_hint`; o token bruto aparece uma única vez na resposta e nunca é persistido em claro, cacheado ou logado — verificado por teste.
- Falha de Redis na criação de tenant faz rollback completo no `core-db` e retorna 500: nenhum tenant órfão fica persistido — teste de integração com Redis derrubado/mockado em falha.
- Falha de Redis em update/delete de configuração persiste o item em `redis_propagation_outbox`, emite o log estruturado `redis_propagation_failed` e mantém a resposta de sucesso — teste de integração dedicado.
- Retry aplica backoff com jitter e respeita as três variáveis de tuning; teste unitário com timers falsos cobre esgotamento de tentativas e sucesso na segunda tentativa.
- `POST /api/tenants/:id/resync-redis` reconstrói todas as chaves do tenant a partir do `core-db` e zera os itens correspondentes do outbox; `GET /api/health/redis-propagation` reflete a queda de `redis_propagation_pending_total` — coberto por e2e.
- Toda escrita gera registro em `backoffice_audit_log`, e tenant desativado persiste `deleted_at` + `deleted_by`.
- Cobertura ≥ 90% em `OrganizationService`, `TenantService`, `TenantConfigPropagationService` e repositories; `scripts/pre-commit.sh` verde.
- `docs/contract/contract.md` atualizado com os endpoints de organizations e tenants no mesmo PR.

## Milestones

<!-- Milestones appended by /wiz-milestones -->
### P05M01: Criar entidade Organization e a interface do repositório

**Status:** 🚧 TODO
**ID:** P05M01

**Goal**

Modelar a entidade TypeORM `Organization` na DataSource nomeada `core`, refletindo exatamente o schema criado na Phase 1 (§7 do PRD), e declarar o contrato `IOrganizationRepository` em `src/organizations/interfaces/`.

**Acceptance Criteria**

- [ ] `src/organizations/entities/organization.entity.ts` mapeia `id` (UUID), `name` (varchar 100), `slug` (varchar 50, único), `active`, `created_at`, `updated_at`, `deleted_at`, `deleted_by`
- [ ] A entidade está registrada apenas na DataSource `core` e é consumida via `@InjectRepository(Organization, 'core')`
- [ ] `IOrganizationRepository` declara `findAll`, `findById`, `findBySlug`, `create`, `update` e `softDelete`, sem nenhum tipo do TypeORM vazando na assinatura
- [ ] A entidade estende o `BaseEntity` comum da Phase 1 quando isso não conflitar com o schema do `core-db`
- [ ] Nenhum import de infraestrutura em `interfaces/`, conforme `docs/technical/guidelines/dependency-injection.md`
- [ ] `npm run lint` e `npm run build` passam

---

### P05M02: Implementar OrganizationRepository na DataSource core

**Status:** 🚧 TODO
**ID:** P05M02

**Goal**

Implementar `OrganizationRepository` contra o `core-db`, cobrindo consulta, criação, atualização e soft delete com `deleted_at` + `deleted_by`.

**Acceptance Criteria**

- [ ] `OrganizationRepository` implementa `IOrganizationRepository` e é registrado por token de interface no `OrganizationModule`
- [ ] Todas as leituras excluem registros com `deleted_at` preenchido
- [ ] `findBySlug` permite detectar colisão de `slug` antes do insert, incluindo organizações desativadas
- [ ] `softDelete(id, actorId)` grava `deleted_at = now()`, `deleted_by = actorId` e `active = false` em uma única operação
- [ ] `update` atualiza `updated_at` e nunca permite alterar `id` ou `created_at`
- [ ] Teste de integração contra o `postgres-core` do compose cobre criação, leitura, atualização, soft delete e a exclusão do registro deletado nas listagens

---

### P05M03: Implementar OrganizationService com regras de slug e desativação

**Status:** 🚧 TODO
**ID:** P05M03

**Goal**

Implementar `OrganizationService` (implementando `IOrganizationService`) com as regras de negócio de unicidade de `slug`, normalização e bloqueio de desativação de organização que ainda possui tenants ativos.

**Acceptance Criteria**

- [ ] `create` normaliza o `slug` (lowercase, trim) e rejeita duplicidade com `DomainError` tipado `ORGANIZATION_SLUG_ALREADY_EXISTS`
- [ ] `update` rejeita troca de `slug` para um valor já usado por outra organização, com o mesmo `code`
- [ ] `findById` lança `ORGANIZATION_NOT_FOUND` quando o registro não existe ou está soft-deletado
- [ ] `deactivate` lança `ORGANIZATION_HAS_ACTIVE_TENANTS` quando existem tenants ativos vinculados
- [ ] Nenhum `throw new Error(...)` em fluxo de negócio, conforme `docs/technical/guidelines/error-handling.md`
- [ ] O service recebe `IOrganizationRepository` por token de interface, sem acesso direto ao TypeORM

---

### P05M04: Expor GET/POST/PUT/DELETE /api/organizations restrito a ADMIN

**Status:** 🚧 TODO
**ID:** P05M04

**Goal**

Criar os DTOs de entrada e saída, o `OrganizationController` e o `OrganizationModule`, expondo os quatro endpoints de organizations exclusivamente para o perfil ADMIN conforme a matriz da §6 do PRD.

**Acceptance Criteria**

- [ ] `CreateOrganizationDto` e `UpdateOrganizationDto` validam `name` (1–100) e `slug` (1–50, padrão `^[a-z0-9-]+$`) com `class-validator`
- [ ] `GET /api/organizations` (paginado com o `PaginationDto` da Phase 2), `POST /api/organizations`, `PUT /api/organizations/:id` e `DELETE /api/organizations/:id` estão implementados
- [ ] Todos os quatro endpoints declaram `@Roles('ADMIN')`; nenhum deles é `@Public()`
- [ ] `DELETE` executa soft delete usando o `user_id` do `@CurrentUser()` como `deleted_by` e responde 204
- [ ] O controller injeta apenas `IOrganizationService` por token, nunca o repositório
- [ ] Endpoints anotados com decorators Swagger, incluindo o envelope de erro do `docs/contract/contract.md`

---

### P05M05: Cobrir OrganizationService e OrganizationRepository com testes unitários

**Status:** 🚧 TODO
**ID:** P05M05

**Goal**

Escrever a suíte unitária de organizations mocando `IOrganizationRepository`, cobrindo caminho feliz e todos os erros de negócio até atingir a meta de cobertura da fase.

**Acceptance Criteria**

- [ ] Testes cobrem `create` (sucesso, slug duplicado, normalização de slug), `update` (sucesso, slug em uso, não encontrado), `findAll`, `findById` e `deactivate` (sucesso, com tenants ativos)
- [ ] Cada `DomainError` do módulo tem pelo menos um teste dedicado, conforme `docs/technical/quality/qa-guidelines.md`
- [ ] Os testes mocam a interface do repositório, não a classe concreta
- [ ] Cobertura de `OrganizationService` e `OrganizationRepository` ≥ 90% em statements, branches e lines
- [ ] `npm run test:cov` passa sem testes pulados (`.skip`, `.todo`) e sem `any` nos mocks

---

### P05M06: Validar /api/organizations com testes e2e de RBAC e ciclo de vida

**Status:** 🚧 TODO
**ID:** P05M06

**Goal**

Escrever os testes e2e de organizations contra a stack do compose, cobrindo o ciclo completo de CRUD e o comportamento negativo de RBAC para os perfis sem permissão.

**Acceptance Criteria**

- [ ] Teste e2e cobre create → list → get → update → delete com um usuário ADMIN autenticado
- [ ] Teste parametrizado prova 403 para `OPERATIONS`, `FINANCE`, `COMPLIANCE` e `SUPPORT` nos quatro endpoints
- [ ] Requisição sem JWT retorna 401 em todos os endpoints do módulo
- [ ] `POST` com `slug` já existente retorna o status e o `code` mapeados pelo `DomainExceptionFilter`
- [ ] Após o `DELETE`, a organização some das listagens e o registro persiste `deleted_at` e `deleted_by` no `core-db`
- [ ] Cada escrita bem-sucedida gera exatamente um registro em `backoffice_audit_log` com `resource_type = 'ORGANIZATION'`

---
