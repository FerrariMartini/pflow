# Phase 4: RBAC Deny-by-Default, Scoping por Organization e Trilha Administrativa

**Duration**: ~3 days (24 milestones @ 1h each)
**Dependencies**: Phase 3
**Status**: 🚧 TODO

## Goal

Fechar o modelo de autorização antes de qualquer endpoint de dado existir: perfil, escopo de tenant e registro append-only de toda ação privilegiada. Sem esta fase, nenhuma fase seguinte pode expor endpoint.

Entregas principais:
- `RolesGuard` + decorator `@Roles()` validando os 5 perfis (`ADMIN`, `OPERATIONS`, `FINANCE`, `COMPLIANCE`, `SUPPORT`) contra a matriz de permissões da §6 do PRD, com deny-by-default: endpoint sem `@Roles()` e sem `@Public()` é negado.
- `AuthContextService` + decorator `@CurrentUser()` expondo `organization_id`, `role` e `tenant_ids` derivados do JWT.
- Cálculo de `tenant_ids` no login: vazio (`{}`) → todos os tenants ativos da Organization; preenchido → subconjunto validado dos tenants ativos da Organization.
- `TenantScopeGuard`/helper que valida `tenant_id ∈ user.tenant_ids` em todo acesso por tenant, e aplicação de `SET LOCAL app.current_tenant_id` por requisição para as queries RLS do `backoffice-db`.
- Filtro explícito `WHERE organization_id = $1` no padrão de acesso ao `core-db`.
- `BackofficeAuditLogService` + interceptor gravando append-only em `backoffice_audit_log` (`actor_id`, `actor_email`, `actor_role`, `resource_type`, `resource_id`, `payload_before`, `payload_after`, `ip_address`, `performed_at`) para CREATE, UPDATE, DEACTIVATE, CONFIG_UPDATE, KICK, REINSTATE e CREDENTIALS_ROTATE, com sanitização de campos sensíveis (OWASP ASVS V7).
- Padrão de soft delete (`deleted_at` + `deleted_by`) compartilhado.

## Phase Acceptance Criteria

- Um endpoint de teste sem `@Roles()` e sem `@Public()` retorna 403 — deny-by-default provado por teste e2e, não apenas por convenção.
- A matriz de permissões da §6 do PRD está codificada em uma tabela de teste parametrizada (perfil × ação) e todos os casos passam, incluindo os negativos.
- Usuário de uma Organization não enxerga tenant de outra Organization; usuário com `tenant_ids` restrito não enxerga tenant fora da lista — dois testes de integração distintos, contra banco real do compose (P0 — multi-tenant isolation).
- `tenant_ids` vazio resolve para todos os tenants ativos da Organization no login, e tenant inativo não entra na lista — coberto por teste unitário e de integração.
- Toda escrita privilegiada gera exatamente um registro em `backoffice_audit_log`, com `payload_before`/`payload_after` sanitizados (`password_hash` e credenciais nunca presentes) — verificado por teste.
- `backoffice_audit_log` é append-only: tentativa de UPDATE/DELETE é bloqueada no nível do banco, coberta por teste de integração.
- Cobertura ≥ 90% em guards, `AuthContextService` e `BackofficeAuditLogService`; `scripts/pre-commit.sh` verde.
- Nenhum endpoint das fases seguintes pode ser mergeado sem `@Roles()` — regra documentada no README do serviço e verificada pelo teste de deny-by-default.

## Milestones

<!-- Milestones appended by /wiz-milestones -->

### P04M01: Definir enum `BackofficeRole` e decorator `@Roles()`

**Status:** 🚧 TODO
**ID:** P04M01

**Goal**

Criar o enum dos cinco perfis RBAC da §6 do PRD e o decorator `@Roles()` que anota a metadata de autorização nos handlers, base sobre a qual o `RolesGuard` opera.

**Acceptance Criteria**

- [ ] `src/common/enums/backoffice-role.enum.ts` define `BackofficeRole` com exatamente `ADMIN`, `OPERATIONS`, `FINANCE`, `COMPLIANCE` e `SUPPORT`
- [ ] `src/common/decorators/roles.decorator.ts` exporta `@Roles(...)` via `SetMetadata`, com a chave `ROLES_KEY` exportada para consumo pelo `Reflector`
- [ ] Decorator é aplicável em método e em classe, com a precedência do método sobre a classe documentada em JSDoc
- [ ] A assinatura exige ao menos um perfil, de modo que `@Roles()` sem argumento falhe em tempo de compilação
- [ ] Teste unitário lê a metadata via `Reflector` e valida os perfis anotados em handler e em controller
- [ ] `npm run lint` e `npm run build` verdes

---

### P04M02: Codificar a matriz de permissões da §6 do PRD

**Status:** 🚧 TODO
**ID:** P04M02

**Goal**

Traduzir a matriz perfil × ação da §6 do PRD em uma estrutura tipada única, que serve tanto de fonte para os decorators dos endpoints das fases seguintes quanto de oráculo dos testes de autorização.

**Acceptance Criteria**

