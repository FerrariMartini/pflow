# Phase 1: Fundação — Scaffold, Persistência Dual, Migrations e Dev Seed

**Duration**: ~5 days (38 milestones @ 1h each)
**Dependencies**: None (foundation phase)
**Status**: 🚧 TODO

## Goal

Criar o serviço `payflow-backoffice-api` do zero (scaffold limpo, sem Palmtree) com o stack travado em `docs/technical/guidelines/coding-standards.md` — Node.js 24, NestJS 11, TypeScript 5.6 `strict`, ESLint 9 flat config, Prettier, Husky + commitlint, Jest + supertest — e entregar toda a base de dados e ambiente local funcionando ponta a ponta.

Ao fim desta fase qualquer desenvolvedor de outro microsserviço do Hub sobe a stack local e encontra `core-db`, `backoffice-db`, Redis e LocalStack populados com os dados fixos da §16 do PRD, sem inserção manual.

Entregas principais:
- Scaffold NestJS + toolchain de qualidade (lint, format, test, hooks de commit) e thresholds de cobertura configurados desde o primeiro commit (P1 do §14).
- Módulo de configuração com validação de ambiente via Zod (`config/`), incluindo as variáveis de tuning de retry Redis (`REDIS_PROPAGATION_*`).
- Logger Winston estruturado (JSON, `correlationId` obrigatório) e bootstrap do `dd-trace-js`, conforme `docs/technical/guidelines/logging.md` e `architecture/observability.md`.
- `docker-compose.yml` completo: `postgres-backoffice`, `postgres-core`, `redis`, `redpanda`, `localstack`, `mailhog` + `Dockerfile.dev`.
- DataSource primária (`backoffice-db`) e DataSource nomeada (`core`) via TypeORM, com `@InjectRepository(Entity, 'core')`.
- Migrations do `backoffice-db` (`cashin_transactions`, `cashout_transactions`, `circuit_breaker_events`, `transaction_audit_ledger`, `backoffice_users`, `backoffice_audit_log`) e do `core-db` (`organizations`, ALTER `tenants.organization_id`, `provider_configs`, `routing_configs`, `circuit_breaker_configs`, `tenant_limits`, `tenant_auth`, `redis_propagation_outbox`).
- RLS habilitada em todas as tabelas do `backoffice-db` com policy por `app.current_tenant_id` (P0 — multi-tenant isolation).
- Módulos de conexão Redis Core (`REDIS_URL`) e Valkey Auth (`REDIS_AUTH_URL`) atrás de `ICacheService`.
- Dev seed completo (PRD §16, obrigatório nesta fase): `seed:db` (core-db + admin do backoffice-db), `seed:redis`, `seed:secrets` (LocalStack) e o agregador `seed:all`, todos com os UUIDs fixos e versionados.
- `GET /api/health` verificando `backoffice-db`, `core-db` e Redis.
- ADR registrando a introdução de `organizations` no `core-db` e a abordagem de DataSource dupla.

## Phase Acceptance Criteria

- `scripts/pre-commit.sh` executa e passa nos quatro gates do serviço (`lint`, `build`, `test`, `test:e2e`) a partir de um checkout limpo, sem estado local.
- `docker compose up -d` sobe os seis serviços de infraestrutura e todos ficam healthy; `npm run migration:run && npm run seed:all` popula `core-db`, `backoffice-db`, Redis e Secrets Manager de forma idempotente (rodar duas vezes não duplica nem falha).
- As chaves Redis `tenant:config:*`, `tenant:limits:*`, `tenant:providers:*`, `routing:weights:*:CASHIN|CASHOUT` e `auth:token:{hash}` (TTL 300s) existem exatamente com os valores da §16.3 após `seed:redis`, verificado por teste de integração.
- Os quatro secrets da §16.4 existem no LocalStack após `seed:secrets`, verificados por consulta via SDK no teste.
- RLS está habilitada em todas as tabelas do `backoffice-db` e um teste de integração prova que uma query sem `SET LOCAL app.current_tenant_id` não retorna linhas de outro tenant.
- Jest está configurado com thresholds que falham o build abaixo de 90% global e 85% em controllers; `npm run test:cov` roda verde.
- ESLint 9 flat config aplica exatamente as regras da guideline (`no-explicit-any: warn`, `no-console: warn`, `no-unused-vars: error` com `argsIgnorePattern: '^_'`, `prefer-const`/`no-var`/`object-shorthand`/`prefer-arrow-callback: error`) e Husky bloqueia commit fora do padrão Conventional Commits.
- `GET /api/health` responde 200 em < 100ms com o status de `backoffice-db`, `core-db` e Redis discriminado por dependência.
- Todo log emitido no boot é JSON estruturado com `service`, `level`, `timestamp` e `correlationId`; nenhum `console.log` no código de produção.
- ADR de `organizations` no `core-db` + DataSource dupla criado em `docs/decisions/` antes do merge da fase.

