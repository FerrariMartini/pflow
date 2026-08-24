# Phase 12: SSE em Tempo Real com Fanout via Redis Pub/Sub

**Duration**: ~3 days (24 milestones @ 1h each)
**Dependencies**: Phase 7 (projeções emissoras), Phase 8 (read model consultável), Phase 9 (eventos de CB operacionais)
**Status**: 🚧 TODO

## Goal

Substituir polling por streams SSE persistentes (`src/events/`), entregando atualização em tempo real das telas de transações e de circuit breaker com fanout correto em deploy multi-instância.

Entregas principais:
- Conexão Valkey Pub/Sub dedicada (`REDIS_PUBSUB_URL`) com clientes ioredis separados para `PUBLISH` e `SUBSCRIBE`, canais `tx-events` e `cb-events`.
- `EventsService` com `RxJS Subject` alimentado pela subscrição Redis; as projeções da Fase 7 passam a emitir após a escrita durável no `backoffice-db`.
- `GET /api/events/transactions` (todos os perfis) e `GET /api/events/circuit-breaker` (ADMIN, OPERATIONS) com `@Sse`, autenticados pelo mesmo `JwtAuthGuard` via cookie HttpOnly.
- Filtro de eventos por `user.tenant_ids` antes da entrega ao cliente.
- Batching com `bufferTime(500ms)`; cada evento carrega `id` (`transaction_id` ou ULID) e `data` como array.
- At-least-once: `Last-Event-ID` na reconexão dispara replay do `backoffice-db` dos eventos mais recentes que esse ID antes de retomar o stream ao vivo.
- Encerramento limpo de conexão (cliente desconecta, shutdown da instância) sem vazamento de subscrição.
- ADR registrando a escolha de SSE sobre WebSocket e do fanout via Redis Pub/Sub isolado.

## Phase Acceptance Criteria

- Evento consumido pela instância A é entregue a um cliente SSE conectado na instância B — teste de integração com duas instâncias da aplicação contra o Valkey do compose (o cenário que motiva o Pub/Sub).
- Operador nunca recebe evento de tenant fora de `user.tenant_ids` — teste com dois usuários de escopos diferentes na mesma conexão de Pub/Sub (P0).
- `bufferTime(500ms)` agrupa rajadas: 50 eventos em 1s chegam ao cliente em no máximo 2 mensagens, cada uma com `data` em array — verificado por teste.
- Reconexão com `Last-Event-ID` replaya do banco exatamente os eventos posteriores a esse ID, sem duplicar nem pular, e sem replay quando o header está ausente — três casos de teste.
- `GET /api/events/circuit-breaker` nega FINANCE, COMPLIANCE e SUPPORT; ambos os streams negam requisição sem JWT válido.
- Desconexão do cliente e shutdown da instância liberam a subscrição e não deixam handler pendurado — teste verifica ausência de vazamento após N conexões abertas e fechadas.
- Latência do evento Kafka até o cliente conectado é < 2s no benchmark de hot spot registrado (P4 do §14).
- Cobertura ≥ 90% em `EventsService` e `RedisPubSubService`; `scripts/pre-commit.sh` verde, ADR criado em `docs/decisions/` e `docs/contract/contract.md` atualizado com o contrato SSE.

## Milestones

<!-- Milestones appended by /wiz-milestones -->
