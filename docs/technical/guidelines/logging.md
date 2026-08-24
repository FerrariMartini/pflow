# Guideline — Logging

## Formato

Todo log é um objeto JSON de uma linha (nunca `console.log`/`fmt.Println` de string livre em código de produção), com campos mínimos obrigatórios:

```json
{
  "timestamp": "2026-08-23T14:02:11.482Z",
  "level": "info",
  "service": "payflow-backoffice-api",
  "correlationId": "corr-...",
  "message": "reconciliation.updated"
}
```

## Níveis

| Nível | Quando usar |
|---|---|
| `error` | Falha que impede a operação de completar; sempre acionável (gera alerta se em produção). |
| `warn` | Situação anômala mas recuperável (ex: retry de webhook antes de esgotar tentativas). |
| `info` | Evento de negócio relevante (transação criada, conciliação registrada) — não é "log de debug", é o rastro operacional. |
| `debug` | Detalhe técnico útil só em investigação ativa; desligado por padrão em produção. |

## O que nunca logar

- Dado sensível de titular (documento, dados bancários completos) — ver `docs/technical/architecture/security.md`.
- Corpo bruto de requisição/resposta contendo segredo (assinatura HMAC, token de autenticação).
- Erro técnico com stack trace em nível `info` — stack trace só em `error`, e só em log interno (nunca na resposta HTTP).

## correlationId é obrigatório

Qualquer log dentro do ciclo de vida de uma transação carrega `correlationId` — sem isso, uma investigação de incidente vira grep manual em vários serviços sem forma de juntar as pontas (ver `docs/technical/architecture/observability.md`). Log sem `correlationId` em um contexto que já tem um disponível é considerado defeito, não estilo.

## Amostragem

Logs em nível `info` de alto volume (ex: heartbeat de consumidor saudável) usam amostragem (ex: 1 a cada N) para não afogar o índice de busca — mas qualquer log de mudança de estado de transação nunca é amostrado, é sempre 100%.
