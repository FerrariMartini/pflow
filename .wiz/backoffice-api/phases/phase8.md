# Phase 8: Consultas de Depósitos e Saques com Filtros, Paginação e Masking por Perfil

**Duration**: ~3 days (24 milestones @ 1h each)
**Dependencies**: Phase 7
**Status**: 🚧 TODO

## Goal

Entregar as telas operacionais de consulta sobre o read model projetado na Fase 7 — a primeira entrega de valor direto para Operações, Financeiro, Compliance e Atendimento.

Entregas principais:
- `GET /api/deposits` e `GET /api/deposits/:id` (`src/deposits/`).
- `GET /api/withdrawals` e `GET /api/withdrawals/:id` (`src/withdrawals/`).
- Filtros comuns: `tenant_id`, `status`, `provider_id`, `date_from`, `date_to`, `document_number`, `merchant_transaction_id`, `payer_id`.
- Paginação `page` + `limit` (default 20, max 100) usando o `PaginatedResponseDto` da Fase 2.
- Escopo por `user.tenant_ids` aplicado em toda query, com `SET LOCAL app.current_tenant_id` (RLS) por requisição.
- Regra específica de `SUPPORT`: leitura básica, sem `document_number` completo.
- Índices de consulta no `backoffice-db` (período, status, tenant, provider) dimensionados para o alvo de p95 < 500ms.

## Phase Acceptance Criteria

- Os quatro endpoints estão acessíveis a todos os 5 perfis conforme a matriz (§6) e negam usuário não autenticado — cobertos por e2e.
- `SUPPORT` recebe `document_number` mascarado enquanto ADMIN/OPERATIONS/FINANCE/COMPLIANCE recebem o valor completo — teste parametrizado por perfil, tanto na listagem quanto no detalhe.
- Consulta com `tenant_id` fora de `user.tenant_ids` retorna 403; consulta sem `tenant_id` retorna apenas os tenants autorizados — dois testes de integração (P0 — multi-tenant isolation).
- Todos os oito filtros funcionam isolados e combinados, incluindo os casos de borda: intervalo de datas invertido, `limit` acima de 100, `page` inexistente e filtro sem resultado — cada um com teste.
- Consulta paginada sobre massa de teste representativa responde em p95 < 500ms com os índices criados, medido por benchmark de hot spot registrado no repositório.
- Nenhum campo sensível aparece em log de consulta; o `MaskingInterceptor` cobre também os campos do read model.
- Cobertura ≥ 90% em `DepositService`, `WithdrawalService` e respectivos repositories; ≥ 85% nos controllers.
- `scripts/pre-commit.sh` verde e `docs/contract/contract.md` atualizado com os quatro endpoints no mesmo PR.

## Milestones

<!-- Milestones appended by /wiz-milestones -->
### P08M01: Criar o DTO base de consulta transacional com os oito filtros

**Status:** 🚧 TODO
**ID:** P08M01

**Goal**

Criar `TransactionQueryDto` compartilhado, estendendo o `PaginationDto` da Fase 2, declarando os oito filtros comuns da §8 do PRD com validação `class-validator`.

**Acceptance Criteria**

- [ ] `TransactionQueryDto` declara `tenant_id`, `status`, `provider_id`, `date_from`, `date_to`, `document_number`, `merchant_transaction_id` e `payer_id`, todos opcionais
- [ ] `tenant_id` e `provider_id` validados como UUID; `date_from` e `date_to` como data ISO 8601 com `@Type(() => Date)`
- [ ] `status` validado contra o enum de status do read model, rejeitando valor fora da lista com 400
- [ ] Herda `page` (default 1, mínimo 1) e `limit` (default 20, máximo 100) do `PaginationDto` da Fase 2, sem redeclarar as regras
- [ ] `forbidNonWhitelisted` do `ValidationPipe` global rejeita query param não declarado com 400
- [ ] Testes unitários cobrem, para cada filtro, um valor válido e um valor rejeitado
- [ ] `npm run lint` e `npm run test` verdes

---

### P08M02: Validar intervalo de datas e normalizar filtros textuais

**Status:** 🚧 TODO
**ID:** P08M02

**Goal**

Adicionar validador customizado que rejeita intervalo de datas invertido e normalizar os filtros textuais antes de chegarem ao repositório, evitando divergência de formato entre cliente e read model.

**Acceptance Criteria**

- [ ] Validador customizado `@IsValidDateRange()` no `TransactionQueryDto` rejeita `date_from` posterior a `date_to` com 400 e `code` estável do `docs/technical/guidelines/error-handling.md`
- [ ] `document_number` é normalizado para apenas dígitos (remove pontuação de CPF) via `@Transform`, antes da validação de tamanho
- [ ] `merchant_transaction_id` e `payer_id` sofrem `trim` e rejeitam string vazia
- [ ] `date_from` sem `date_to` (e vice-versa) é aceito e tratado como intervalo aberto
- [ ] Testes unitários cobrem: intervalo invertido, intervalo igual (`date_from == date_to`), intervalo aberto em cada ponta, CPF com e sem pontuação
- [ ] Nenhum valor de `document_number` aparece em log durante a validação — verificado por teste
- [ ] `npm run lint` e `npm run test` verdes

