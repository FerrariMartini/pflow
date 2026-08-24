# Phase 6: BaaS Providers — CRUD, Credenciais no Secrets Manager e Rotação

**Duration**: ~4 days (28 milestones @ 1h each)
**Dependencies**: Phase 5
**Status**: 🚧 TODO

## Goal

Entregar a gestão de provedores BaaS por tenant com credenciais vivendo exclusivamente no AWS Secrets Manager (LocalStack em dev), respeitando o split de IAM: o `backoffice-api` só escreve (`CreateSecret`, `PutSecretValue`) e o core só lê (`GetSecretValue`).

Entregas principais:
- `infrastructure/secrets/` com `ISecretsService` e `SecretsManagerService`, path `payflow/{env}/tenants/{tenant_id}/providers/{provider_code}`.
- `GET /api/tenants/:tid/providers` e `GET /api/tenants/:tid/providers/:pid` (ADMIN, OPERATIONS) — nunca retornam credencial, apenas metadados e máscara.
- `POST /api/tenants/:tid/providers` (ADMIN): cadastra em `provider_configs` e grava as credenciais no Secrets Manager.
- `PUT /api/tenants/:tid/providers/:pid` (metadados) e `PUT /api/tenants/:tid/providers/:pid/credentials` (rotação — novo secret version).
- `DELETE /api/tenants/:tid/providers/:pid` (soft delete) e `POST /api/tenants/:tid/providers/:pid/test-connection`.
- Cache do ARN em `provider:credentials:arn:{tid}:{code}` no Valkey Auth (TTL 5min) — apenas o ARN, nunca o segredo.
- `POST /api/tenants/:tid/providers/resync-redis` reconstruindo a chave `tenant:providers:{tenant_id}` no Redis Core, reusando o serviço de propagação da Fase 5 (contrato forte na criação, outbox no update/delete).

## Phase Acceptance Criteria

- Nenhuma credencial de provider é persistida em banco, cache ou log — teste de integração inspeciona `provider_configs`, o Valkey Auth e o transporte de log após criação e rotação, provando que só o ARN é cacheado.
- `GET` de detalhe retorna credenciais mascaradas e o teste e2e confirma que nenhum campo em claro atravessa a resposta, para ADMIN e para OPERATIONS.
- Rotação de credenciais cria uma nova versão no Secrets Manager sem invalidar a leitura do core durante a operação, e gera registro `CREDENTIALS_ROTATE` em `backoffice_audit_log` — coberto por teste contra LocalStack.
- Criação de provider com falha de Redis faz rollback (contrato forte da §11.1); update/delete com falha de Redis cai no `redis_propagation_outbox` — dois testes distintos.
- `test-connection` trata timeout, credencial inválida e provider indisponível como `DomainError` tipados distintos, cada um com teste, e nunca vaza a resposta bruta do provedor.
- `POST /api/tenants/:tid/providers/resync-redis` reconstrói `tenant:providers:{tenant_id}` idêntica ao formato da §16.3, verificado por teste de integração.
- RBAC conforme a matriz: escrita ADMIN-only, leitura ADMIN+OPERATIONS — negativos cobertos.
- Cobertura ≥ 90% em `ProviderService` e `SecretsManagerService`; `scripts/pre-commit.sh` verde e `docs/contract/contract.md` atualizado no mesmo PR.

## Milestones

<!-- Milestones appended by /wiz-milestones -->

### P06M01: Definir `ISecretsService` e o resolvedor de path de secrets

**Status:** 🚧 TODO
**ID:** P06M01

**Goal**

Criar em `src/infrastructure/secrets/` a interface `ISecretsService` (token de injeção) e o helper que monta o path canônico `payflow/{env}/tenants/{tenant_id}/providers/{provider_code}`, sem nenhuma dependência do SDK da AWS.

**Acceptance Criteria**