## Milestones

<!-- Milestones appended by /wiz-milestones -->

### P01M01: Criar scaffold NestJS 11 do serviço

**Status:** ✅ COMPLETE
**ID:** P01M01

**Goal**

Criar do zero o esqueleto do `services/payflow-backoffice-api` com NestJS 11 sobre Node.js 24, incluindo `package.json`, `nest-cli.json`, bootstrap mínimo e os scripts npm que os demais milestones vão usar.

**Acceptance Criteria**

- [x] `services/payflow-backoffice-api/package.json` declara `engines.node: ">=24"`, `@nestjs/core`, `@nestjs/common`, `@nestjs/platform-express` na major 11 e `reflect-metadata`
- [x] Scripts npm criados: `build`, `start`, `start:dev`, `start:prod`, `lint`, `format`, `test`, `test:cov`, `test:e2e`
- [x] `src/main.ts` faz bootstrap com prefixo global `/api` e porta lida de `PORT` (default `3001`)
- [x] `src/app.module.ts` existe como root module vazio e compila
- [x] `nest-cli.json`, `.nvmrc` (24) e `.gitignore` (node_modules, dist, coverage, .env) criados
- [x] `npm install && npm run start:dev` sobe a aplicação na porta 3001 sem erro

---

### P01M02: Configurar TypeScript 5.6 em modo strict

**Status:** 🚧 TODO
**ID:** P01M02

**Goal**

Configurar o compilador TypeScript 5.6 com `strict: true` e as opções de build exigidas por `docs/technical/guidelines/coding-standards.md`, garantindo que o serviço compile limpo desde o primeiro commit.

**Acceptance Criteria**

- [ ] `tsconfig.json` com `strict: true`, `strictNullChecks`, `noImplicitAny`, `noImplicitOverride`, `forceConsistentCasingInFileNames`, `experimentalDecorators` e `emitDecoratorMetadata` habilitados
- [ ] `target` e `module` compatíveis com Node.js 24 (`ES2023` ou superior) e `moduleResolution: node`
- [ ] `tsconfig.build.json` exclui `test`, `**/*.spec.ts` e `dist` do build de produção
- [ ] Path alias configurado para `src/` e resolvido tanto no build quanto no Jest
- [ ] `npm run build` gera `dist/` sem nenhum erro ou warning de tipo

---

### P01M03: Configurar ESLint 9 flat config e Prettier

**Status:** 🚧 TODO
**ID:** P01M03

**Goal**

Aplicar exatamente as regras de lint e format definidas em `docs/technical/guidelines/coding-standards.md`, sem regras extras nem regras faltando.

**Acceptance Criteria**

- [ ] `eslint.config.mjs` (flat config) usa `typescript-eslint` 8 com type-aware linting apontando para `tsconfig.json`
- [ ] Regras exatas configuradas: `@typescript-eslint/no-explicit-any: warn`, `@typescript-eslint/explicit-function-return-type: off`, `@typescript-eslint/explicit-module-boundary-types: off`, `@typescript-eslint/no-unused-vars: error` com `argsIgnorePattern: '^_'`, `no-console: warn`, `prefer-const`/`no-var`/`object-shorthand`/`prefer-arrow-callback: error`
- [ ] `.prettierrc` define `singleQuote: true`, `trailingComma: "all"`, `semi: true`, `printWidth: 100`, `tabWidth: 2`
- [ ] ESLint e Prettier não conflitam (`eslint-config-prettier` aplicado por último na cadeia)
- [ ] `npm run lint` e `npm run format:check` passam verde no código existente
- [ ] Verificado que um arquivo temporário com `var x = 1` faz `npm run lint` sair com código diferente de zero, e o arquivo é removido em seguida

