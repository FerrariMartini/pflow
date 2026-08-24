# PRD — PayFlow Hub

## 1. Contexto e problema

Empresas que processam pagamentos instantâneos (ex: PIX no Brasil) frequentemente dependem de um único provedor/banco para liquidar transações. Isso gera três problemas recorrentes:

1. **Ponto único de falha**: indisponibilidade do provedor paralisa o fluxo de pagamentos do negócio.
2. **Falta de padronização**: cada integração bancária expõe um contrato diferente, forçando os sistemas internos a conhecer detalhes de cada banco.
3. **Baixa observabilidade operacional**: sem um ponto central de conciliação, é difícil para o time de operações (backoffice) saber o status real de uma transação em caso de divergência.

## 2. Objetivo

Construir um **hub de pagamentos** que abstraia múltiplos provedores de liquidação atrás de um contrato único e interno, garanta consistência via processamento assíncrono orientado a eventos, e ofereça a times de operação uma visão unificada e auditável de todas as transações.

## 3. Personas

- **Integrador (cliente do hub)**: sistemas internos de outros produtos da empresa que iniciam cobranças (cash-in) ou pagamentos (cash-out) através do hub. Objetivo: integrar uma vez contra um contrato estável, sem precisar conhecer particularidades de cada provedor bancário. Dor atual: cada produto que integra diretamente com um banco reimplementa retry, idempotência e tratamento de erro do zero.
- **Operador de backoffice**: analista que consulta status de transações, investiga divergências e aciona reprocessamento manual quando necessário. Objetivo: responder "o que aconteceu com a transação X" em segundos, não em uma investigação manual entre bancos de dados. Dor atual: sem visão unificada, precisa de acesso direto (e arriscado) ao banco de produção de cada serviço.
- **Provedor de liquidação**: banco/instituição parceira que efetivamente move o dinheiro e notifica o hub via webhook. Não é usuário direto do hub, mas define restrições de contrato (formato de callback, janela de confirmação) que o hub precisa absorver sem vazar para os integradores.
- **SRE / plantão**: responsável por manter o hub operacional; consome os artefatos de `docs/technical/infrastructure/` e `docs/technical/architecture/observability.md`, não o código de domínio em si.
- **QA**: valida que cada entrega atende ao critério de aceite definido na milestone (`.wiz/<slug>/phases/`, quando o serviço é planejado via o PayFlow SDLC Kit), com base nas diretrizes de `docs/technical/quality/qa-guidelines.md`.

## 3.1 Multi-tenancy

Cada integrador é tratado como um tenant lógico do hub (não há deploy dedicado por cliente). Isso implica: nenhuma query sem filtro por `integratorId`, limites (rate limit, valor) configuráveis por tenant, e nenhum dado de um integrador acessível por outro — ver `docs/technical/architecture/security.md` e `docs/technical/infrastructure/aws-architecture.md` para como isso se reflete em autenticação e infraestrutura.

## 4. Escopo funcional (v1)

| Capacidade | Descrição | Serviço responsável |
|---|---|---|
| Cash-in | Receber ordens de cobrança, gerar cobrança no provedor, aguardar confirmação | `payflow-cashin-service` |
| Cash-out | Receber ordens de pagamento/transferência, submeter ao provedor, tratar liquidação | `payflow-cashout-service` |
| Roteamento de entrada | Autenticação, rate limiting e roteamento das chamadas de integradores | `payflow-gateway` |
| Notificação outbound | Notificar sistemas integradores sobre mudanças de status via webhook, com retry e assinatura HMAC | `payflow-webhook-service` |
| Consistência de eventos | Garantir publicação confiável de eventos de domínio (padrão outbox) | `payflow-outbox-relay` |
| Trilha de auditoria | Registrar todo evento relevante para fins de compliance e investigação | `payflow-audit-service` |
| Operação/backoffice | Consulta de transações, conciliação manual, reprocessamento, métricas operacionais | `payflow-backoffice-api` (+ frontend) |

## 5. Fora de escopo (v1)

- Suporte a múltiplos provedores simultâneos com roteamento por custo/SLA (fica para v2).
- Split de pagamentos entre múltiplos beneficiários.
- Interface de autoatendimento para integradores (onboarding é manual/via time comercial).

## 5.1 Requisitos não funcionais (por prioridade)

| Prioridade | Categoria | Requisito |
|---|---|---|
| P0 — Corretude | Sem duplicidade de movimentação sob nenhuma condição de retry/rede | Ver seção 7 (riscos) e `docs/technical/guidelines/error-handling.md` |
| P1 — Testes | Regressão impossível em regra de máquina de estados sem quebrar CI | Ver `docs/technical/ci-cd.md` e `docs/technical/quality/qa-guidelines.md` |
| P2 — Segurança | Toda borda de entrada autenticada; nenhum dado sensível em log | Ver `docs/technical/architecture/security.md`, `docs/technical/guidelines/logging.md` |
| P3 — Qualidade | Código revisável isoladamente por commit; ADR para toda decisão relevante | Ver `docs/technical/guidelines/coding-standards.md`, `docs/decisions/` |
| P4 — Performance | Latência e throughput dentro do SLO por serviço | Ver `docs/technical/architecture/observability.md` |

## 6. Métricas de sucesso

- Latência p95 de confirmação de cash-in abaixo de 200ms.
- 100% das transações com trilha de auditoria completa (nenhum evento perdido).
- Zero divergência não detectada entre o status interno e o status no provedor (garantido por conciliação periódica).

## 7. Riscos conhecidos

- **Duplicidade de processamento**: mitigado por idempotência em todos os endpoints de entrada (chave de idempotência obrigatória).
- **Eventos fora de ordem**: mitigado por máquina de estados explícita por transação, que rejeita transições inválidas.
- **Falha de entrega de webhook**: mitigado por fila de retry com backoff exponencial e dead-letter queue.
