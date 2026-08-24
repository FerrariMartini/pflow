# ADR-0001: Microsserviços orientados a eventos, com padrão outbox

**Status**: Aceito

## Contexto

O hub precisa integrar múltiplos serviços internos (cash-in, cash-out, webhook, auditoria, backoffice) que evoluem em ritmos diferentes e têm requisitos de disponibilidade distintos (ex: falha no serviço de auditoria não pode derrubar o cash-in). Também precisamos garantir que nenhuma transação "desapareça" entre a confirmação de um pagamento e a notificação dos sistemas interessados.

## Alternativas consideradas

1. **Monólito modular**: mais simples de operar no início, mas acopla o ciclo de deploy de todos os domínios e não isola falhas.
2. **Microsserviços com chamadas síncronas (REST/gRPC) entre si**: mais simples de raciocinar, mas cria acoplamento temporal — se `webhook-service` estiver fora do ar, `cash-in` não poderia depender dele para confirmar uma transação.
3. **Microsserviços orientados a eventos (Kafka) com padrão outbox**: desacopla os serviços no tempo; cada serviço reage a eventos de domínio sem depender da disponibilidade imediata dos consumidores.

## Decisão

Adotar a opção 3. Cada serviço de domínio publica eventos através do padrão outbox (escreve o evento pendente na mesma transação de banco que a mudança de estado; um relay dedicado — `outbox-relay` — garante a publicação em Kafka).

## Consequências

- Prós: falhas em serviços consumidores (webhook, auditoria) não bloqueiam o fluxo principal de pagamento; cada serviço escala e faz deploy independentemente.
- Contras: consistência é eventual, não imediata — a UI de backoffice pode levar alguns segundos para refletir o estado mais recente. Aceitável dado que não há requisito de consistência forte para consulta operacional.
- Exige investimento em observabilidade (correlation_id de ponta a ponta) para não perder rastreabilidade ao trocar chamada síncrona por eventos.