---

### P01M04: Configurar Husky, commitlint e lint-staged

**Status:** 🚧 TODO
**ID:** P01M04

**Goal**

Enforçar Conventional Commits no momento do commit e rodar lint/format apenas nos arquivos staged, conforme o gate P1 do §14 do PRD.

**Acceptance Criteria**

- [ ] `husky` instalado com hook `commit-msg` executando `commitlint --edit`
- [ ] `commitlint.config.js` estende `@commitlint/config-conventional` e exige escopo entre parênteses referenciando o serviço
- [ ] Hook `pre-commit` executa `lint-staged` com `eslint --fix` e `prettier --write` em `*.ts`
- [ ] Verificado que a mensagem `atualiza coisas` é rejeitada e `feat(backoffice-api): add scaffold` é aceita
- [ ] Instruções de ativação dos hooks documentadas no README do serviço

---

### P01M05: Configurar Jest com thresholds de cobertura que falham o build

**Status:** 🚧 TODO
**ID:** P01M05

**Goal**

Configurar a suíte de testes unitários com Jest e travar os thresholds de cobertura do §13 do PRD de forma que o build falhe abaixo do mínimo, desde o primeiro commit.

**Acceptance Criteria**

- [ ] Jest configurado com `ts-jest`, `rootDir: src`, `testRegex: .*\.spec\.ts$` e resolução dos path aliases do `tsconfig.json`
- [ ] `coverageThreshold.global` exige 90% em `branches`, `functions`, `lines` e `statements`
- [ ] Thresholds por glob configurados: `**/*.service.ts` 90%, `**/*.repository.ts` 90%, `**/*.controller.ts` 85%
- [ ] `collectCoverageFrom` exclui `*.module.ts`, `*.dto.ts`, `*.entity.ts`, `main.ts` e migrations
- [ ] `npm run test` e `npm run test:cov` rodam verde com pelo menos um teste real
- [ ] Verificado que reduzir artificialmente a cobertura faz `npm run test:cov` sair com código diferente de zero

---

### P01M06: Configurar suíte e2e com supertest

**Status:** 🚧 TODO
**ID:** P01M06

**Goal**

Criar a infraestrutura de testes end-to-end com Jest + supertest, isolada da suíte unitária, para que endpoints possam ser validados via HTTP real a partir da Phase 1.

**Acceptance Criteria**

- [ ] `test/jest-e2e.json` configurado com `rootDir` na raiz do serviço e `testRegex: .e2e-spec.ts$`
- [ ] Script `test:e2e` executa a suíte e2e sem colidir com a suíte unitária
- [ ] Helper de bootstrap cria a aplicação Nest de teste aplicando os mesmos pipes e prefixo `/api` do `main.ts`
- [ ] Primeiro `app.e2e-spec.ts` sobe a aplicação e valida uma resposta HTTP com supertest
- [ ] `npm run test:e2e` passa verde e encerra o processo sem handles pendentes

---

### P01M07: Criar a estrutura de diretórios de `src/` e o README do serviço

**Status:** 🚧 TODO
**ID:** P01M07

**Goal**

Materializar a árvore de diretórios definida no §9 do PRD e documentar o padrão de módulo (Hexagonal Light + interfaces SOLID) que todos os módulos das fases seguintes vão seguir.

**Acceptance Criteria**

- [ ] Criados `src/common/{decorators,guards,interceptors,filters,interfaces,dto,entities,services}`, `src/config/` e `src/infrastructure/{database,cache,kafka,secrets,observability}`
- [ ] `services/payflow-backoffice-api/README.md` descreve a estrutura, o padrão `interfaces/controllers/services/repositories/entities/dto` e a regra de injeção por token de interface
- [ ] README aponta para `docs/technical/guidelines/` como fonte de verdade, sem duplicar convenção
- [ ] `.env.example` criado com todas as variáveis do §12 do PRD e sem nenhum valor real de segredo
- [ ] `npm run lint` e `npm run build` continuam verdes com a nova estrutura

