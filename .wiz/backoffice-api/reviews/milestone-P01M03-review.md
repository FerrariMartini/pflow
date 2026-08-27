# Milestone Review: P01M03

**Title**: Configurar ESLint 9 flat config e Prettier  
**PRD**: backoffice-api  
**Phase**: 1  
**Date**: 2026-08-27  
**Auditor**: wiz-reviewer

## Summary

O milestone P01M03 entrega a configuração de lint e format exigida pela guideline do repositório. O `eslint.config.mjs` aplica flat config com `typescript-eslint` 8, aponta `parserOptions.project` para `tsconfig.json`, configura exatamente as sete regras nominais (mais `eslint-config-prettier` por último), e o `.prettierrc` espelha o padrão documentado. Os scripts `npm run lint` e `npm run format:check` passam verde; a regra `no-var` foi confirmada com arquivo temporário (`var x = 1` → exit 1). O débito D2 do P01M01 (lint fictício) está resolvido. Aprovado.

## Acceptance Criteria Verification

### ✅ Criterion 1: `eslint.config.mjs` flat config com `typescript-eslint` 8 type-aware apontando para `tsconfig.json`

**Status**: Met  
**Evidence**:
- File: `services/payflow-backoffice-api/eslint.config.mjs:1-36` — flat config via `tseslint.config()`, import de `@eslint/js`, `typescript-eslint` e `eslint-config-prettier`.
- File: `eslint.config.mjs:12-16` — `parserOptions.project: './tsconfig.json'`, `tsconfigRootDir: import.meta.dirname`.
- File: `package.json:41-42,52` — `eslint: ^9.17.0`, `typescript-eslint: ^8.18.2`.
- Lockfile: `typescript-eslint@8.67.0` instalado (`package-lock.json`).

**Nota**: A config usa `tseslint.configs.recommended` (não `recommendedTypeChecked`). Isso é coerente com o goal do milestone ("sem regras extras"): as regras exigidas não dependem de type-checking avançado. A infraestrutura type-aware (`project` + `tsconfigRootDir`) está presente para regras futuras.

---

### ✅ Criterion 2: Regras exatas configuradas

**Status**: Met  
**Evidence** (`eslint.config.mjs:18-33`):

| Regra | Esperado | Configurado |
|---|---|---|
| `@typescript-eslint/no-explicit-any` | `warn` | `warn` ✅ |
| `@typescript-eslint/explicit-function-return-type` | `off` | `off` ✅ |
| `@typescript-eslint/explicit-module-boundary-types` | `off` | `off` ✅ |
| `@typescript-eslint/no-unused-vars` | `error`, `argsIgnorePattern: '^_'` | `error`, `argsIgnorePattern: '^_'` ✅ |
| `no-console` | `warn` | `warn` ✅ |
| `prefer-const` | `error` | `error` ✅ |
| `no-var` | `error` | `error` ✅ |
| `object-shorthand` | `error` | `error` ✅ |
| `prefer-arrow-callback` | `error` | `error` ✅ |

**Verificação dinâmica** (arquivo temporário `src/_rule-test.ts`):
```
1:25  warning  Unexpected any          @typescript-eslint/no-explicit-any
2:3   warning  Unexpected console statement  no-console
3:3   error    Unexpected var, use let or const instead  no-var
```

Alinhamento com `docs/technical/guidelines/coding-standards.md:39-44` — regras e severidades idênticas, incluindo a justificativa documentada para `no-explicit-any: warn` e `explicit-*: off`.

---

### ✅ Criterion 3: `.prettierrc` com opções exatas

**Status**: Met  
**Evidence** (`services/payflow-backoffice-api/.prettierrc`):

```json
{
  "singleQuote": true,
  "trailingComma": "all",
  "semi": true,
  "printWidth": 100,
  "tabWidth": 2
}
```

Corresponde a `docs/technical/guidelines/coding-standards.md:34` e `coding-standards.md:34` (Backoffice — Format).

---

### ✅ Criterion 4: `eslint-config-prettier` aplicado por último na cadeia

**Status**: Met  
**Evidence**: `eslint.config.mjs:35` — `eslintConfigPrettier` é o último argumento de `tseslint.config(...)`, após `eslint.configs.recommended`, `tseslint.configs.recommended` e o bloco de regras customizadas.

---

### ✅ Criterion 5: `npm run lint` e `npm run format:check` passam verde

**Status**: Met  
**Evidence** (execução em 2026-08-27):

**`npm run lint`** — exit 0:
```
/home/.../src/main.ts
  13:3  warning  Unexpected console statement  no-console

✖ 1 problem (0 errors, 1 warning)
```

**`npm run format:check`** — exit 0:
```
Checking formatting...
All matched files use Prettier code style!
```

Scripts em `package.json:16-18`:
- `lint`: `eslint "{src,test}/**/*.ts"`
- `format:check`: `prettier --check "src/**/*.ts" "test/**/*.ts"`

O warning de `no-console` em `main.ts:13` (`console.error` no handler de bootstrap) é pré-existente e aceitável pelo gate de CI (`docs/technical/ci-cd.md:14` — zero erros; warnings rastreados). Não é regressão do P01M03.

---