---

### P08M03: Implementar o query builder compartilhado do read model

**Status:** 🚧 TODO
**ID:** P08M03

**Goal**

Criar `TransactionQueryBuilder` compartilhado que traduz um `TransactionQueryDto` em cláusulas `WHERE` parametrizadas do TypeORM, reutilizado pelos repositórios de depósitos e saques.

**Acceptance Criteria**

- [ ] `TransactionQueryBuilder` aplica cada um dos oito filtros como predicado parametrizado, ignorando os filtros ausentes
- [ ] `date_from`/`date_to` são aplicados sobre a coluna de período do read model como intervalo fechado
- [ ] Toda query recebe obrigatoriamente `tenant_id IN (:...tenantIds)` a partir do escopo do usuário, mesmo quando nenhum filtro é informado
- [ ] Nenhum valor de filtro é concatenado em string SQL — apenas binding de parâmetro (prevenção de SQL injection, P2)
- [ ] Ordenação default estável por período decrescente e desempate por `id`, garantindo paginação sem repetição de linha entre páginas
- [ ] Testes unitários verificam o SQL gerado e os parâmetros para: nenhum filtro, cada filtro isolado e todos os oito combinados
- [ ] `npm run lint` e `npm run test` verdes

---

### P08M04: Aplicar SET LOCAL app.current_tenant_id por requisição

**Status:** 🚧 TODO
**ID:** P08M04

**Goal**

Garantir que toda consulta ao read model rode dentro de uma transação com `SET LOCAL app.current_tenant_id` definido a partir do contexto autenticado, ativando a RLS criada na Fase 1.

**Acceptance Criteria**

- [ ] Helper/`QueryRunner` dedicado abre transação, executa `SET LOCAL app.current_tenant_id` e só então roda a query do read model
- [ ] O valor vem do `AuthContextService` da Fase 4; requisição sem contexto autenticado não chega a executar query
- [ ] O `SET LOCAL` é liberado ao fim da transação, sem vazar entre requisições subsequentes na mesma conexão do pool — coberto por teste de integração com duas requisições sequenciais de tenants distintos
- [ ] Teste de integração prova que uma query executada sem o `SET LOCAL` não retorna linhas (RLS ativa, P0 — multi-tenant isolation)
- [ ] Erro ao aplicar o `SET LOCAL` resulta em falha técnica com 500 genérico, sem vazar detalhe de conexão
- [ ] Cobertura ≥ 90% no helper
- [ ] `npm run lint` e `npm run test` verdes

---

### P08M05: Resolver o escopo de tenant da consulta a partir de user.tenant_ids

**Status:** 🚧 TODO
**ID:** P08M05

**Goal**

Implementar a resolução do escopo de tenant da consulta: filtro `tenant_id` fora de `user.tenant_ids` retorna 403 e ausência de `tenant_id` restringe o resultado aos tenants autorizados.

**Acceptance Criteria**

- [ ] `TransactionScopeResolver` recebe o `tenant_id` opcional do DTO e o `tenant_ids` do `@CurrentUser()` e devolve a lista efetiva de tenants da query
- [ ] `tenant_id` informado e presente em `user.tenant_ids` resolve para lista de um elemento
- [ ] `tenant_id` informado e ausente de `user.tenant_ids` lança `DomainError` traduzido para 403, sem revelar se o tenant existe
- [ ] `tenant_id` ausente resolve para todos os tenants de `user.tenant_ids`
- [ ] `user.tenant_ids` vazio nunca resulta em consulta sem restrição — o caso é tratado como erro de contexto, não como acesso irrestrito
- [ ] Testes unitários cobrem os quatro cenários acima; cobertura ≥ 90% no resolver
- [ ] `npm run lint` e `npm run test` verdes

---

### P08M06: Criar a base do módulo de depósitos com entidade, interfaces e DTOs de resposta

**Status:** 🚧 TODO
**ID:** P08M06

**Goal**

Montar o esqueleto de `src/deposits/` seguindo o padrão Hexagonal Light da §9 do PRD: entidade `CashinTransaction`, interfaces `IDepositRepository`/`IDepositService` e DTOs de resposta de listagem e detalhe.

**Acceptance Criteria**

- [ ] `CashinTransaction` mapeia a tabela `cashin_transactions` do `backoffice-db` criada na Fase 1, sem redefinir schema
- [ ] `IDepositRepository` e `IDepositService` declaram as operações de listagem paginada e busca por id, em `src/deposits/interfaces/`
- [ ] `DepositsQueryDto` estende `TransactionQueryDto` sem adicionar filtro fora dos oito comuns
- [ ] `DepositListItemDto` e `DepositDetailDto` declaram explicitamente os campos expostos — nenhum campo da entidade é serializado por default
- [ ] Ambos os DTOs de resposta são documentados com decorators Swagger
- [ ] Mapper entidade → DTO coberto por teste unitário, incluindo campo nulo opcional
- [ ] `npm run lint`, `npm run build` e `npm run test` verdes

---
