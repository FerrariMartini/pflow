# Arquitetura — Segurança

## Modelo de ameaças (resumo)

O hub processa movimentação financeira, então o modelo de ameaça prioriza: (1) forjar/alterar uma transação, (2) reproduzir uma transação legítima (replay), (3) escalar privilégio para operações administrativas, (4) vazar dados de transação em trânsito ou em log.

## Autenticação e autorização

- **Integrador → Gateway**: assinatura HMAC-SHA256 sobre o corpo bruto da requisição (`X-Signature`), com segredo por integrador, rotacionável sem downtime (dois segredos válidos simultaneamente durante a rotação).
- **Serviço → Serviço**: mTLS na malha interna (todos os serviços atrás do `payflow-gateway` confiam apenas em certificados emitidos pela CA interna do cluster).
- **Backoffice (operador humano)**: OIDC contra o provedor de identidade da empresa; o token carrega `role` (ex: `operator`, `auditor`) usado para autorização por endpoint no `payflow-backoffice-api`.
- **Sem princípio de confiança implícita entre serviços**: mesmo dentro da rede interna, cada serviço valida o `correlationId`/claims recebidos, não assume que "veio da rede interna" é suficiente.

## Idempotência como controle de segurança (não só de confiabilidade)

`Idempotency-Key` obrigatório em toda operação de escrita não é só proteção contra falha de rede — é também mitigação de replay: uma tentativa de reenviar uma requisição capturada não gera uma segunda cobrança/pagamento.

## Proteção de dados

- Nenhum dado sensível (documento do titular, dados bancários completos) é logado — logs carregam apenas identificadores internos (`transactionId`, `correlationId`, `integratorId` mascarado).
- Dados em repouso: criptografia at-rest no banco de cada serviço; dados em trânsito: TLS 1.2+ em todas as bordas, mTLS internamente.
- Segredos (chaves HMAC, credenciais de banco) nunca em variável de ambiente em texto plano em produção — vêm de um secrets manager, injetados em runtime.

## Auditoria como controle de segurança

`payflow-audit-service` existe tanto para conciliação operacional quanto como controle de segurança: qualquer alteração de estado de transação é rastreável a um evento de origem, o que é pré-requisito para investigação de incidente e para compliance (trilha não pode ser alterada nem pelo time de operação).

## Superfícies revisadas por serviço

| Serviço | Superfície crítica | Controle principal |
|---|---|---|
| `payflow-gateway` | Entrada externa | HMAC + rate limiting |
| `payflow-cashin-service` / `payflow-cashout-service` | Movimentação de valor | Idempotência + máquina de estados |
| `payflow-webhook-service` | Saída para terceiros | Assinatura do payload, sem expor dados além do necessário |
| `payflow-backoffice-api` | Ação humana privilegiada | OIDC + RBAC por endpoint |
| `payflow-audit-service` | Trilha de verdade | Append-only, sem update/delete |