- [ ] `src/infrastructure/secrets/interfaces/secrets-service.interface.ts` declara `ISecretsService` com `createProviderSecret`, `rotateProviderSecret` e `resolveSecretArn`, todos tipados sem `any`
- [ ] A interface expõe apenas operações de escrita e de resolução de ARN — nenhum método de leitura de valor de secret existe no contrato
- [ ] Helper `buildProviderSecretName(env, tenantId, providerCode)` produz exatamente `payflow/{env}/tenants/{tenant_id}/providers/{provider_code}`
- [ ] O helper normaliza `provider_code` para minúsculo e rejeita valor fora de `^[a-z0-9-]{2,40}$` com `DomainError` tipado
- [ ] Teste unitário cobre path válido, normalização de caixa e os casos de `provider_code` inválido
- [ ] `npm run lint` e `npm run build` passam

---

### P06M02: Implementar `SecretsManagerService` com AWS SDK v3 e criação de secret

**Status:** 🚧 TODO
**ID:** P06M02

**Goal**

Implementar `SecretsManagerService` sobre `@aws-sdk/client-secrets-manager` (v3), com client configurável por endpoint (LocalStack em dev) e a operação `createProviderSecret` usando `CreateSecretCommand`.

**Acceptance Criteria**

- [ ] `SecretsManagerService` implementa `ISecretsService` e recebe o client do SDK v3 por injeção, sem instanciá-lo internamente
- [ ] `createProviderSecret` emite `CreateSecretCommand` com o nome resolvido pelo helper do P06M01 e `SecretString` contendo o JSON das credenciais
- [ ] O método retorna apenas `{ arn, versionId }` — o valor das credenciais nunca é devolvido nem retido em campo de instância
- [ ] O client é criado a partir de `AWS_REGION` e do endpoint opcional (`AWS_ENDPOINT_URL`) validados no módulo de config com Zod
- [ ] Nenhum log emitido pelo service contém `SecretString`, chave ou valor de credencial
- [ ] Teste unitário com o client mockado cobre sucesso e propagação de erro do SDK
- [ ] `npm run lint` e `npm run build` passam

---

### P06M03: Implementar rotação via `PutSecretValue` e mapear erros da AWS em `DomainError`

**Status:** 🚧 TODO
**ID:** P06M03

**Goal**

Adicionar `rotateProviderSecret` usando `PutSecretValueCommand` (nova versão do secret existente) e traduzir as falhas do SDK em `DomainError` tipados da hierarquia da Phase 2.

**Acceptance Criteria**

- [ ] `rotateProviderSecret` cria uma nova versão do secret existente sem apagar nem sobrescrever versões anteriores
- [ ] `ResourceNotFoundException` do SDK vira `ProviderSecretNotFoundError`, com `code` estável e mapeamento para 404
- [ ] `ResourceExistsException` na criação vira `ProviderSecretAlreadyExistsError` (409) em vez de estourar erro técnico
- [ ] Erros de credencial/permissão da AWS (`AccessDeniedException`) viram falha técnica com 500 genérico, sem expor a mensagem original na resposta
- [ ] A mensagem original da AWS é registrada apenas no log interno, sem qualquer trecho de `SecretString`
- [ ] Testes unitários cobrem os quatro mapeamentos de erro acima
- [ ] `npm run lint` e `npm run build` passam

---

### P06M04: Criar `SecretsModule` com wiring por token e documentar o split de IAM write-only

**Status:** 🚧 TODO
**ID:** P06M04

**Goal**

Empacotar a infraestrutura de secrets em um módulo NestJS que provê `ISecretsService` por token de interface, e registrar no README do serviço a política de IAM write-only do `backoffice-api`.

**Acceptance Criteria**

