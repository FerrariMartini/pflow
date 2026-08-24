# Phase 11: Trilha de Auditoria Consultável para Compliance

**Duration**: ~2 days (18 milestones @ 1h each)
**Dependencies**: Phase 7 (read model), Phase 4 (RBAC)
**Status**: 🚧 TODO

## Goal

Entregar a consulta da trilha de auditoria financeira (`src/audit/`), lendo o `transaction_audit_ledger` — ledger cronológico append-only escrito exclusivamente pelo `audit-worker` via Kafka — sem confundi-lo com o `backoffice_audit_log` de ações administrativas da Fase 4.

Entregas principais:
- `GET /api/audit/transactions/:id`: histórico cronológico completo de uma transação (cash-in ou cash-out).
- `GET /api/audit`: trilha de eventos com filtros de período, tipo, tenant e direção, paginada.
- Repository estritamente read-only sobre `transaction_audit_ledger` (nenhum caminho de escrita exposto pelo `backoffice-api`).
- Escopo por `user.tenant_ids` e RLS aplicados também na trilha.
- Índices de consulta por transação, período e tenant.

## Phase Acceptance Criteria

- Ambos os endpoints são restritos a ADMIN e COMPLIANCE, negando OPERATIONS, FINANCE e SUPPORT — cobertos por e2e.
- `AuditLedgerRepository` não expõe nenhum método de escrita, e um teste de integração prova que o usuário de banco do backoffice não consegue INSERT/UPDATE/DELETE em `transaction_audit_ledger`.
- O histórico de uma transação retorna os eventos em ordem cronológica estável por `occurredAt` e desempate determinístico, incluindo o caso de eventos com o mesmo timestamp — caso de borda com teste.
- Consulta de transação de tenant fora de `user.tenant_ids` retorna 403/vazio conforme o contrato definido, nunca dados de outro tenant (P0).
- Todos os filtros de `GET /api/audit` funcionam isolados e combinados; transação inexistente retorna `DomainError` tipado `TRANSACTION_NOT_FOUND`, com teste.
- Resposta respeita o masking de PII do interceptor global, inclusive nos payloads históricos do ledger.
- Cobertura ≥ 90% em `AuditService` e no repository; `scripts/pre-commit.sh` verde.
- `docs/contract/contract.md` atualizado com os dois endpoints e a distinção entre os dois ledgers documentada no README do serviço.

## Milestones

<!-- Milestones appended by /wiz-milestones -->
