# Contratos de API — visão geral

Contratos completos de cada serviço vivem em `services/<serviço>/README.md`. Este documento cobre apenas as convenções compartilhadas por todos os endpoints do hub.

## Protocolo por trecho da comunicação

O contrato externo (integrador → hub) é sempre REST. O protocolo interno (gateway → serviço de domínio) varia por serviço — ver `docs/technical/architecture/overview.md`, seção "Por que cash-in é síncrono e cash-out é assíncrono", para o raciocínio completo:

| Trecho | Protocolo | Natureza |
|---|---|---|
| Integrador → `payflow-gateway` | REST (HTTPS + HMAC) | — |
| `payflow-gateway` → `payflow-cashin-service` | gRPC (proto em `docs/contract/`) | Síncrono |
| `payflow-gateway` → `payflow-cashout-service` | Comando Kafka (`payflow.cashout.command.v1`) | Assíncrono |
| `payflow-gateway` → `payflow-backoffice-api` | REST | Síncrono |

## Convenções REST

- Todo endpoint de comando (POST) que cria/altera estado exige header `Idempotency-Key` (string, UUID recomendado).
- Toda requisição de integrador é autenticada via assinatura HMAC-SHA256 no header `X-Signature`, calculada sobre o corpo bruto da requisição com a chave secreta do integrador.
- Erros seguem o formato:
  ```json
  {
    "error": {
      "code": "TRANSACTION_ALREADY_CONFIRMED",
      "message": "Transação já confirmada, não é possível reprocessar.",
      "correlationId": "..."
    }
  }
  ```
- Versionamento de contrato via prefixo de path (`/v1/...`); mudanças breaking exigem novo prefixo, nunca alteração in-place de um contrato já publicado. Todo bump de versão de contrato é um `BREAKING CHANGE` no changelog do serviço e política de deprecação — ver `docs/technical/versioning.md`.

## Convenções de eventos (Kafka)

- Nome do tópico: `payflow.<dominio>.<evento>` (ex: `payflow.cashin.confirmed`).
- Todo evento carrega `eventId`, `correlationId`, `occurredAt`, `payload`.
- Consumidores devem ser idempotentes em relação a `eventId` (at-least-once delivery).

## Convenção de comando (Kafka) — diferente de evento

`payflow.cashout.command.v1` não é um evento de domínio (não representa algo que já aconteceu) — é um **comando**: uma instrução para o `payflow-cashout-service` executar. Por isso o nome usa `.command.` em vez do padrão `<dominio>.<evento>` acima. Carrega os mesmos campos base (`eventId` aqui funciona como `commandId`, `correlationId`, `occurredAt`, `payload`) mais o `Idempotency-Key` recebido do integrador, usado pelo consumidor para deduplicar antes de processar.