- [ ] `SecretsModule` provê `{ provide: 'ISecretsService', useClass: SecretsManagerService }` e exporta apenas o token, nunca a classe concreta
- [ ] O client do SDK v3 é registrado como provider próprio, permitindo substituição por fake nos testes
- [ ] As variáveis `AWS_REGION`, `AWS_ENDPOINT_URL` e `SECRETS_ENV_PREFIX` estão no schema Zod de config, com falha de boot se ausentes fora de dev
- [ ] README do serviço documenta que o `backoffice-api` usa IAM write-only (`CreateSecret`, `PutSecretValue`) e que `GetSecretValue` é exclusivo do core
- [ ] Teste de integração prova que o service não expõe nenhum caminho de código que chame `GetSecretValueCommand`
- [ ] `npm run lint`, `npm run build` e `npm test` passam

---

### P06M05: Cachear o ARN do secret no Valkey Auth com TTL de 5 minutos

**Status:** 🚧 TODO
**ID:** P06M05

**Goal**

Implementar `resolveSecretArn` com cache em `provider:credentials:arn:{tid}:{code}` no Valkey Auth (TTL 300s), armazenando exclusivamente o ARN.

**Acceptance Criteria**

- [ ] `resolveSecretArn(tenantId, providerCode)` consulta a chave `provider:credentials:arn:{tid}:{code}` antes de qualquer chamada à AWS
- [ ] O valor cacheado é somente a string do ARN — nenhum campo de credencial, versão de secret ou payload é gravado
- [ ] A chave é escrita com TTL de 300 segundos via `ICacheService` do Valkey Auth (`REDIS_AUTH_URL`), nunca no Redis Core
- [ ] Criação e rotação de credenciais atualizam a chave com o ARN resultante
- [ ] Falha do Valkey no caminho de cache não derruba a operação: o ARN é resolvido diretamente e a falha vira log estruturado de warning
- [ ] Teste de integração contra o Valkey do compose confirma o conteúdo da chave, o TTL e que nenhum outro campo foi persistido
- [ ] `npm run lint`, `npm run build` e `npm test` passam

---

### P06M06: Testar `SecretsManagerService` de ponta a ponta contra o LocalStack

**Status:** 🚧 TODO
**ID:** P06M06

**Goal**

Escrever a suíte de integração do `SecretsManagerService` contra o LocalStack do `docker-compose.yml`, cobrindo criação, rotação e versionamento reais.

**Acceptance Criteria**

- [ ] Teste cria um secret no path `payflow/{env}/tenants/{tenant_id}/providers/{provider_code}` e confirma o ARN retornado
- [ ] Teste de rotação confirma que uma nova versão foi criada e que a versão anterior continua existindo no LocalStack
- [ ] Teste confirma que recriar o mesmo path retorna `ProviderSecretAlreadyExistsError`, não erro técnico
- [ ] A suíte limpa os secrets criados ao final, permitindo reexecução idempotente
- [ ] A suíte roda dentro de `npm run test:e2e` sem exigir passo manual além de `docker compose up -d`
- [ ] `scripts/pre-commit.sh` passa

---
### P06M07: Modelar a entidade `ProviderConfig` na DataSource `core`

**Status:** 🚧 TODO
**ID:** P06M07

**Goal**

Criar a entidade TypeORM `ProviderConfig` mapeando `provider_configs` do `core-db`, com os campos de metadados, soft delete e o hint de credencial — nunca a credencial em si.

**Acceptance Criteria**

- [ ] `src/providers/entities/provider-config.entity.ts` mapeia `provider_configs` na DataSource nomeada `core`
- [ ] Campos mapeados: `id`, `tenant_id`, `provider_id`, `base_url`, `active`, `created_at`, `updated_at`, `deleted_at`, `deleted_by`
- [ ] Campos de credencial (`api_key`, `api_secret`, `client_id` ou equivalentes) não existem na entidade nem na tabela
- [ ] Há apenas `secret_arn` e `credentials_hint` como referência ao Secrets Manager, ambos sem valor sensível
- [ ] Migration do `core-db` adiciona `secret_arn`, `credentials_hint`, `deleted_at` e `deleted_by` caso ainda não existam, de forma idempotente
- [ ] Teste de integração confirma que a entidade carrega uma linha semeada pela §16.1 do PRD
- [ ] `npm run lint` e `npm run build` passam

