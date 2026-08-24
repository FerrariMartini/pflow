# Phase 7: Consumers Kafka e Projeções Idempotentes do Read Model

**Duration**: ~4 days (32 milestones @ 1h each)
**Dependencies**: Phase 4 (autorização) e Phase 1 (migrations do read model). Pode iniciar em paralelo à Phase 6.
**Status**: 🚧 TODO

## Goal

Construir a infraestrutura Kafka e as projeções que alimentam o read model do backoffice (ADR-0002), com idempotência garantida por `eventId` — pré-requisito das telas operacionais, conforme a restrição do §15 do PRD.

Entregas principais:
- `infrastructure/kafka/` com `@nestjs/microservices` + KafkaJS, consumer group `backoffice-api`, partition key `tenant_id`, e validação do envelope de evento (`eventId`, `correlationId`, `occurredAt`, `payload`) conforme `docs/contract/contract.md`.
- `cashin.projection.ts`: `transaction.cashin.initiated.v1` (INSERT PENDING), `transaction.cashin.completed.v1` e `transaction.cashin.failed.v1` (UPDATE status).
- `cashout.projection.ts`: `transaction.cashout.requested.v1` (INSERT PROCESSING), `transaction.cashout.completed.v1`, `transaction.cashout.failed.v1`, `transaction.cashout.reversed.v1` (UPDATE status).
- `circuit-breaker.projection.ts`: `circuit_breaker.kicked.v1` e `circuit_breaker.recovered.v1` → INSERT em `circuit_breaker_events`.
- Consumer de `balancing.recalibrated.v1` (log operacional) e `dlq.projection.ts` para `webhook.dlq.v1` (alerta operacional).
- Deduplicação por `eventId` e proteção contra evento fora de ordem (não regredir status por `occurredAt` mais antigo).
- Tratamento de payload malformado sem travar a partição (rejeição registrada, offset avança de forma controlada).
- Métricas de consumer lag e taxa de processamento via `dd-trace-js`, e `GET /api/health` estendido para incluir Kafka.

## Phase Acceptance Criteria

- Reprocessar o mesmo offset/`eventId` não gera duplicata nem altera o estado projetado — teste de integração contra Redpanda do compose reprocessa cada um dos 7 eventos transacionais (P0 — idempotência).
- Evento fora de ordem (`completed` chegando antes de `initiated`, ou `occurredAt` mais antigo que o estado atual) não regride o status da transação — caso de borda com teste dedicado por fluxo.
- Envelope inválido ou payload malformado é rejeitado com log `error` estruturado e não bloqueia o consumo da partição — teste prova que o consumer continua processando o evento seguinte.
- Teste de contrato valida o schema de cada um dos 11 tópicos consumidos contra `docs/contract/contract.md`, e a divergência falha o build.
- Todas as projeções gravam `tenant_id` corretamente e respeitam a RLS do `backoffice-db`; nenhuma projeção escreve linha sem `tenant_id`.
- Consumer lag e taxa de processamento são expostos como métrica custom no DataDog e `GET /api/health` reporta o estado do Kafka.
- Todo log de projeção carrega `correlationId` propagado do envelope do evento — verificado por teste.
- Cobertura ≥ 90% nos handlers de projeção; `scripts/pre-commit.sh` verde.

## Milestones

<!-- Milestones appended by /wiz-milestones -->
### P07M01: Adicionar configuração de ambiente do Kafka ao schema Zod

**Status:** 🚧 TODO
**ID:** P07M01

**Goal**

Estender o módulo `config/` da Fase 1 com as variáveis de conexão do Kafka (`KAFKA_BROKERS`, `KAFKA_CLIENT_ID`, `KAFKA_CONSUMER_GROUP`, timeouts e retry) validadas por Zod, garantindo que o serviço falhe no boot quando a configuração estiver ausente ou inválida.

**Acceptance Criteria**

- [ ] Schema Zod valida `KAFKA_BROKERS` (lista separada por vírgula, mínimo 1), `KAFKA_CLIENT_ID`, `KAFKA_CONSUMER_GROUP` (default `backoffice-api`), `KAFKA_SESSION_TIMEOUT_MS`, `KAFKA_HEARTBEAT_INTERVAL_MS` e `KAFKA_RETRY_MAX_ATTEMPTS`
- [ ] Valor default do consumer group é `backoffice-api`, conforme §7 do PRD
- [ ] Boot com `KAFKA_BROKERS` vazio ou malformado aborta com mensagem de erro explícita, sem stack trace de infraestrutura
- [ ] `.env.example` e o serviço `backoffice-api` do `docker-compose.yml` expõem `KAFKA_BROKERS: redpanda:9092`
- [ ] Testes unitários cobrem configuração válida, ausente e malformada
- [ ] `scripts/pre-commit.sh` verde

