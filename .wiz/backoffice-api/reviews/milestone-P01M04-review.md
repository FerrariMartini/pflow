# Milestone Review: P01M04

**Title**: Configurar Husky, commitlint e lint-staged  
**PRD**: backoffice-api  
**Phase**: 1  
**Date**: 2026-08-27  
**Auditor**: wiz-reviewer

## Summary

O P01M04 entrega o gate de commit local exigido pelo §14 do PRD: Husky 9 com hooks `commit-msg` e `pre-commit`, commitlint estendendo Conventional Commits com escopo obrigatório `backoffice-api`, e lint-staged aplicando ESLint `--fix` + Prettier nos `*.ts` staged. Os cinco critérios de aceite foram verificados por inspeção de arquivo e por execução — inclusive a rejeição de `atualiza coisas` e a aceitação de `feat(backoffice-api): add scaffold`. O `prepare` script está correto para monorepo (`cd ../.. && husky services/payflow-backoffice-api/.husky`), `core.hooksPath` aponta para `.husky/_`, e o README documenta ativação e formato de commit. Todos os gates do codebase passam verde; nenhum teste falha ou é pulado; zero erros de lint.

Débito registrado (fora do escopo explícito desta milestone): o PRD §14 descreve pre-commit como `lint-staged + npm test (affected files)`, mas o hook Husky implementado roda apenas lint-staged — testes continuam no `scripts/pre-commit.sh` manual/CI. Isso não viola os critérios do P01M04, mas permanece como lacuna frente ao gate P1 completo do PRD.

## Acceptance Criteria Verification

### ✅ Criterion 1: `husky` instalado com hook `commit-msg` executando `commitlint --edit`

**Status**: Met  
**Evidence**:
- `package.json:43` — `"husky": "^9.1.7"` em `devDependencies`
- `package.json:11` — `"prepare": "cd ../.. && husky services/payflow-backoffice-api/.husky"` (monorepo-aware)
- `.husky/commit-msg:1-2` — `cd` para o diretório do serviço, depois `npx --no -- commitlint --edit "$1"`
- `git config core.hooksPath` → `services/payflow-backoffice-api/.husky/_` (Husky 9 wrapper)
- Commit `3875902 feat(backoffice-api): configure Husky, commitlint, and lint-staged`

**Notes**:
- O flag `--no` em `npx --no -- commitlint` impede instalação implícita de pacote ausente — boa prática de segurança/reprodutibilidade.
- O `cd "$(dirname "$0")/.."` garante que commitlint e lint-staged rodem com CWD correto dentro do monorepo.

---

### ✅ Criterion 2: `commitlint.config.js` estende `@commitlint/config-conventional` e exige escopo referenciando o serviço

**Status**: Met  
**Evidence**:
- `commitlint.config.js:5` — `extends: ['@commitlint/config-conventional']`
- `commitlint.config.js:1` — `allowedScopes = ['backoffice-api']`
- `commitlint.config.js:7-8` — `scope-empty: [2, 'never']`, `scope-enum: [2, 'always', allowedScopes]`
- `package.json:39-40` — `@commitlint/cli` e `@commitlint/config-conventional` declarados

**Verificação adicional de escopo** (além do critério mínimo):
- `feat(wrong-scope): test` → rejeitado (`scope must be one of [backoffice-api]`, exit 1)
- `feat: no scope` → rejeitado (`scope may not be empty`, exit 1)

---

### ✅ Criterion 3: Hook `pre-commit` executa `lint-staged` com `eslint --fix` e `prettier --write` em `*.ts`

**Status**: Met  
**Evidence**:
- `.husky/pre-commit:1-2` — `cd` para diretório do serviço, `npx lint-staged`
- `package.json:45` — `"lint-staged": "^15.3.0"`
- `package.json:54-56`:
  ```json
  "lint-staged": {
    "*.ts": ["eslint --fix", "prettier --write"]
  }
  ```

---

### ✅ Criterion 4: Verificado que `atualiza coisas` é rejeitada e `feat(backoffice-api): add scaffold` é aceita

**Status**: Met  
**Evidence** (executado em `services/payflow-backoffice-api/`):

```bash
echo "atualiza coisas" | npx commitlint
# exit 1 — subject-empty, type-empty, scope-empty

echo "feat(backoffice-api): add scaffold" | npx commitlint
# exit 0 — aceita
```

---

### ✅ Criterion 5: Instruções de ativação dos hooks documentadas no README do serviço

**Status**: Met  
**Evidence**:
- `README.md:16-17` — `npm install` dispara `prepare`, que configura Husky
- `README.md:22-28` — reativação via `npm install` ou `npm run prepare` se hooks não rodarem
- `README.md:30-35` — tabela descrevendo `pre-commit` (lint-staged) e `commit-msg` (commitlint)
- `README.md:37-46` — formato `<type>(backoffice-api): <description>` com exemplos
- `README.md:60-62` — distinção entre gates do monorepo (`scripts/pre-commit.sh`) e hooks locais