---
### P01M08: Implementar validação de ambiente com Zod

**Status:** 🚧 TODO
**ID:** P01M08

**Goal**

Criar o módulo `src/config/` com schema Zod que valida todas as variáveis de ambiente no boot e falha rápido com mensagem agregada, expondo um serviço de configuração tipado para o resto da aplicação.

**Acceptance Criteria**

- [ ] `src/config/env.schema.ts` valida com Zod `NODE_ENV`, `PORT`, `DATABASE_URL`, `CORE_DATABASE_URL`, `REDIS_URL`, `REDIS_AUTH_URL`, `REDIS_PUBSUB_URL`, `KAFKA_BROKERS`, `JWT_SECRET`, `FRONTEND_URL`, `AWS_REGION`, `AWS_ENDPOINT_URL`, `SMTP_HOST` e `SMTP_PORT`
- [ ] Tipos numéricos usam coerção e limites (`PORT` e `SMTP_PORT` inteiros entre 1 e 65535); URLs de banco e Redis validadas por formato
- [ ] `ConfigModule` global expõe `AppConfigService` com getters tipados derivados do schema, sem `process.env` espalhado pelo código
- [ ] Boot com variável obrigatória ausente ou inválida aborta o processo listando **todas** as falhas de uma vez, não apenas a primeira
- [ ] Nenhum valor de segredo é impresso na mensagem de erro de validação
- [ ] Testes unitários cobrem schema válido, variável ausente, valor fora do range e agregação de múltiplas falhas

---

### P01M09: Adicionar as variáveis de tuning de retry Redis ao schema de configuração

**Status:** 🚧 TODO
**ID:** P01M09

**Goal**

Incluir no schema Zod as variáveis de tuning do retry de propagação Redis descritas no §11.1 do PRD, com defaults seguros, para que a Phase de propagação de configuração já as encontre disponíveis.

**Acceptance Criteria**

- [ ] `REDIS_PROPAGATION_MAX_RETRIES`, `REDIS_PROPAGATION_BASE_DELAY_MS` e `REDIS_PROPAGATION_MAX_DELAY_MS` validadas como inteiros positivos com defaults documentados
- [ ] Schema rejeita `REDIS_PROPAGATION_MAX_DELAY_MS` menor que `REDIS_PROPAGATION_BASE_DELAY_MS`
- [ ] `AppConfigService` expõe um objeto agrupado `redisPropagation` com os três valores tipados
- [ ] As três variáveis constam de `.env.example` e do bloco de environment do `backoffice-api` no `docker-compose.yml`
- [ ] Testes unitários cobrem aplicação dos defaults, valor customizado válido e rejeição da combinação inconsistente

---

### P01M10: Implementar o logger estruturado com Winston

**Status:** 🚧 TODO
**ID:** P01M10

**Goal**

Configurar Winston como logger da aplicação emitindo JSON de uma linha com os campos obrigatórios de `docs/technical/guidelines/logging.md`, substituindo o logger padrão do NestJS.

**Acceptance Criteria**

- [ ] `src/infrastructure/observability/` contém a configuração Winston com formato JSON e os campos `timestamp`, `level`, `service`, `correlationId` e `message`
- [ ] `service` é fixado como `payflow-backoffice-api` em todos os registros
- [ ] Interface `ILogger` declarada em `src/common/interfaces/` e provida por token de DI; nenhum consumidor importa Winston diretamente
- [ ] Logger substitui o padrão do Nest no bootstrap (`app.useLogger`), inclusive nos logs de inicialização do framework
- [ ] Nível de log lido da configuração, com `debug` desligado por padrão fora de desenvolvimento
- [ ] Testes unitários validam que a saída é JSON parseável de uma linha e contém os campos obrigatórios em `info`, `warn` e `error`

---

### P01M11: Propagar `correlationId` em todo o ciclo de requisição

**Status:** 🚧 TODO
**ID:** P01M11

**Goal**