---

### P07M02: Criar o módulo de infraestrutura Kafka com @nestjs/microservices

**Status:** 🚧 TODO
**ID:** P07M02

**Goal**

Criar `src/infrastructure/kafka/kafka.module.ts` registrando o transporte Kafka do `@nestjs/microservices` (KafkaJS integrado), com consumer group `backoffice-api` e partition key `tenant_id`, exposto por token de injeção conforme `docs/technical/guidelines/dependency-injection.md`.

**Acceptance Criteria**

- [ ] `KafkaModule` registra o transport `Transport.KAFKA` com brokers, `clientId` e `groupId` vindos do `ConfigService` — nenhum valor hardcoded
- [ ] Partition key das mensagens produzidas é `tenant_id`, conforme §7 do PRD
- [ ] Cliente exposto via token de interface (`IKafkaClient`), nunca a classe concreta do KafkaJS
- [ ] `allowAutoTopicCreation` desabilitado; tópicos são responsabilidade do broker
- [ ] Módulo importável pelo `AppModule` sem dependência circular
- [ ] Teste de integração sobe o módulo com DI real e valida a configuração resolvida
- [ ] `scripts/pre-commit.sh` verde

---

### P07M03: Fazer bootstrap híbrido HTTP + microservice Kafka no main.ts

**Status:** 🚧 TODO
**ID:** P07M03

**Goal**

Ajustar `main.ts` para conectar o microservice Kafka ao lado da aplicação HTTP (`connectMicroservice` + `startAllMicroservices`), com shutdown gracioso que fecha o consumer antes de encerrar o processo.

**Acceptance Criteria**

- [ ] `connectMicroservice` registrado antes de `listen()`, e `startAllMicroservices()` chamado no bootstrap
- [ ] `enableShutdownHooks()` habilitado; `SIGTERM` desconecta o consumer do grupo antes de encerrar
- [ ] Falha de conexão com o broker no boot é registrada com log `error` estruturado e o processo encerra com exit code diferente de zero
- [ ] Servidor HTTP continua respondendo em `/api` com o prefixo global inalterado
- [ ] Teste e2e sobe a aplicação híbrida e confirma que o contexto Nest inicializa com o consumer conectado
- [ ] `scripts/pre-commit.sh` verde

---

### P07M04: Definir os tipos do envelope de evento e a interface IProjectionHandler

**Status:** 🚧 TODO
**ID:** P07M04

**Goal**

Criar em `src/projections/interfaces/` o contrato tipado do envelope de evento (`eventId`, `correlationId`, `occurredAt`, `payload`) e a interface `IProjectionHandler`, base comum de todas as projeções.

**Acceptance Criteria**

- [ ] Tipo `EventEnvelope<TPayload>` com `eventId`, `correlationId`, `occurredAt` e `payload` genérico, exatamente os campos de `docs/contract/contract.md`
- [ ] `IProjectionHandler<TPayload>` define `handle(envelope: EventEnvelope<TPayload>): Promise<void>` e o tópico que atende
- [ ] Tipos de payload declarados para os 11 tópicos consumidos da §7, sem uso de `any`
- [ ] TypeScript `strict` sem erros e sem supressão via `@ts-ignore`
- [ ] Domínio livre de import de infraestrutura, conforme `docs/technical/guidelines/dependency-injection.md`
- [ ] `scripts/pre-commit.sh` verde

---

### P07M05: Implementar a validação do envelope de evento

**Status:** 🚧 TODO
**ID:** P07M05

**Goal**

Criar `EnvelopeValidator` em `infrastructure/kafka/` que valida via Zod todo evento recebido contra o envelope de `docs/contract/contract.md`, rejeitando mensagens sem `eventId`, `correlationId`, `occurredAt` válido ou `payload`.

**Acceptance Criteria**

- [ ] `eventId` e `correlationId` validados como UUID; `occurredAt` como ISO-8601 com timezone; `payload` como objeto não vazio
- [ ] Retorno é um resultado tipado (`Ok`/`Err`) com `DomainError` na rejeição — sem `throw` para erro de validação, conforme `docs/technical/guidelines/error-handling.md`
- [ ] Mensagem que não é JSON válido é tratada como rejeição, não como exceção não capturada
- [ ] Nenhum campo do `payload` é logado na rejeição — apenas `eventId`, tópico, partição, offset e o motivo
- [ ] Testes unitários cobrem envelope válido e um caso de rejeição por campo faltante, tipo errado e JSON inválido
- [ ] Cobertura ≥ 90% no validador; `scripts/pre-commit.sh` verde