---

### P06M08: Implementar `IProviderRepository` e `ProviderConfigRepository` no `core-db`

**Status:** 🚧 TODO
**ID:** P06M08

**Goal**

Criar o repositório de `provider_configs` sobre a DataSource `core`, com filtro explícito por organization e exclusão de registros soft-deleted.

**Acceptance Criteria**

- [ ] `IProviderRepository` declara `findByTenant`, `findById`, `create`, `update`, `softDelete` e `findActiveByTenantForRedis`
- [ ] `ProviderConfigRepository` usa `@InjectRepository(ProviderConfig, 'core')` conforme o padrão da Phase 1
- [ ] Toda query por tenant aplica join/filtro explícito `WHERE organization_id = $1` no `core-db`, conforme §10 do PRD
- [ ] Registros com `deleted_at` preenchido não retornam em `findByTenant` nem em `findById`
- [ ] `softDelete` grava `deleted_at` e `deleted_by` em vez de remover a linha
- [ ] Testes de integração contra o `core-db` do compose cobrem os seis métodos, incluindo o caso de provider de outra organization
- [ ] `npm run lint`, `npm run build` e `npm test` passam

---

### P06M09: Criar os DTOs de provider com validação estrita

**Status:** 🚧 TODO
**ID:** P06M09

**Goal**

Definir `CreateProviderDto`, `UpdateProviderDto` e `CredentialsDto` com `class-validator`, garantindo que o `ValidationPipe` global rejeite qualquer campo não declarado.

**Acceptance Criteria**

- [ ] `CreateProviderDto` valida `provider_id`, `base_url` (URL válida), `active` e o objeto `credentials` obrigatório
- [ ] `UpdateProviderDto` cobre apenas metadados (`base_url`, `active`) e rejeita qualquer campo de credencial com 400
- [ ] `CredentialsDto` valida as chaves de credencial como strings não vazias com tamanho máximo definido, sem `any`
- [ ] Os DTOs de credencial estão marcados para exclusão de log e de serialização de resposta
- [ ] Teste e2e prova que enviar `credentials` em `PUT /api/tenants/:tid/providers/:pid` retorna 400 por `forbidNonWhitelisted`
- [ ] Testes unitários cobrem entrada válida e ao menos três entradas inválidas por DTO
- [ ] `npm run lint`, `npm run build` e `npm test` passam

---

### P06M10: Criar o esqueleto de `ProviderService`, seus `DomainError` e o `ProvidersModule`

**Status:** 🚧 TODO
**ID:** P06M10

**Goal**

Montar o módulo `src/providers/` com `IProviderService`, o service vazio injetando repositório e `ISecretsService` por token, e a família de `DomainError` do domínio de providers.

**Acceptance Criteria**

- [ ] `ProvidersModule` registra `{ provide: 'IProviderService', useClass: ProviderService }` e `{ provide: 'IProviderRepository', useClass: ProviderConfigRepository }`
- [ ] `ProviderService` injeta `IProviderRepository`, `ISecretsService` e o serviço de propagação Redis apenas por token de interface
- [ ] `DomainError` tipados criados: `ProviderNotFoundError` (404), `ProviderAlreadyExistsError` (409), `ProviderInactiveError` (409) e `TenantNotAccessibleError` (403), cada um com `code` estável
- [ ] Nenhum arquivo de `src/providers/services/` importa SDK da AWS, `ioredis` ou TypeORM diretamente
- [ ] `ProvidersModule` está importado no `app.module.ts` e a aplicação sobe sem erro de DI
- [ ] Teste unitário instancia `ProviderService` com todos os mocks das interfaces, provando que o wiring é substituível
- [ ] `npm run lint`, `npm run build` e `npm test` passam

---

### P06M11: Implementar o mascaramento de credenciais para respostas de leitura

**Status:** 🚧 TODO
**ID:** P06M11

**Goal**

