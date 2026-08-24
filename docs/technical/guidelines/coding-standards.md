# Padrões de código

Este documento define o boilerplate técnico (versões, lint, format, estrutura) para os dois grupos de subprojeto do hub. Para tópicos com guideline dedicada, ver:

- Injeção de dependência: `docs/technical/guidelines/dependency-injection.md`
- Tratamento de erros: `docs/technical/guidelines/error-handling.md`
- Logging: `docs/technical/guidelines/logging.md`
- Gates de CI/CD (cobertura mínima, lint, segurança): `docs/technical/ci-cd.md`
- Estratégia de teste (pirâmide, Definition of Done): `docs/technical/quality/qa-guidelines.md`

## CORE — serviços de domínio em Go

Grupo: `payflow-gateway`, `payflow-cashin-service`, `payflow-cashout-service`, `payflow-webhook-service`, `payflow-outbox-relay`, `payflow-audit-service`.

| Item | Padrão |
|---|---|
| Linguagem | Go 1.25 |
| Lint | `golangci-lint` v2, linters habilitados: `errcheck`, `govet`, `staticcheck`, `gosec`, `revive`, `exhaustive` (switch sobre enum de domínio precisa ser exaustivo — pega `TransactionStatus`/`ReconciliationStatus` incompletos em compile-time de lint, não em produção) |
| Format | `gofmt`/`goimports`, sem configuração adicional — zero debate de estilo |
| Testes | `testing` da standard library + `testify` (`require`/`assert`) para asserts legíveis; tabela de casos (`t.Run` por cenário) para regra de máquina de estados |
| Estrutura | `cmd/` (entrypoint) · `internal/domain` · `internal/usecase` · `internal/adapter` (arquitetura hexagonal, ver `dependency-injection.md`) · `migrations/` quando o serviço tem banco próprio |
| Timeout de lint em CI | 5 min (ver `docs/technical/ci-cd.md`) |

Arquitetura hexagonal: `internal/{domain,usecase,adapter}`, domínio sem dependência de framework ou driver externo (sem import de biblioteca de HTTP/Kafka dentro de `domain`) — regra reforçada pelo lint de arquitetura no CI, não só por convenção documentada. Erros de negócio como tipos sentinela (`var ErrX = errors.New(...)`), nunca `panic` em fluxo de negócio (ver `error-handling.md`). `context.Context` como primeiro parâmetro em toda função que atravessa I/O — obrigatório para propagação de `correlationId`/deadline. Nomes de pacote curtos e sem redundância (`cashin`, não `cashinpackage`); sem pacote `utils`/`common` genérico acumulando funções não relacionadas.

## Backoffice — `payflow-backoffice-api`

| Item | Padrão |
|---|---|
| Runtime | Node.js 24.x |
| Framework | NestJS 11 |
| Linguagem | TypeScript 5.6, `strict: true` |
| Lint | ESLint 9, flat config (`eslint.config.mjs`) via `typescript-eslint` 8 — ver regras abaixo |
| Format | Prettier: `singleQuote`, `trailingComma: all`, `semi: true`, `printWidth: 100`, `tabWidth: 2` |
| Commit hooks | `husky` (`commit-msg`) + `commitlint` (`@commitlint/config-conventional`) — Conventional Commits é **enforçado no commit**, não só documentado |
| Testes | Jest (unit) + `supertest` (e2e) |
| Estrutura | `src/modules/<dominio>/{controller,service,dto,entities}` |

Regras de lint específicas (motivo de cada uma, não só a lista):
- `@typescript-eslint/no-explicit-any`: `warn` (não `error`) — NestJS usa `any` em alguns pontos de framework; vira sinal de revisão, não bloqueio automático.
- `@typescript-eslint/explicit-function-return-type` e `explicit-module-boundary-types`: `off` — decorators do NestJS já tornam o tipo de retorno óbvio/verboso de anotar.
- `@typescript-eslint/no-unused-vars`: `error`, com `argsIgnorePattern: '^_'` (permite parâmetro não usado explicitamente prefixado com `_`, comum em assinatura de handler).
- `no-console`: `warn` — usar o logger estruturado (`docs/technical/guidelines/logging.md`), não `console.log`.
- `prefer-const`, `no-var`, `object-shorthand`, `prefer-arrow-callback`: `error` — sem debate, são substituições mecânicas sem trade-off.

DTOs de entrada validados com `class-validator`; nunca confiar em payload não validado dentro da camada de serviço. Serviços não conhecem detalhes de HTTP — isso fica exclusivamente no controller. Erros de domínio usam exceções tipadas (`class X extends DomainError`), nunca `throw new Error(string)` genérico (ver `error-handling.md`).

## Geral (ambos os grupos)

### Idioma

| Artefato | Idioma |
|---|---|
| Código: identificadores, comentários, descrições de teste, mensagens de erro | Inglês |
| Mensagens de commit e changelog | Inglês |
| Agentes e comandos em `.claude/` | Inglês |
| Documentação em `docs/`, notas de review, retrospectivas | Português |

Código e histórico são artefatos técnicos de alcance aberto — ferramentas, bibliotecas e quem der manutenção depois esperam inglês. A documentação de processo é escrita para o time que a lê no dia a dia.

### Demais convenções

- Commits seguem [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`, com escopo entre parênteses referenciando o serviço (`feat(backoffice-api): ...`).
- Nenhum segredo, credencial ou dado real em código, commit ou documentação.
- Toda decisão arquitetural relevante vira ADR antes da implementação, não depois (`docs/decisions/`).
- Nenhuma mudança de contrato de API/evento sem atualizar `docs/contract/contract.md` no mesmo PR.
