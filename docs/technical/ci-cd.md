# CI/CD — pipeline e critérios de qualidade

## Estágios do pipeline (todo serviço)

```
lint → build → test unitário → test de integração/e2e → scan de segurança → build de imagem → deploy (dev → staging → prod)
```

Cada estágio é um **gate**: falha em qualquer um bloqueia o avanço para o próximo. Não existe "merge com CI vermelho e conserta depois" — se o gate falhou, o PR não é elegível para merge.

## Critérios por estágio

### 1. Lint / análise estática
- **Critério de aceite**: zero erros. Warning é aceitável para itens já rastreados como débito técnico explícito; novo código não pode introduzir warning novo sem justificativa no PR.
- Node/TS: ESLint + Prettier (`npm run lint`). Go: `golangci-lint` com regra de arquitetura customizada barrando import de infraestrutura dentro de `internal/domain` (ver `docs/technical/guidelines/dependency-injection.md`).

### 2. Build
- **Critério de aceite**: build reprodutível a partir de um checkout limpo, sem dependência de estado local da máquina do desenvolvedor (nada de "funciona na minha máquina").

### 3. Testes unitários
- **Critério de aceite**: cobertura mínima de 80% em `internal/domain`/`internal/usecase` (Go) e em `src/modules/*/[!.]*.service.ts` (Node) — regra de negócio, não boilerplate de framework. Cobertura de linha em código de infraestrutura (adapters, controllers finos) não é gate, é indicador.
- Todo `DomainError` novo precisa de teste cobrindo o caminho que o dispara (ver `docs/technical/guidelines/error-handling.md`).

### 4. Testes de integração / e2e
- **Critério de aceite**: suíte e2e sobe o serviço completo (sem mock do próprio serviço) contra dependências reais ou containerizadas (Postgres/Kafka via `docker-compose` em CI); serviços com contrato de evento têm teste de contrato validando schema publicado/consumido.

### 5. Scan de segurança
- **Critério de aceite**: zero vulnerabilidade `critical`/`high` sem exceção aprovada explicitamente (com prazo de remediação); scan de dependências (`npm audit`/`govulncheck`) e scan de imagem de container antes do push para o registry.

### 6. Build e push de imagem
- Imagem versionada por SHA do commit (nunca `:latest` em deploy), com SBOM gerado e anexado ao artefato.

### 7. Deploy progressivo
- `dev` automático a cada merge na branch principal → `staging` automático após smoke test em `dev` → `prod` com aprovação manual (para serviços que movimentam valor: `cashin`, `cashout`) ou automático com canary + rollback automático por métrica (para serviços sem essa criticidade, ex: `audit-service`).
- **Critério de rollback automático**: taxa de erro > 1% ou latência p95 acima do SLO (ver `docs/technical/architecture/observability.md`) nos primeiros 10 minutos após deploy dispara rollback automático, sem esperar intervenção humana.

## Branch e PR

- Sem push direto na branch principal — todo código entra via PR.
- PR exige: 1 aprovação humana + todos os gates acima verdes. Para os serviços que movimentam valor (`cashin`, `cashout`, `gateway`), exige 2 aprovações.
- Commits seguem Conventional Commits (ver `docs/technical/guidelines/coding-standards.md`), o que alimenta o changelog automático por serviço — ver `docs/technical/versioning.md` para o mapeamento commit → versão → changelog e a ferramenta usada.