---

### P07M06: Criar o handler base de projeção com pipeline de processamento

**Status:** 🚧 TODO
**ID:** P07M06

**Goal**

Implementar `BaseProjectionHandler` em `infrastructure/kafka/`, encapsulando o pipeline comum de toda projeção: desserialização, validação do envelope, delegação ao handler concreto e fronteira de erro única.

**Acceptance Criteria**

- [ ] Pipeline executa na ordem: desserializar → validar envelope → delegar ao handler concreto → registrar resultado
- [ ] Handlers concretos implementam apenas `IProjectionHandler`, sem repetir validação ou tratamento de erro
- [ ] Ponto de extensão para emissão de eventos SSE documentado no código como pendência da Phase 12, sem implementação nesta fase
- [ ] Nenhuma exceção escapa do pipeline para o consumer do KafkaJS
- [ ] Testes unitários com handler concreto fake cobrem sucesso, envelope inválido e exceção lançada pelo handler
- [ ] Cobertura ≥ 90% no handler base; `scripts/pre-commit.sh` verde

---
### P07M07: Criar a migration da tabela processed_events

**Status:** 🚧 TODO
**ID:** P07M07

**Goal**

Adicionar ao `backoffice-db` a tabela `processed_events`, base da deduplicação por `eventId` exigida pelo P0 do §14, com RLS por `tenant_id` no mesmo padrão das demais tabelas da Fase 1.

**Acceptance Criteria**

- [ ] Migration cria `processed_events` com `event_id` UUID, `topic`, `tenant_id` UUID NOT NULL, `occurred_at` TIMESTAMPTZ e `processed_at` TIMESTAMPTZ DEFAULT now()
- [ ] Constraint UNIQUE em (`event_id`, `topic`) garante a deduplicação no nível do banco
- [ ] RLS habilitada com policy por `app.current_tenant_id`, idêntica ao padrão das demais tabelas do `backoffice-db`
- [ ] Índice em `processed_at` para permitir limpeza futura sem full scan
- [ ] Migration possui `down` funcional e roda de forma limpa a partir de banco vazio
- [ ] Teste de integração aplica a migration e prova que INSERT duplicado do mesmo (`event_id`, `topic`) viola a constraint
- [ ] `scripts/pre-commit.sh` verde

---

### P07M08: Implementar o repositório e o serviço de deduplicação por eventId

**Status:** 🚧 TODO
**ID:** P07M08

**Goal**

Criar `IProcessedEventRepository` e `EventDeduplicationService` em `src/projections/`, responsáveis por registrar o `eventId` processado e informar se um evento já foi aplicado.

**Acceptance Criteria**

- [ ] `IProcessedEventRepository` expõe `registerIfNew(eventId, topic, tenantId, occurredAt)` retornando indicação de duplicata sem lançar exceção
- [ ] Implementação usa `INSERT ... ON CONFLICT DO NOTHING` e trata a violação de unique como duplicata, nunca como falha técnica
- [ ] Registro sempre grava `tenant_id`; tentativa sem `tenant_id` é rejeitada com `DomainError` antes de tocar o banco
- [ ] Serviço injetado por token de interface; teste unitário moca o repositório
- [ ] Teste de integração prova que a segunda chamada com o mesmo `eventId` retorna duplicata
- [ ] Cobertura ≥ 90% no serviço e no repositório; `scripts/pre-commit.sh` verde

---

### P07M09: Integrar a deduplicação ao pipeline do handler base

**Status:** 🚧 TODO
**ID:** P07M09

**Goal**

Acoplar o `EventDeduplicationService` ao `BaseProjectionHandler` de modo que o registro do `eventId` e a escrita da projeção ocorram na mesma transação de banco, garantindo o P0 de idempotência.

**Acceptance Criteria**

- [ ] Registro em `processed_events` e escrita da projeção acontecem dentro de uma única transação TypeORM
- [ ] Evento já processado é descartado antes de qualquer escrita, com log `info` contendo `eventId`, tópico e `correlationId`
- [ ] Falha na escrita da projeção faz rollback do registro em `processed_events`, permitindo reprocessamento
- [ ] Contador de eventos deduplicados exposto para uso posterior nas métricas
- [ ] Teste de integração reprocessa o mesmo evento e confirma que o estado projetado não muda e nenhuma linha é duplicada
- [ ] Cobertura ≥ 90% no pipeline; `scripts/pre-commit.sh` verde