Garantir que todo log emitido dentro de uma requisição carregue automaticamente o `correlationId`, usando `AsyncLocalStorage` alimentado por middleware, conforme a regra de obrigatoriedade da guideline de logging.

**Acceptance Criteria**

- [ ] Middleware lê o header `x-correlation-id` da requisição ou gera um UUID v4 quando ausente
- [ ] `AsyncLocalStorage` mantém o `correlationId` acessível ao logger sem precisar passá-lo por parâmetro
- [ ] Resposta HTTP devolve o header `x-correlation-id` com o valor usado
- [ ] `LoggingInterceptor` registra início e fim de cada requisição com método, rota, status e duração em ms
- [ ] Testes unitários cobrem header presente, header ausente e isolamento entre contextos concorrentes
- [ ] Teste e2e confirma que o header volta na resposta e que o log emitido durante a requisição contém o mesmo `correlationId`

---

### P01M12: Configurar o bootstrap do dd-trace-js

**Status:** 🚧 TODO
**ID:** P01M12

**Goal**

Inicializar o APM DataDog antes de qualquer outro import da aplicação e correlacionar traces com os logs Winston, conforme `docs/technical/architecture/observability.md`.

**Acceptance Criteria**

- [ ] `src/tracer.ts` inicializa `dd-trace` e é o **primeiro** import de `src/main.ts`, antes de NestJS
- [ ] Tracing é ligado ou desligado por variável de ambiente validada no schema Zod (`DD_TRACE_ENABLED`, `DD_SERVICE`, `DD_ENV`, `DD_VERSION`)
- [ ] `logInjection` habilitado, de modo que `trace_id` e `span_id` apareçam nos logs Winston quando o tracing está ativo
- [ ] Com tracing desabilitado a aplicação sobe normalmente e nenhum erro é emitido
- [ ] Pino e Prometheus não constam de `package.json` (removidos do boilerplate por decisão do §7 do PRD)
- [ ] Teste automatizado confirma que o boot é bem-sucedido nas duas configurações (tracing ligado e desligado)

---

### P01M13: Criar o docker-compose com os dois PostgreSQL e o Redis

**Status:** 🚧 TODO
**ID:** P01M13

**Goal**

Subir a base de dados local do serviço: `postgres-backoffice`, `postgres-core` e `redis`, com healthchecks e volumes nomeados, conforme o §12 do PRD.

**Acceptance Criteria**

- [ ] `docker-compose.yml` define `postgres-backoffice` (`postgres:16-alpine`, db/user/password `backoffice`, porta `5432:5432`) e `postgres-core` (`postgres:16-alpine`, db/user/password `core`, porta `5433:5432`)
- [ ] `redis` (`redis:7-alpine`) exposto em `6379:6379`
- [ ] Healthcheck `pg_isready` nos dois Postgres e `redis-cli ping` no Redis, com `interval`, `timeout` e `retries` definidos
- [ ] Volumes nomeados persistem os dados entre `docker compose down` e `up`
- [ ] `docker compose up -d` deixa os três serviços em estado `healthy`
- [ ] Portas e credenciais de dev registradas no README do serviço, batendo com a tabela do §16.5 do PRD

---

### P01M14: Adicionar Redpanda, LocalStack e MailHog ao docker-compose

**Status:** 🚧 TODO
**ID:** P01M14

**Goal**

Completar a stack local com o broker Kafka-compatível, o emulador de Secrets Manager e o servidor SMTP de inspeção de emails 2FA, fechando os seis serviços de infraestrutura da fase.

**Acceptance Criteria**

- [ ] `redpanda` (`redpandadata/redpanda`) sobe com `redpanda start --smp 1 --memory 512M --overprovisioned` e expõe `9092`, `8081`, `8082` e `9644`
- [ ] `localstack` sobe com `SERVICES: secretsmanager` e `DEFAULT_REGION: sa-east-1` na porta `4566`
- [ ] `mailhog` expõe `1025` (SMTP) e `8025` (UI web)
- [ ] Healthcheck definido para os três serviços (admin API do Redpanda, `_localstack/health`, porta HTTP do MailHog)
- [ ] `docker compose up -d` deixa os **seis** serviços de infraestrutura em estado `healthy`
- [ ] UI do MailHog acessível em `http://localhost:8025` e endpoint do LocalStack respondendo em `http://localhost:4566`

