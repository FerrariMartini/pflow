# Arquitetura — Visão Geral

## Estilo arquitetural

Microsserviços orientados a eventos. A borda com o integrador é sempre REST (HTTPS + HMAC), mas **o protocolo interno entre gateway e serviço de domínio muda conforme a natureza do fluxo**: cash-in é síncrono (gRPC), cash-out é assíncrono (comando via Kafka). Ver seção "Por que cash-in é síncrono e cash-out é assíncrono" abaixo. Em ambos os casos, a propagação de estado para o resto do hub usa o **padrão outbox transacional**, garantindo que nenhum evento seja perdido mesmo em caso de falha entre a escrita no banco e a publicação no broker.

```
Integrador
   │ REST (HTTPS + HMAC)
   ▼
┌───────────────────┐
│  payflow-gateway   │  auth, rate limit, roteamento
└──┬─────────────┬───┘
   │ gRPC          │ publica payflow.cashout.command.v1
   │ (síncrono)    │ (assíncrono — gateway responde 202 Accepted)
   ▼               ▼
┌──────────┐   ┌─────────────────────────┐
│ cash-in  │   │ payflow.cashout.command │  Kafka
└────┬─────┘   └───────────┬─────────────┘
     │                     ▼
     │               ┌───────────┐
     │               │ cash-out  │  consome o comando
     │               └─────┬─────┘
     │ outbox               │ outbox
     ▼                      ▼
┌───────────────────────────────┐
│      payflow-outbox-relay      │  lê outbox, publica em Kafka, marca como enviado
└────────────────┬────────────────┘
                 │ eventos de domínio
   ┌─────────────┼──────────────┬───────────────┐
   ▼             ▼               ▼               ▼
┌────────┐   ┌───────────┐ ┌────────────┐ ┌──────────────┐
│webhook │   │  audit    │ │ backoffice │ │ (futuros      │
│service │   │  service  │ │    api     │ │  consumidores)│
└────────┘   └───────────┘ └────────────┘ └──────────────┘
```

## Por que cash-in é síncrono e cash-out é assíncrono

Os dois fluxos parecem simétricos (ambos criam uma transação e a levam a um provedor de liquidação), mas a natureza da resposta que o integrador precisa é diferente — e isso guia o protocolo interno:

- **Cash-in (gRPC, síncrono)**: o integrador precisa de um dado de volta na resposta (ex: referência de cobrança a ser exibida ao usuário final) para poder prosseguir. Não há como responder de forma útil sem esperar o resultado da chamada ao provedor — então o gateway chama `payflow-cashin-service` via **gRPC** e só responde ao integrador depois que o serviço confirma a criação da cobrança.
- **Cash-out (comando Kafka, assíncrono)**: o integrador só precisa saber que a ordem foi aceita, não o resultado imediato da liquidação. Desacoplar a aceitação do processamento evita bloquear a resposta HTTP na latência do provedor e, mais importante, **reduz o risco de double-execution**: se o gateway chamasse o provedor de forma síncrona e a conexão caísse depois do provedor confirmar mas antes da resposta chegar, um retry do integrador poderia gerar um segundo pagamento. Como comando assíncrono com `Idempotency-Key`, um retry do integrador é deduplicado antes mesmo de chegar ao `payflow-cashout-service`. O gateway responde `202 Accepted` + `transactionId`; o status final é consultado depois (`GET /v1/cash-out/:id`, ou de forma unificada via `payflow-backoffice-api`).

Essa assimetria é deliberada, não uma inconsistência entre os dois serviços — ver `docs/contract/contract.md` para o detalhamento de protocolo por serviço.

## Por que esse padrão (demais decisões)

- **Outbox em vez de publicar direto no broker dentro do handler**: evita o problema clássico de "escrevi no banco mas caí antes de publicar o evento" (ou vice-versa). A escrita da transação e a escrita do evento pendente acontecem na mesma transação de banco; um processo separado (`outbox-relay`) garante a publicação com at-least-once delivery.
- **Gateway como única porta de entrada**: centraliza autenticação e rate limiting, evitando que cada serviço de domínio reimplemente essa lógica.
- **Backoffice como consumidor, não como dono do dado transacional**: o backoffice-api mantém um *read model* próprio, construído a partir dos eventos de domínio, otimizado para consulta operacional (busca, filtros, paginação) — sem acoplar o time de operação ao schema interno do cash-in/cash-out.

## Consistência e idempotência

- Toda chamada de entrada (`POST /cash-in` via gRPC, `POST /cash-out` via comando Kafka) exige um `Idempotency-Key`. Requisições repetidas com a mesma chave retornam o resultado da primeira execução, sem reprocessar — no caso do cash-out, a deduplicação acontece antes do comando ser efetivamente processado, não depois.
- Cada transação tem uma máquina de estados explícita (`created → processing → confirmed | failed | reversed`), e transições inválidas são rejeitadas na camada de domínio, não apenas validadas na API.

## Observabilidade

- Todo evento de domínio carrega um `correlation_id` (originado na requisição no gateway) propagado por todos os serviços downstream, permitindo rastrear uma transação de ponta a ponta nos logs.
- `payflow-audit-service` persiste uma cópia imutável de todo evento relevante, servindo como fonte de verdade para investigações — independente do estado atual em cada serviço.
- Ver `docs/technical/architecture/observability.md` para os três pilares (logs/métricas/tracing) e SLOs de referência.

## Segurança

Ver `docs/technical/architecture/security.md` para modelo de ameaças, autenticação por camada (integrador→gateway, serviço→serviço, operador→backoffice) e proteção de dados. Idempotência (seção acima) é tratada ali também como controle de segurança, não só de confiabilidade.

## Infraestrutura

Ver `docs/technical/infrastructure/aws-architecture.md` para o desenho de infraestrutura (ECS Fargate, MSK, RDS por serviço, isolamento de rede) e `docs/technical/infrastructure/sre-runbook.md` para severidades de incidente e runbooks dos alertas críticos.

## Evolução v1 → v2

**v1 (escopo deste repositório)**: um único provedor de liquidação por trás do hub, isolamento multi-tenant só na camada de aplicação (ver `docs/technical/infrastructure/aws-architecture.md`), sem split de pagamento entre beneficiários (ver PRD, seção 5 — fora de escopo v1).

**v2 (fora de escopo, mas já considerado no desenho)**: suporte a múltiplos provedores simultâneos com roteamento por custo/SLA — isso muda `payflow-cashin-service`/`payflow-cashout-service` de "integra com um provedor" para "escolhe entre provedores", o que é o motivo de já isolarmos o cliente do provedor atrás de uma interface própria desde a v1 (Dependency Inversion, ver `docs/technical/guidelines/dependency-injection.md`) — trocar/adicionar provedor não deve exigir reescrever a máquina de estados.

## Detalhamento por serviço

Ver `services/<nome-do-serviço>/README.md` para contrato de API, eventos publicados/consumidos e decisões específicas de cada serviço. A quebra em fases/milestones de cada serviço fica em `.wiz/<slug>/` a partir do momento em que ele é planejado via o PayFlow SDLC Kit (`/wiz-prd` → `/wiz-phases` → `/wiz-milestones`) — hoje só `payflow-backoffice-api` (`.wiz/backoffice-api/`) passou por esse processo.