Criar o helper de máscara que gera e aplica `credentials_hint` (ex.: `dev-****-001`), garantindo que nenhuma resposta da API exponha valor de credencial em claro.

**Acceptance Criteria**

- [ ] Helper `maskCredential(value)` preserva no máximo os 4 primeiros e 3 últimos caracteres e mascara o restante
- [ ] Valor com menos de 8 caracteres é mascarado integralmente, sem revelar comprimento exato
- [ ] O hint é calculado no momento da criação/rotação e persistido em `credentials_hint`, sem o valor original
- [ ] O DTO de resposta de provider não possui nenhum campo capaz de carregar credencial em claro, verificado por teste de tipo/serialização
- [ ] Testes unitários cobrem valor curto, valor longo, valor vazio e valor `undefined`
- [ ] `npm run lint`, `npm run build` e `npm test` passam

---

### P06M12: Implementar `GET /api/tenants/:tid/providers` com RBAC e escopo de tenant

**Status:** 🚧 TODO
**ID:** P06M12

**Goal**

Entregar a listagem de providers do tenant para ADMIN e OPERATIONS, retornando apenas metadados e respeitando o escopo `tenant_id ∈ user.tenant_ids`.

**Acceptance Criteria**

- [ ] `ProviderController` expõe `GET /api/tenants/:tid/providers` com `@Roles('ADMIN', 'OPERATIONS')`
- [ ] O endpoint aplica o guard/helper de escopo de tenant da Phase 4 e retorna 403 para tenant fora de `tenant_ids`
- [ ] A resposta lista `provider_id`, `base_url`, `active`, `created_at` e `updated_at`, sem `secret_arn` nem qualquer credencial
- [ ] Providers soft-deleted não aparecem na listagem
- [ ] Paginação usa o `PaginationDto` compartilhado (default 20, max 100)
- [ ] Testes e2e cobrem ADMIN, OPERATIONS, tenant fora de escopo (403) e tenant de outra organization (403)
- [ ] `npm run lint`, `npm run build`, `npm test` e `npm run test:e2e` passam

---

### P06M13: Implementar `GET /api/tenants/:tid/providers/:pid` com credenciais mascaradas

**Status:** 🚧 TODO
**ID:** P06M13

**Goal**

Entregar o detalhe do provider retornando metadados e o `credentials_hint` mascarado, com teste e2e provando que nenhum campo em claro atravessa a resposta.

**Acceptance Criteria**

- [ ] `GET /api/tenants/:tid/providers/:pid` responde com `@Roles('ADMIN', 'OPERATIONS')` e escopo de tenant aplicado
- [ ] A resposta inclui `credentials_hint` mascarado e o indicador de última rotação, nunca o valor da credencial nem o `SecretString`
- [ ] `secret_arn` não é exposto na resposta pública do endpoint
- [ ] Provider inexistente ou soft-deleted retorna `ProviderNotFoundError` com 404
- [ ] Teste e2e para ADMIN e para OPERATIONS varre o corpo da resposta e falha se qualquer valor de credencial semeada aparecer
- [ ] `npm run lint`, `npm run build`, `npm test` e `npm run test:e2e` passam

---
### P06M14: Implementar a persistência de metadados em `POST /api/tenants/:tid/providers`

**Status:** 🚧 TODO
**ID:** P06M14

**Goal**

Criar o caminho de escrita de metadados do provider no `core-db` dentro de uma transação, ainda sem gravação no Secrets Manager, com RBAC ADMIN-only.

**Acceptance Criteria**

- [ ] `POST /api/tenants/:tid/providers` responde com `@Roles('ADMIN')` e retorna 403 para OPERATIONS, FINANCE, COMPLIANCE e SUPPORT
- [ ] A criação roda em transação única no `core-db`, gravando `tenant_id`, `provider_id`, `base_url` e `active`
- [ ] `provider_id` duplicado para o mesmo tenant retorna `ProviderAlreadyExistsError` com 409
- [ ] Tenant inexistente ou fora do escopo do usuário retorna 403 antes de qualquer escrita
- [ ] Nenhum campo do objeto `credentials` é gravado no `core-db` nesta etapa nem em nenhuma outra
- [ ] Testes de integração cobrem criação bem-sucedida, duplicidade e RBAC negativo
- [ ] `npm run lint`, `npm run build`, `npm test` e `npm run test:e2e` passam