---
### P01M15: Criar o Dockerfile.dev e o serviço backoffice-api no compose

**Status:** 🚧 TODO
**ID:** P01M15

**Goal**

Containerizar a aplicação para desenvolvimento com hot reload e amarrá-la aos seis serviços de infraestrutura, com o bloco de environment exatamente como especificado no §12 do PRD.

**Acceptance Criteria**

- [ ] `Dockerfile.dev` parte de `node:24-alpine`, instala dependências em camada separada do código-fonte e roda `start:dev` com hot reload por volume montado
- [ ] Container executa como usuário não-root
- [ ] Serviço `backoffice-api` no compose expõe `3001:3001` e declara `depends_on` com `condition: service_healthy` para os seis serviços de infraestrutura
- [ ] Bloco `environment` contém as variáveis do §12 apontando para os hostnames internos do compose (`postgres-backoffice`, `postgres-core`, `redis`, `redpanda`, `localstack`, `mailhog`)
- [ ] `.dockerignore` exclui `node_modules`, `dist`, `coverage` e `.env`
- [ ] `docker compose up -d` sobe a aplicação containerizada, que responde HTTP na porta 3001

---

### P01M16: Configurar a DataSource primária `backoffice-db` com TypeORM

**Status:** 🚧 TODO
**ID:** P01M16

**Goal**

Conectar a aplicação ao `backoffice-db` via `TypeOrmModule.forRootAsync()` alimentado pela configuração validada, e habilitar a CLI de migrations dessa conexão.

**Acceptance Criteria**

- [ ] `src/infrastructure/database/` registra a DataSource primária lendo `DATABASE_URL` do `AppConfigService`
- [ ] `synchronize: false` e `migrationsRun: false` em todos os ambientes, sem exceção
- [ ] Arquivo standalone de DataSource exportado para a CLI do TypeORM, com `entities` e `migrations` apontando para os diretórios do `backoffice-db`
- [ ] Scripts `migration:generate`, `migration:run` e `migration:revert` funcionam contra o `postgres-backoffice` do compose
- [ ] Pool de conexões e timeout configurados por variável de ambiente, com defaults documentados
- [ ] Teste de integração conecta na DataSource, executa `SELECT 1` e encerra a conexão sem handles pendentes

---

### P01M17: Configurar a DataSource nomeada `core` com TypeORM

**Status:** 🚧 TODO
**ID:** P01M17

**Goal**

Adicionar a segunda conexão TypeORM para o `core-db` como named connection `core`, permitindo `@InjectRepository(Entity, 'core')` conforme o §7 do PRD, sem interferir na DataSource primária.

**Acceptance Criteria**

- [ ] `TypeOrmModule.forRootAsync({ name: 'core' })` registrado lendo `CORE_DATABASE_URL`, com `synchronize: false`
- [ ] Diretórios de entities e migrations do `core-db` separados dos do `backoffice-db`, sem sobreposição de globs
- [ ] Arquivo standalone de DataSource `core` e scripts `migration:core:generate`, `migration:core:run` e `migration:core:revert`
- [ ] Documentado no README que o `core-db` é fonte de verdade de configuração e que o backoffice escreve nele com escopo restrito às tabelas do §7
- [ ] Teste de integração prova que as duas conexões coexistem no mesmo contexto Nest e que `@InjectRepository(Entity, 'core')` resolve o repositório na conexão certa
- [ ] Ambas as conexões fecham corretamente no `onApplicationShutdown`

---

### P01M18: Criar a entidade base e as convenções de migration

**Status:** 🚧 TODO
**ID:** P01M18

**Goal**

Padronizar colunas comuns, nomenclatura e organização das migrations antes de escrever a primeira, evitando divergência entre os dois bancos.

**Acceptance Criteria**