---

## Gates Executed

| Gate | Comando | Exit | Resultado |
|---|---|---|---|
| Lint | `npm run lint` | **0** | 0 erros, 1 warning pré-existente (`no-console` em `main.ts:13`) |
| Format | `npm run format:check` | **0** | All matched files use Prettier code style |
| Test (unit) | `npm test` | **0** | 1 suíte / 1 teste passed, 0 failed, 0 skipped |
| Test (e2e) | `npm run test:e2e` | **0** | 1 suíte / 1 teste passed, 0 failed, 0 skipped |
| Pre-commit (monorepo) | `scripts/pre-commit.sh` | **0** | lint → build → test → e2e, todos verdes |
| Commitlint (reject) | `echo "atualiza coisas" \| npx commitlint` | **1** | 3 violations (type/subject/scope empty) |
| Commitlint (accept) | `echo "feat(backoffice-api): add scaffold" \| npx commitlint` | **0** | Aceita |
| Hooks path | `git config core.hooksPath` | — | `services/payflow-backoffice-api/.husky/_` |

**Regressões no restante do codebase**: nenhuma.

## Code Quality Assessment

**Rating**: Good (⭐⭐⭐⭐)

**Findings**:
- ✅ Dependências corretas e versionadas: `husky`, `@commitlint/*`, `lint-staged`
- ✅ Configuração commitlint mínima e focada — escopo único `backoffice-api`, alinhado a `coding-standards.md:63`
- ✅ Hooks Husky enxutos; `cd` para CWD do serviço evita falhas silenciosas no monorepo
- ✅ `prepare` script aponta para raiz do repo antes de invocar `husky` — padrão correto para monorepo
- ✅ README claro, em inglês (código/docs de serviço), com tabela de hooks e exemplos de commit
- ✅ Mensagem de commit do milestone (`3875902`) segue o próprio padrão enforçado
- ⚠️ Pre-commit Husky não executa testes — apenas lint-staged (ver débito PRD §14 abaixo)
- ⚠️ Warning `no-console` em `main.ts:13` persiste (pré-existente, não introduzido por P01M04)

## NFR Compliance

- **P0 (Correctness)**: ✅ Met — hooks configurados corretamente; commitlint rejeita mensagens inválidas; lint-staged aponta para comandos corretos
- **P1 (Tests)**: ✅ Met — suíte existente passa; nenhum teste falha ou skip. Nota: testes não rodam no hook Husky pre-commit (lacuna vs PRD §14, não vs critérios P01M04)
- **P2 (Security)**: ✅ Met — `--no` no npx impede install arbitrário; nenhum segredo nos hooks/config; commitlint impede mensagens fora do padrão (rastreabilidade)
- **P3 (Quality)**: ✅ Met — config legível, README documentado, zero erros de lint, format check verde
- **P4 (Performance)**: ✅ Met / N/A — hooks leves (lint-staged só em arquivos staged)

## Recommendations

### High Priority
_Nenhum item bloqueante para P01M04._

### Medium Priority
1. **Adicionar `npm test` ao hook `pre-commit` Husky** — o PRD §14 (`prd.md:764-766`, `prd.md:847`) descreve `lint-staged + npm test (affected files)`. Hoje testes rodam apenas via `scripts/pre-commit.sh` (manual/CI). Considerar milestone dedicado ou extensão do pre-commit quando Jest/coverage thresholds (P01M05) estiverem estáveis.
2. **Resolver warning `no-console` em `main.ts:13`** — será naturalmente endereçado quando P01M10 entregar logger estruturado; até lá, o warning aparece em todo lint.

### Low Priority
1. **Documentar variável `HUSKY=0`** no README para bypass temporário em emergências (Husky 9 suporta via `.husky/_/h:14`).
2. **Considerar `lint-staged` com glob mais explícito** (`"{src,test}/**/*.ts"`) se arquivos `.ts` forem adicionados fora dessas pastas no futuro — hoje `*.ts` na raiz do serviço é suficiente.

## Overall Assessment

**Pass**: ✅

Os cinco critérios de aceite do P01M04 são verdadeiros e foram verificados por inspeção e execução. Commitlint rejeita mensagens fora do padrão e aceita o formato com escopo `backoffice-api`. Husky está instalado com hooks funcionais no contexto monorepo. Lint-staged aplica ESLint `--fix` e Prettier `--write` em `*.ts`. README documenta ativação e convenção de commit. Todos os gates do codebase passam: zero erros de lint, zero testes falhando ou pulados, `scripts/pre-commit.sh` verde.

Débito aceito: pre-commit Husky não inclui testes, conforme descrito no PRD §14 mas fora do escopo explícito desta milestone. Recomenda-se endereçar em milestone futuro sem bloquear P01M04.