---

### P06M15: Gravar as credenciais no Secrets Manager durante a criação do provider

**Status:** 🚧 TODO
**ID:** P06M15

**Goal**

Encadear `createProviderSecret` na criação do provider, persistindo apenas `secret_arn` e `credentials_hint` no `core-db` e descartando o valor em memória logo após o envio.

**Acceptance Criteria**

- [ ] `ProviderService.create` chama `ISecretsService.createProviderSecret` antes de confirmar a transação do `core-db`
- [ ] Somente `secret_arn` e `credentials_hint` são persistidos; o objeto `credentials` nunca é atribuído à entidade
- [ ] Falha na gravação do secret aborta a transação e nenhum provider fica persistido no `core-db`
- [ ] O ARN retornado é gravado na chave de cache `provider:credentials:arn:{tid}:{code}` do P06M05
- [ ] Nenhum log de qualquer etapa do fluxo contém o objeto `credentials`, verificado por teste que inspeciona o transporte de log
- [ ] Teste de integração contra LocalStack confirma o secret criado no path correto após um `POST` bem-sucedido
- [ ] `npm run lint`, `npm run build`, `npm test` e `npm run test:e2e` passam

---

### P06M16: Aplicar contrato forte de propagação Redis na criação de provider

**Status:** 🚧 TODO
**ID:** P06M16

**Goal**

Reusar o `TenantConfigPropagationService` da Phase 5 para atualizar `tenant:providers:{tenant_id}` na criação, com rollback completo e 500 em caso de falha do Redis, conforme §11.1.

**Acceptance Criteria**

- [ ] Após a persistência no `core-db`, a criação atualiza `tenant:providers:{tenant_id}` no Redis Core pelo serviço de propagação existente, sem reimplementar a escrita
- [ ] Falha do Redis após o retry com backoff+jitter faz rollback da transação do `core-db` e retorna 500
- [ ] Nenhum provider órfão permanece no `core-db` após o rollback, verificado por consulta direta no teste
- [ ] O secret já criado no Secrets Manager é registrado em log estruturado como órfão reconciliável, sem expor conteúdo
- [ ] O caso de falha não grava item em `redis_propagation_outbox` — criação é contrato forte, não reconciliação
- [ ] Teste de integração com Redis em falha cobre o cenário completo de rollback
- [ ] `npm run lint`, `npm run build`, `npm test` e `npm run test:e2e` passam

---

### P06M17: Implementar `PUT /api/tenants/:tid/providers/:pid` de metadados com outbox

**Status:** 🚧 TODO
**ID:** P06M17

**Goal**

Entregar a atualização de metadados do provider (ADMIN) com propagação Redis em contrato de reconciliação: falha do Redis grava em `redis_propagation_outbox` e mantém a resposta de sucesso.

**Acceptance Criteria**

- [ ] `PUT /api/tenants/:tid/providers/:pid` atualiza `base_url` e `active` com `@Roles('ADMIN')` e escopo de tenant aplicado
- [ ] Após a persistência, a chave `tenant:providers:{tenant_id}` é reconstruída pelo serviço de propagação da Phase 5
- [ ] Falha do Redis grava item em `redis_propagation_outbox` no `core-db`, emite o log `redis_propagation_failed` e retorna 200
- [ ] Nenhum campo de credencial é aceito nem alterado por este endpoint
- [ ] `GET /api/health/redis-propagation` reflete o incremento de `redis_propagation_pending_total` após a falha
- [ ] Testes de integração distintos cobrem o caminho feliz e o caminho de outbox
- [ ] `npm run lint`, `npm run build`, `npm test` e `npm run test:e2e` passam

