# Phase 10: Gestão de Usuários Internos e Notificação por Email

**Duration**: ~3 days (20 milestones @ 1h each)
**Dependencies**: Phase 4
**Status**: 🚧 TODO

## Goal

Entregar a administração de usuários do backoffice (`src/users/`), incluindo o controle granular de escopo que o ADMIN exerce sobre o que cada operador enxerga — a contraparte de escrita do scoping implementado na Fase 4.

Entregas principais:
- `GET /api/users` (filtros `active`, `roleId`, paginação) e `GET /api/users/:id`, ambos restritos à Organization do JWT.
- `POST /api/users`: cadastro com senha inicial sob a password policy, disparando notificação por email (SES em produção, MailHog em dev) com retry/outbox em caso de falha de envio.
- `PUT /api/users/:id`: perfil, escopo (`tenantIds`), `active` e `twoFactorEnabled`.
- `DELETE /api/users/:id`: soft delete (`deleted_at` + `deleted_by`).
- Validação de que todo `tenantId` informado pertence à Organization do usuário, no `POST` e no `PUT`.

## Phase Acceptance Criteria

- Os cinco endpoints são ADMIN-only e retornam 403 para os outros quatro perfis — cobertos por e2e.
- Um ADMIN não consegue ler, criar, alterar nem desativar usuário de outra Organization — teste de integração explícito (P0 — isolamento).
- `tenantIds` contendo tenant de outra Organization ou tenant inativo é rejeitado com `DomainError` tipado, tanto no `POST` quanto no `PUT`; `tenantIds` vazio é aceito e significa "todos os tenants da Organization".
- Alterar `twoFactorEnabled` para `false` em usuário ADMIN ou COMPLIANCE é rejeitado (2FA é obrigatório para esses perfis) — caso de borda com teste.
- Falha no envio do email de cadastro não perde o usuário criado: o item entra na fila de retry/outbox e o log `error` estruturado é emitido — teste com transporte de email em falha.
- Nenhuma resposta de usuário expõe `password_hash`, e nenhum log de `/api/users` contém email em claro.
- Toda escrita gera registro em `backoffice_audit_log` com `payload_before`/`payload_after` sanitizados.
- Cobertura ≥ 90% em `UserService`; `scripts/pre-commit.sh` verde e `docs/contract/contract.md` atualizado no mesmo PR.

## Milestones

<!-- Milestones appended by /wiz-milestones -->

### P10M01: Criar a estrutura de `src/users/` e a entity `BackofficeUser`

**Status:** 🚧 TODO
**ID:** P10M01

**Goal**

Criar o esqueleto de diretórios de `src/users/` conforme a §9 do PRD e a entity TypeORM `BackofficeUser`, mapeando a tabela `backoffice_users` do `backoffice-db` criada na Fase 1, com `password_hash` blindado contra serialização.

**Acceptance Criteria**

- [ ] Diretórios `interfaces/`, `controllers/`, `services/`, `repositories/`, `entities/` e `dto/` criados em `src/users/`
- [ ] `BackofficeUser` mapeia `id`, `organization_id`, `email`, `name`, `role`, `tenant_ids`, `active`, `two_factor_enabled`, `password_hash`, `deleted_at`, `deleted_by`, `created_at` e `updated_at`
- [ ] `role` é tipada pelo enum dos cinco perfis da §6 do PRD (`ADMIN`, `OPERATIONS`, `FINANCE`, `COMPLIANCE`, `SUPPORT`), sem string literal solta
- [ ] `tenant_ids` mapeado como array de UUID com default `{}`, conforme a §10 do PRD
- [ ] `password_hash` declarado com `select: false` e `@Exclude()`, de modo que nenhuma serialização padrão o exponha
- [ ] Teste unitário prova que serializar a entity não produz a chave `password_hash`
- [ ] `npm run lint` e `npm run build` passam

---

### P10M02: Definir `IUserRepository`, `IUserService` e o `UsersModule`

**Status:** 🚧 TODO
**ID:** P10M02

**Goal**

Declarar os contratos do módulo de usuários e registrar os providers por token de injeção, seguindo o padrão Hexagonal Light da §9 do PRD e `docs/technical/guidelines/dependency-injection.md`.

**Acceptance Criteria**

- [ ] `IUserRepository` declara `findManyByOrganization`, `findByIdInOrganization`, `findByEmailInOrganization`, `create`, `update` e `softDelete`, todos tipados sem `any`
- [ ] `IUserService` declara `list`, `getById`, `create`, `update` e `deactivate`
- [ ] Toda assinatura de leitura e de escrita recebe `organizationId` explicitamente — nenhuma operação do contrato permite acesso sem escopo de Organization
- [ ] `UsersModule` registra `{ provide: 'IUserService', useClass: UserService }` e `{ provide: 'IUserRepository', useClass: UserRepository }`
- [ ] `UserController` injeta apenas `IUserService`; nenhuma referência a repository ou a TypeORM no controller
- [ ] `UsersModule` é importado por `AppModule` e a aplicação sobe sem provider órfão nem import circular
- [ ] `npm run lint` e `npm run build` passam

