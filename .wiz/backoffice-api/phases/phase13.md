# Phase 13: Endurecimento, Cobertura Total e Prontidão de Deploy

**Duration**: ~3 days (26 milestones @ 1h each)
**Dependencies**: Phase 12 (todas as fases anteriores)
**Status**: 🚧 TODO

## Goal

Fechar o V1 elevando o serviço inteiro ao Definition of Done de `docs/technical/quality/qa-guidelines.md` e aos gates de `docs/technical/ci-cd.md` — cobrindo o que as fases individuais não têm como cobrir sozinhas: caminhos e2e ponta a ponta, fuzzing das áreas críticas, benchmarks dos hot spots, scan de segurança e a imagem de produção.

Esta fase é de consolidação, não de adiamento: os gates de lint, teste e cobertura já rodam verdes desde a Fase 1.

Entregas principais:
- Suíte e2e dos caminhos críticos completos: login com 2FA → consulta de depósitos → ajuste de balanceamento → propagação Redis → evento SSE recebido.
- Fechamento de cobertura para ≥ 90% global e nas classes de regra de negócio, ≥ 85% em controllers, com o threshold falhando o build.
- Fuzzing das áreas críticas do §13: DTOs de input (`LoginDto`, `CreateUserDto`, `UpdateBalancingDto`), parsing do envelope de evento Kafka e parsing/validação de token de auth.
- Benchmarks dos hot spots: throughput do consumer Kafka, listagem paginada sob carga e latência de escrita Redis na propagação de config.
- `Dockerfile` de produção multi-stage, imagem versionada por SHA do commit (nunca `:latest`) com SBOM anexado.
- Pipeline Bitbucket completo: Build → Lint → Test → Migration Check → Scan (`npm audit` + scan de imagem) → Build Image → Deploy, com cada estágio como gate bloqueante.
- README do serviço com o contrato de uso do dev seed para os outros times (§16.5) e a documentação de troubleshooting do resync Redis.
- Sessão de teste exploratório roteirizada por risco antes da promoção, focada em payload malformado e UX de erro.

## Phase Acceptance Criteria

- `scripts/pre-commit.sh` passa verde em checkout limpo, e o pipeline completo de CI passa em todos os estágios sem exceção manual.
- Cobertura global ≥ 90% (branches, functions, lines, statements), services e repositories ≥ 90%, controllers ≥ 85% — thresholds configurados de forma que a regressão falhe o build, não apenas apareça no relatório.
- Zero teste falhando e zero teste marcado como `skip`/`todo` em toda a suíte; zero erro de lint em todo o serviço.
- Os quatro fluxos e2e críticos passam contra a stack containerizada real (Postgres × 2, Redpanda, Valkey, LocalStack, MailHog), sem mock do próprio serviço.
- Fuzzing das três áreas do §13 roda em CI e nenhuma entrada malformada causa 500 não tratado, crash do processo ou trava de partição Kafka.
- Benchmarks dos três hot spots executam e registram baseline no repositório; p95 de listagem paginada < 500ms, lag de consumer < 5s e latência SSE < 2s são atendidos.
- `npm audit` e o scan de imagem retornam zero vulnerabilidade `critical`/`high` sem exceção aprovada com prazo documentado.
- Imagem de produção builda multi-stage, é taggeada pelo SHA do commit e tem SBOM anexado; migration dry-run passa contra um banco limpo.
- Todo endpoint do §8 do PRD está documentado no Swagger e refletido em `docs/contract/contract.md`; o README do serviço permite a outro time subir a stack seguindo apenas as instruções escritas.

## Milestones

<!-- Milestones appended by /wiz-milestones -->