### ✅ Criterion 6: `var x = 1` faz lint sair com código ≠ 0

**Status**: Met  
**Evidence** (arquivo temporário `src/_lint-var-test.ts`, removido em seguida):

```
1:1  error  Unexpected var, use let or const instead  no-var
1:5  error  'x' is assigned a value but never used    @typescript-eslint/no-unused-vars

✖ 3 problems (2 errors, 1 warning)
EXIT_CODE=1
```

A regra `no-var: error` está ativa e bloqueia o gate.

---

## Comparison with `docs/technical/guidelines/coding-standards.md`

| Guideline (Backoffice) | Implementação | Status |
|---|---|---|
| ESLint 9, flat config (`eslint.config.mjs`) | `eslint.config.mjs` presente, ESLint 9.x | ✅ |
| `typescript-eslint` 8 | `^8.18.2` → 8.67.0 instalado | ✅ |
| Prettier: singleQuote, trailingComma all, semi, printWidth 100, tabWidth 2 | `.prettierrc` idêntico | ✅ |
| Sete regras de lint com severidades documentadas | Todas presentes em `eslint.config.mjs:18-33` | ✅ |
| Node.js 24.x | `engines.node: ">=24"` | ✅ (herdado, fora do escopo P01M03) |
| TypeScript 5.6, strict | `typescript ^5.6.3`, `strict: true` em tsconfig | ✅ (P01M02, fora do escopo) |

Nenhuma regra extra além da guideline foi adicionada. Nenhuma regra documentada está faltando.

## Code Quality Assessment

**Rating**: Good (⭐⭐⭐⭐)

**Findings**:
- ✅ Flat config limpo, legível, segue padrão `typescript-eslint` 8.
- ✅ Ignores explícitos para `dist/`, `coverage/`, `node_modules/` (`eslint.config.mjs:7`).
- ✅ `@eslint/js` agora declarado em `devDependencies` — débito D1 do P01M01 resolvido (`package.json:38`).
- ✅ `format:check` adicionado — pendência registrada no P01M01 resolvida (`package.json:18`).
- ✅ `lint-staged` integra ESLint + Prettier nos arquivos staged (`package.json:54-56`).
- ⚠️ `console.error` em `main.ts:13` gera warning de `no-console` — esperado até P01M10 (logger estruturado); não é falha deste milestone.
- 💡 Futuro: considerar `recommendedTypeChecked` quando regras type-aware forem adicionadas à guideline (ex.: `no-floating-promises`).

## NFR Compliance

- **P0 (Correctness)**: ✅ Met — config aplica regras corretas; lint e format executam sem erro.
- **P1 (Tests)**: ✅ Met — `npm test` (1 suite, 1 teste) e `npm run test:e2e` (1 suite, 1 teste) passam; nenhum teste falho ou pulado.
- **P2 (Security)**: ✅ Met / N/A — milestone de tooling; sem superfície de ataque nova.
- **P3 (Quality)**: ✅ Met — zero erros de lint; config alinhada à guideline; débito D2 do P01M01 fechado.
- **P4 (Performance)**: ✅ Met / N/A — lint completa em ~1,5s.

## Gates Executed

| Gate | Comando | Resultado |
|---|---|---|
| Lint | `npm run lint` | ✅ exit 0 (1 warning pré-existente) |
| Format | `npm run format:check` | ✅ exit 0 |
| Unit tests | `npm test` | ✅ 1/1 passed |
| E2E tests | `npm run test:e2e` | ✅ 1/1 passed |
| no-var enforcement | temp `var x = 1` | ✅ exit 1 |

## Recommendations

### High Priority

Nenhum item bloqueante.

### Medium Priority

1. Substituir `console.error` em `main.ts:13` por logger estruturado quando P01M10 entregar — elimina o único warning de lint restante.
2. Documentar no README do serviço (P01M07) que warnings de lint pré-existentes são débito rastreado, conforme gate de CI.

### Low Priority

1. Avaliar inclusão de `recommendedTypeChecked` em milestone futuro se a guideline adicionar regras type-aware.
2. Adicionar `.prettierignore` se `dist/` ou artefatos gerados entrarem no glob de format no futuro.

## Resolution of P01M01 Debt

| Débito | Status pós-P01M03 |
|---|---|
| D1 — `@eslint/js` não declarado | ✅ Resolvido (`package.json:38`) |
| D2 — `eslint.config.mjs` sem regras da guideline | ✅ Resolvido (todas as 7 regras + prettier last) |
| D2 — `format:check` ausente | ✅ Resolvido (`package.json:18`) |

O gatilho de bloqueio #1 do P01M01 ("P01M03 COMPLETE sem D2 corrigido") **não se aplica** — D2 está corrigido.

## Overall Assessment

**Pass**: ✅

Todos os seis critérios de aceite do P01M03 foram verificados por inspeção de arquivo e execução. A configuração de lint e format espelha exatamente `docs/technical/guidelines/coding-standards.md`. Os gates `npm run lint`, `npm run format:check`, testes unitários e e2e passam verde. A regra `no-var` está ativa e comprovada. O débito de lint fictício do P01M01 está encerrado. Nenhum teste falha, nenhum teste é pulado, nenhum erro de lint existe no codebase.