- [ ] `src/common/entities/base.entity.ts` define `id` (UUID), `created_at`, `updated_at`, `deleted_at` e `deleted_by`, alinhado ao soft delete exigido no §10 do PRD
- [ ] Naming strategy snake_case aplicada às duas DataSources, garantindo colunas e índices em snake_case
- [ ] Estrutura `migrations/backoffice/` e `migrations/core/` criada com convenção de nome `<timestamp>-<descricao-kebab>.ts` documentada no README
- [ ] Toda migration implementa `up` e `down`; o `down` reverte integralmente o `up`
- [ ] Extensão `uuid-ossp` habilitada por migration inicial no `backoffice-db`
- [ ] Teste unitário confirma que a naming strategy converte um nome de propriedade camelCase para snake_case

---

### P01M19: Criar as migrations de `cashin_transactions` e `cashout_transactions`

**Status:** 🚧 TODO
**ID:** P01M19

**Goal**

Criar no `backoffice-db` as duas tabelas de projeção do read model que os consumers Kafka da Phase de projeções vão alimentar, com os índices que sustentam os filtros do §8 do PRD.

**Acceptance Criteria**

- [ ] `cashin_transactions` criada com `tenant_id`, `provider_id`, `status`, `amount`, `document_number`, `merchant_transaction_id`, `payer_id`, timestamps e as colunas da entidade base
- [ ] `cashout_transactions` criada com o mesmo conjunto de colunas de filtro, incluindo os estados de reversão previstos nos tópicos `transaction.cashout.*.v1`
- [ ] Índices criados para os filtros do §8: `tenant_id`, `status`, `provider_id`, `created_at`, `document_number` e `merchant_transaction_id`
- [ ] Constraint de unicidade que garante idempotência do consumer (reprocessar o mesmo offset não duplica linha), atendendo ao P0 do §14
- [ ] `npm run migration:run` aplica e `npm run migration:revert` desfaz as duas migrations sem erro
- [ ] Teste de integração confirma a existência das tabelas, das colunas e dos índices após o `migration:run`

---

### P01M20: Criar as migrations de `circuit_breaker_events` e `transaction_audit_ledger`

**Status:** 🚧 TODO
**ID:** P01M20

**Goal**

Criar no `backoffice-db` a tabela de histórico de kicks e recoveries do circuit breaker e o ledger cronológico append-only escrito pelo `audit-worker`.

**Acceptance Criteria**

- [ ] `circuit_breaker_events` criada com `tenant_id`, `provider_id`, `flow_type`, tipo do evento (kick/recovery), motivo, origem (manual/automático) e `occurred_at`, com índice por `tenant_id` e `occurred_at`
- [ ] `transaction_audit_ledger` criada com `tenant_id`, referência à transação, direção (cashin/cashout), tipo de evento, payload e `occurred_at`, indexada para busca cronológica por transação
- [ ] `transaction_audit_ledger` é append-only: sem coluna de atualização e com a restrição de escrita documentada na migration
- [ ] `flow_type` restrito a `CASHIN` e `CASHOUT` por constraint de banco
- [ ] `migration:run` e `migration:revert` executam sem erro
- [ ] Teste de integração valida a criação das tabelas e a rejeição de um `flow_type` inválido

---

### P01M21: Criar a migration de `backoffice_users`

**Status:** 🚧 TODO
**ID:** P01M21

**Goal**

Criar a tabela de usuários internos do backoffice com o modelo de RBAC e de escopo por Organization descrito no §10 do PRD.

**Acceptance Criteria**

- [ ] `backoffice_users` criada com `id`, `organization_id` NOT NULL, `email` UNIQUE, `name`, `role`, `tenant_ids` (array de UUID, default `{}`), `active`, `password_hash`, `two_factor_enabled` e as colunas de soft delete da entidade base
- [ ] `role` restrito por constraint aos perfis do §6 do PRD
- [ ] Índices em `organization_id` e em `email` (case-insensitive) criados
- [ ] Semântica de `tenant_ids` documentada na migration: vazio significa todos os tenants ativos da Organization; preenchido significa apenas os listados
- [ ] `password_hash` nunca aceita valor nulo e a coluna não é exposta em nenhum default de select
- [ ] Teste de integração valida a criação da tabela, a unicidade de `email` e a rejeição de um `role` fora da lista permitida

---