---

### P07M10: Implementar a guarda de ordenação por occurredAt

**Status:** 🚧 TODO
**ID:** P07M10

**Goal**

Criar o helper de transição de estado que impede regressão de status quando chega evento com `occurredAt` mais antigo que o já projetado, atendendo à consequência de eventos fora de ordem apontada no ADR-0002.

**Acceptance Criteria**

- [ ] Função pura `shouldApplyTransition(currentOccurredAt, incomingOccurredAt, currentStatus, incomingStatus)` decide aplicar ou descartar a atualização
- [ ] Evento com `occurredAt` anterior ao último aplicado na mesma transação é descartado com log `warn` contendo `eventId` e `correlationId`
- [ ] Status terminal (`COMPLETED`, `FAILED`, `REVERSED`) nunca regride para `PENDING` ou `PROCESSING`
- [ ] Coluna que guarda o `occurredAt` do último evento aplicado é atualizada junto com o status
- [ ] Testes unitários cobrem evento em ordem, fora de ordem, empate de `occurredAt` e tentativa de regressão de status terminal
- [ ] Cobertura ≥ 90% no helper; `scripts/pre-commit.sh` verde

---

### P07M11: Criar o repositório de projeção de cash-in

**Status:** 🚧 TODO
**ID:** P07M11

**Goal**

Implementar `ICashinProjectionRepository` e sua implementação TypeORM sobre `cashin_transactions`, com `SET LOCAL app.current_tenant_id` por transação para respeitar a RLS do `backoffice-db`.

**Acceptance Criteria**

- [ ] Repositório expõe `insertPending(...)` e `updateStatus(...)` operando na entidade `CashinTransaction`
- [ ] Toda operação executa `SET LOCAL app.current_tenant_id` com o `tenant_id` do evento antes do comando SQL
- [ ] Escrita sem `tenant_id` é rejeitada com `DomainError` antes de chegar ao banco
- [ ] Repositório injetado por token de interface, sem vazar TypeORM para a camada de projeção
- [ ] Teste de integração prova que escrita e leitura respeitam a RLS e que consulta com outro `tenant_id` não enxerga a linha
- [ ] Cobertura ≥ 90% no repositório; `scripts/pre-commit.sh` verde

---

### P07M12: Projetar transaction.cashin.initiated.v1 como INSERT PENDING

**Status:** 🚧 TODO
**ID:** P07M12

**Goal**

Implementar em `cashin.projection.ts` o handler de `transaction.cashin.initiated.v1`, inserindo a transação em `cashin_transactions` com status `PENDING`.

**Acceptance Criteria**

- [ ] Handler registrado no tópico `transaction.cashin.initiated.v1` e inserindo linha com status `PENDING`
- [ ] Todos os campos do payload mapeados para as colunas do read model, incluindo `tenant_id`, `provider_id` e `occurredAt` do envelope
- [ ] Reentrega do mesmo `eventId` não cria segunda linha (deduplicação da P07M09 exercitada por teste)
- [ ] Payload sem campo obrigatório é rejeitado com log `error` estruturado, sem escrita parcial
- [ ] Testes unitários cobrem inserção com sucesso e ao menos um caso de rejeição
- [ ] Cobertura ≥ 90% no handler; `scripts/pre-commit.sh` verde

---

### P07M13: Projetar transaction.cashin.completed.v1 e failed.v1 como UPDATE de status

**Status:** 🚧 TODO
**ID:** P07M13

**Goal**

Implementar os handlers de `transaction.cashin.completed.v1` e `transaction.cashin.failed.v1`, atualizando o status da linha em `cashin_transactions` com a guarda de ordenação da P07M10.

**Acceptance Criteria**

- [ ] `completed` leva o status para `COMPLETED` e `failed` para `FAILED`, ambos gravando o motivo/metadados do payload quando presentes
- [ ] Ambos passam pelo `shouldApplyTransition` e descartam evento com `occurredAt` mais antigo que o já aplicado
- [ ] UPDATE que não encontra a transação registra log `warn` e não cria linha silenciosamente por esse caminho
- [ ] Reentrega do mesmo `eventId` não altera o estado projetado
- [ ] Testes unitários cobrem sucesso de cada tópico, evento fora de ordem e transação inexistente
- [ ] Cobertura ≥ 90% nos handlers; `scripts/pre-commit.sh` verde

---