- [ ] `src/common/authorization/permission-matrix.ts` define o tipo `PermissionAction` com as treze ações da §6 (consulta de depósitos, consulta de saques, exportação CSV, config balanceamento, config circuit breaker, histórico de kicks, gestão de organizações, gestão de tenants, consulta de tenants, gestão de BaaS providers, consulta de BaaS providers, gestão de usuários, trilha de auditoria)
- [ ] `PERMISSION_MATRIX` mapeia cada `PermissionAction` para o conjunto exato de `BackofficeRole` permitidos, idêntico célula a célula à tabela da §6
- [ ] A leitura básica do `SUPPORT` em depósitos e saques está representada explicitamente, e `SUPPORT` aparece negado em exportação CSV
- [ ] Helper `rolesFor(action: PermissionAction): readonly BackofficeRole[]` exportado para uso direto nos decorators `@Roles()`
- [ ] Estrutura declarada `as const` / `readonly`, sem mutação possível em runtime
- [ ] Teste unitário compara a matriz com a tabela da §6 incluindo as células negadas, e falha se alguma ação ficar sem entrada

---

### P04M03: Implementar `RolesGuard`

**Status:** 🚧 TODO
**ID:** P04M03

**Goal**

Entregar o guard que compara o `role` do JWT emitido na Phase 3 com os perfis exigidos pelo handler, registrado globalmente logo após o `JwtAuthGuard`.

**Acceptance Criteria**

- [ ] `src/common/guards/roles.guard.ts` resolve a metadata de handler e de classe via `Reflector.getAllAndOverride`
- [ ] Requisição cujo `role` está na lista exigida é permitida; caso contrário o guard produz 403 com `code` estável, traduzido pelo `DomainExceptionFilter` da Phase 2
- [ ] Guard registrado como `APP_GUARD` global depois do `JwtAuthGuard`, de modo que 401 tenha precedência sobre 403 para token ausente ou inválido
- [ ] Rotas anotadas com `@Public()` não são avaliadas pelo `RolesGuard`
- [ ] Log da negação registra `user_id`, `role` e rota, sem PII em claro, conforme `docs/technical/guidelines/logging.md`
- [ ] Testes unitários cobrem: perfil permitido, perfil negado, rota pública e metadata de classe sobrescrita no método
- [ ] Cobertura ≥ 90% no arquivo do guard

---

### P04M04: Provar deny-by-default para handler sem `@Roles()`

**Status:** 🚧 TODO
**ID:** P04M04

**Goal**

Garantir que um handler autenticado sem `@Roles()` e sem `@Public()` seja negado pelo guard — comportamento provado por teste, não apenas por convenção de código.

**Acceptance Criteria**

- [ ] `RolesGuard` nega com 403 quando não existe metadata `ROLES_KEY` no handler nem na classe e a rota não é `@Public()`
- [ ] Fixture de teste expõe um controller com um handler sem `@Roles()` e sem `@Public()`
- [ ] Teste e2e prova 403 nesse handler usando um JWT válido de cada um dos cinco perfis
- [ ] Teste e2e prova que o mesmo handler, quando anotado com `@Roles(BackofficeRole.ADMIN)`, responde 200 para ADMIN
- [ ] A fixture vive apenas em `test/` e não é registrada no `AppModule` de produção
- [ ] A resposta de negação não revela quais perfis seriam necessários para acessar a rota

---

### P04M05: Teste parametrizado da matriz de permissões

**Status:** 🚧 TODO
**ID:** P04M05

**Goal**

Cobrir a matriz de permissões inteira com uma tabela de teste parametrizada perfil × ação, incluindo todos os casos negativos, de forma que uma ação nova nunca fique sem cobertura.

**Acceptance Criteria**

- [ ] O teste percorre o produto cartesiano dos cinco perfis pelas ações de `PERMISSION_MATRIX` usando `it.each`, sem casos escritos manualmente
- [ ] Cada combinação permitida resulta em acesso concedido e cada combinação negada resulta em 403
- [ ] Asserção explícita verifica que o número de casos executados é igual a 5 × número de ações da matriz
- [ ] Acrescentar uma ação em `PERMISSION_MATRIX` sem cobertura correspondente faz a suíte falhar
- [ ] Os negativos incluem ao menos SUPPORT em exportação CSV, OPERATIONS em trilha de auditoria e FINANCE em config de balanceamento
- [ ] A suíte parametrizada completa executa em menos de 10 segundos

---

### P04M06: Implementar `AuthContextService`

**Status:** 🚧 TODO
**ID:** P04M06

**Goal**

Entregar o serviço com escopo de requisição que expõe o contexto autenticado — `organization_id`, `role` e `tenant_ids` — derivado do JWT, para que nenhum service precise ler o objeto `Request`.

**Acceptance Criteria**

- [ ] `src/common/interfaces/auth-context.interface.ts` define `IAuthContextService` e o tipo `AuthenticatedUser` com `user_id`, `email`, `organization_id`, `role`, `tenant_ids` e `jti`
- [ ] `src/common/services/auth-context.service.ts` implementa `IAuthContextService` com escopo `REQUEST` e é provido pelo token `'IAuthContextService'`
- [ ] Métodos `getUser()`, `getOrganizationId()`, `getRole()` e `getTenantIds()` disponíveis e tipados
- [ ] Acessar o contexto em requisição não autenticada lança `DomainError` tipado, nunca retorna `undefined` silencioso
- [ ] O serviço não importa nada de infraestrutura, conforme `docs/technical/guidelines/dependency-injection.md`
- [ ] Testes unitários cobrem contexto presente, contexto ausente e `tenant_ids` vazio; cobertura ≥ 90%

---