---

### P06M18: Implementar a rotação de credenciais em `PUT /:pid/credentials`

**Status:** 🚧 TODO
**ID:** P06M18

**Goal**

Entregar a rotação de credenciais criando uma nova versão do secret no Secrets Manager, sem invalidar a leitura do core durante a operação e sem tocar nos metadados do provider.

**Acceptance Criteria**

- [ ] `PUT /api/tenants/:tid/providers/:pid/credentials` responde com `@Roles('ADMIN')` e escopo de tenant aplicado
- [ ] A rotação usa `PutSecretValue` sobre o secret existente, criando nova versão e mantendo a anterior acessível ao core até a promoção da nova
- [ ] Em nenhum instante da operação o secret fica ausente ou vazio para uma leitura concorrente do core — teste de integração faz leituras concorrentes durante a rotação e nenhuma falha
- [ ] `credentials_hint` e o timestamp de última rotação são atualizados no `core-db`; nenhum valor de credencial é persistido
- [ ] A chave `provider:credentials:arn:{tid}:{code}` é reescrita com o ARN vigente e o TTL de 5min é renovado
- [ ] Falha do Secrets Manager na rotação não altera `credentials_hint` no `core-db` e retorna erro tipado
- [ ] `npm run lint`, `npm run build`, `npm test` e `npm run test:e2e` passam

---

### P06M19: Registrar `CREDENTIALS_ROTATE` e as demais ações em `backoffice_audit_log`

**Status:** 🚧 TODO
**ID:** P06M19

**Goal**

Ligar todas as escritas do módulo de providers ao `BackofficeAuditLogService` da Phase 4, com sanitização garantida dos campos de credencial.

**Acceptance Criteria**

- [ ] Criação gera `CREATE`, atualização de metadados gera `UPDATE`, soft delete gera `DEACTIVATE` e rotação gera `CREDENTIALS_ROTATE` em `backoffice_audit_log`
- [ ] Cada registro traz `actor_id`, `actor_email`, `actor_role`, `resource_type`, `resource_id`, `payload_before`, `payload_after`, `ip_address` e `performed_at`
- [ ] `payload_before` e `payload_after` de `CREDENTIALS_ROTATE` contêm apenas o hint e o timestamp — nenhum valor de credencial, nem antes nem depois
- [ ] `secret_arn` é omitido ou truncado nos payloads de auditoria
- [ ] Teste parametrizado percorre as quatro ações e valida a presença de exatamente um registro por operação
- [ ] Teste dedicado varre `backoffice_audit_log` após rotação e falha se qualquer credencial semeada aparecer
- [ ] `npm run lint`, `npm run build`, `npm test` e `npm run test:e2e` passam

---

### P06M20: Implementar `DELETE /api/tenants/:tid/providers/:pid` com soft delete e outbox

**Status:** 🚧 TODO
**ID:** P06M20

**Goal**

Entregar a desativação do provider por soft delete (ADMIN), removendo-o da chave `tenant:providers:{tenant_id}` com contrato de reconciliação em falha de Redis.

**Acceptance Criteria**

- [ ] `DELETE /api/tenants/:tid/providers/:pid` grava `deleted_at` e `deleted_by` sem remover a linha do `core-db`
- [ ] A chave `tenant:providers:{tenant_id}` é reconstruída sem o provider desativado
- [ ] Falha do Redis grava item em `redis_propagation_outbox`, emite `redis_propagation_failed` e mantém a resposta de sucesso
- [ ] O secret no Secrets Manager não é apagado pela operação, e essa decisão está documentada no README do serviço
- [ ] Desativar um provider já desativado retorna `ProviderNotFoundError` com 404, sem gerar novo registro de auditoria
- [ ] Testes de integração cobrem soft delete bem-sucedido, caminho de outbox e dupla desativação
- [ ] `npm run lint`, `npm run build`, `npm test` e `npm run test:e2e` passam

---