---

### P10M03: Implementar `UserRepository` escopado por Organization

**Status:** 🚧 TODO
**ID:** P10M03

**Goal**

Implementar o `UserRepository` sobre o `backoffice-db` com todas as queries filtrando `organization_id` e descartando registros soft-deleted, cobrindo leitura e escrita.

**Acceptance Criteria**

- [ ] Toda query aplica `WHERE organization_id = :organizationId AND deleted_at IS NULL`, sem exceção
- [ ] `findManyByOrganization` aceita os filtros opcionais `active` e `roleId` mais os parâmetros de paginação, retornando itens e total em uma única chamada
- [ ] Ordenação determinística (`created_at DESC, id DESC`) para paginação estável entre páginas
- [ ] `findByEmailInOrganization` é case-insensitive e também escopado por Organization
- [ ] `softDelete` grava `deleted_at` e `deleted_by` conforme o padrão da Fase 4, sem remover a linha
- [ ] `password_hash` só é carregado no método explicitamente usado na criação; consultas de listagem e detalhe nunca o trazem do banco
- [ ] Teste de integração contra o `backoffice-db` do compose cobre listagem filtrada, detalhe, criação, atualização e soft delete
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---

### P10M04: Criar os DTOs de consulta e de resposta do módulo de usuários

**Status:** 🚧 TODO
**ID:** P10M04

**Goal**

Criar `ListUsersQueryDto` (filtros `active` e `roleId` sobre a paginação compartilhada da Fase 2) e `UserResponseDto`, garantindo por construção que nenhuma resposta carregue `password_hash`.

**Acceptance Criteria**

- [ ] `ListUsersQueryDto` compõe o `PaginationDto` da Fase 2 (default 20, max 100)
- [ ] `active` é opcional e aceita apenas booleano, transformado a partir de `"true"`/`"false"`
- [ ] `roleId` é validado contra o enum dos cinco perfis; valor fora do enum retorna 400 com o envelope de erro do `docs/contract/contract.md`
- [ ] `UserResponseDto` expõe exatamente `id`, `email`, `name`, `role`, `tenantIds`, `active`, `twoFactorEnabled`, `createdAt` e `updatedAt` — e nenhum outro campo
- [ ] `UserResponseDto` não declara `password_hash` nem `passwordHash` sob nenhuma forma
- [ ] Query param não declarado no DTO é rejeitado com 400 pelo `forbidNonWhitelisted` global da Fase 2
- [ ] Teste unitário do mapper entity → `UserResponseDto` prova a ausência de `password_hash` mesmo quando a entity o carrega preenchido
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---

### P10M05: Implementar `GET /api/users` com filtros e paginação

**Status:** 🚧 TODO
**ID:** P10M05

**Goal**

Implementar `UserService.list` e o endpoint `GET /api/users`, ADMIN-only, retornando apenas usuários da Organization do JWT com os filtros `active` e `roleId` e paginação.

**Acceptance Criteria**

- [ ] `UserService.list` recebe a Organization do `@CurrentUser()` da Fase 4 e nunca de query param ou body
- [ ] `GET /api/users` é decorado com `@Roles('ADMIN')`, conforme a matriz de permissões da §6 do PRD
- [ ] Resposta usa o `PaginatedResponseDto` da Fase 2 com `items`, `total`, `page` e `limit`
- [ ] Filtros `active` e `roleId` funcionam isolados e combinados
- [ ] Usuários soft-deleted não aparecem na listagem
- [ ] Filtro sem resultado retorna 200 com lista vazia, nunca 404
- [ ] Teste e2e cobre listagem sem filtro, com `active=false`, com `roleId`, com filtro sem resultado e com `limit` acima do máximo
- [ ] Teste unitário de `UserService.list` com o repository mockado pela interface
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---

### P10M06: Implementar `GET /api/users/:id`

**Status:** 🚧 TODO
**ID:** P10M06

**Goal**

Implementar `UserService.getById` e o endpoint `GET /api/users/:id`, ADMIN-only, restrito à Organization do JWT e sem vazar a existência de usuários de outras Organizations.

**Acceptance Criteria**

- [ ] `id` é validado como UUID no path; valor inválido retorna 400
- [ ] `GET /api/users/:id` é decorado com `@Roles('ADMIN')`
- [ ] Usuário de outra Organization retorna 404 com `DomainError` tipado de não encontrado — nunca 403 nem mensagem que confirme a existência do registro
- [ ] Usuário soft-deleted retorna 404
- [ ] Resposta é serializada pelo `UserResponseDto`, sem `password_hash`
- [ ] Teste e2e cobre detalhe encontrado, UUID inválido, id inexistente, id de outra Organization e usuário soft-deleted
- [ ] Teste unitário de `UserService.getById` com o repository mockado
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---
