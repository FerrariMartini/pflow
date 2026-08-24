# Arquitetura — Observabilidade

## Princípio

Numa arquitetura orientada a eventos (ver `overview.md`), uma transação atravessa vários serviços de forma assíncrona — sem observabilidade de ponta a ponta, um incidente vira uma investigação manual em múltiplos bancos de dados. Observabilidade não é um add-on aqui, é pré-requisito da arquitetura escolhida (ADR-0001).

## Três pilares

### Logs estruturados
- Todo log é JSON estruturado, nunca string livre, com campos fixos: `timestamp`, `level`, `service`, `correlationId`, `transactionId` (quando aplicável), `message`.
- `correlationId` é gerado no `payflow-gateway` na entrada da requisição e propagado em todo header/evento subsequente — é a chave de busca principal em qualquer investigação.
- Ver `docs/technical/guidelines/logging.md` para convenções de nível de log e o que nunca deve ser logado.

### Métricas
- RED (Rate, Errors, Duration) por endpoint em todo serviço síncrono (`gateway`, `backoffice-api`).
- Métricas de consumidor (lag de partição, taxa de processamento, taxa de erro) em todo serviço assíncrono (`cashin`, `cashout`, `webhook`, `outbox-relay`, `audit`).
- Métrica de negócio dedicada: taxa de transações não conciliadas (`payflow-backoffice-api`) e idade da mais antiga pendência de conciliação — é o principal indicador de saúde operacional do hub, não só técnico.

### Tracing distribuído
- Cada requisição síncrona e cada evento assíncrono carregam contexto de trace (`traceId`/`spanId`) propagado via header (síncrono) ou payload do evento (assíncrono), permitindo reconstruir a jornada completa de uma transação — do `POST /v1/cash-in` até a notificação de webhook — numa única visualização.

## SLOs de referência

| Sinal | Alvo |
|---|---|
| Latência p95 de confirmação de cash-in | < 200ms (ver PRD, seção 6) |
| Lag máximo de consumidor em `outbox-relay` | < 10s sob carga normal |
| Tempo entre evento gerado e entrega de webhook (p95) | < 30s |
| Divergência não detectada entre hub e provedor | 0 (garantida por conciliação periódica automatizada + manual) |

## Estado da instrumentação

Este documento define o desenho: quais sinais são coletados, com que campos e contra quais SLOs. A instrumentação (OpenTelemetry, coletor, dashboards, alertas) depende da infraestrutura descrita em `docs/technical/infrastructure/aws-architecture.md` e é rastreada como trabalho próprio, planejado via o PayFlow SDLC Kit (`/wiz-prd`) quando priorizada.

A base já está no código: `correlationId` e os campos estruturados de log definidos em `docs/technical/guidelines/logging.md` estão presentes em `payflow-backoffice-api`, que é o ponto de partida da propagação ponta a ponta descrita acima.
