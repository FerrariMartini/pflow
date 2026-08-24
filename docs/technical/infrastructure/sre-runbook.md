# SRE — runbook e operação

## Severidades de incidente

| Severidade | Critério | Exemplo | Resposta esperada |
|---|---|---|---|
| SEV1 | Movimentação de valor impactada (cash-in/cash-out indisponível ou processando incorretamente) | `payflow-cashin-service` fora do ar | Acionamento imediato, war room, comunicação a stakeholders em até 15 min |
| SEV2 | Degradação sem impacto direto em valor | Lag alto em `outbox-relay`, atraso de webhook | Acionamento em até 30 min, sem war room obrigatório |
| SEV3 | Impacto restrito a operação/observabilidade | `payflow-audit-service` com atraso de ingestão | Tratado em horário comercial, sem acionamento fora de escala |

## Alertas de referência e runbook associado

### Alerta: lag de consumidor acima do SLO (`payflow-outbox-relay`)
- **Sintoma**: eventos demoram para chegar aos consumidores (webhook, audit, backoffice).
- **Primeira ação**: verificar se é lag de leitura (poll não acompanha volume) ou lag de publicação (broker aceitando devagar) — dashboards separam as duas métricas.
- **Mitigação imediata**: escalar horizontalmente o `outbox-relay` (é stateless e usa `SELECT ... FOR UPDATE SKIP LOCKED`, seguro escalar sem coordenação adicional).
- **Escalonamento**: se lag persiste após scale-out, verificar saúde do MSK (partições sub-replicadas, ISR shrink) antes de investigar a aplicação.

### Alerta: taxa de erro do `payflow-gateway` acima de 1%
- **Primeira ação**: verificar se é concentrado em um integrador (rate limit/HMAC de um cliente específico) ou geral (rollout ruim, dependência downstream fora do ar).
- **Mitigação imediata**: se geral e correlacionado com deploy recente, rollback segue o critério automático de `docs/technical/ci-cd.md` (mas pode ser antecipado manualmente).

### Alerta: transações não conciliadas acima do limiar (`payflow-backoffice-api`)
- **Sintoma**: métrica de negócio (ver `docs/technical/architecture/observability.md`) subindo — indica divergência crescente entre hub e provedor, não é só um problema técnico.
- **Primeira ação**: time de operação (não SRE) investiga via `GET /v1/transactions?status=...`; SRE só é acionado se a causa raiz for técnica (ex: consumidor de eventos do read model parado).

## Prontidão operacional (definition of "pronto para produção")

Um serviço novo só vai para produção quando:
1. Dashboards RED (ou de consumidor, conforme o tipo) publicados e revisados por SRE.
2. Ao menos um alerta crítico configurado e testado (disparo simulado, não só configurado "no papel").
3. Runbook mínimo documentado nesta página (ou em anexo) para o alerta crítico acima.
4. Rollback automático configurado conforme `docs/technical/ci-cd.md`.

## On-call

Rotação semanal, escopo por domínio (não um único on-call genérico para os 7 serviços) — quem está de plantão em `cashin`/`cashout` não é necessariamente quem responde por `audit-service`, dado o perfil de severidade muito diferente entre esses grupos.
