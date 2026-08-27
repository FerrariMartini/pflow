# Milestone Audit: P01M01

**Title**: Criar scaffold NestJS 11 do serviço
**PRD**: backoffice-api
**Phase**: 1
**Date**: 2026-08-24
**Auditor**: Claude Code (wiz-reviewer)

## Summary

O scaffold do `payflow-backoffice-api` está entregue e funcional: os seis critérios de aceite do P01M01 foram verificados individualmente no código e todos são reais — inclusive o critério de boot, confirmado subindo a aplicação e batendo em `http://localhost:3001/api`. Todos os gates executam verde a partir do checkout atual (`lint`, `build`, `test`, `test:e2e`, `scripts/pre-commit.sh`, `npm audit`).

O ponto de atenção não está no que o P01M01 pediu, e sim no que ele entregou **além** do escopo: `tsconfig.json`, `eslint.config.mjs`, config do Jest e o harness e2e foram criados nesta milestone, mas nenhum deles satisfaz os critérios das milestones P01M02/M03/M05/M06 que ainda estão TODO. O risco é o gate de lint parecer verde quando o conjunto de regras obrigatório da guideline ainda não está aplicado. Aprovado com débito registrado.

## Acceptance Criteria Verification

### Criterion 1: `package.json` declara `engines.node: ">=24"`, `@nestjs/core`, `@nestjs/common`, `@nestjs/platform-express` na major 11 e `reflect-metadata`

**Status**: ✅ Verificado
**Evidence**:
- File: `services/payflow-backoffice-api/package.json:7-9` — `"engines": { "node": ">=24" }`
- File: `package.json:21-27` — `@nestjs/common ^11.0.0`, `@nestjs/core ^11.0.0`, `@nestjs/platform-express ^11.0.0`, `reflect-metadata ^0.2.2`
- Versões efetivamente instaladas (`npm ls`): `@nestjs/common@11.2.1`, `@nestjs/core@11.2.1`, `@nestjs/platform-express@11.2.1`, `reflect-metadata@0.2.2` — major 11 confirmada, não apenas declarada.

**Issues**:
- Deriva do stack travado: `docs/technical/guidelines/coding-standards.md:32` fixa **TypeScript 5.6**, mas o range `^5.6.3` (`package.json:43`) resolveu para `typescript@5.9.3`. O mesmo padrão de caret vale para `@types/node ^24.0.0`. Não viola o critério (que não fala de TS), mas contraria a leitura literal de "stack travado". Débito de baixa severidade — ver Improvement Opportunities.

---

### Criterion 2: Scripts npm criados: `build`, `start`, `start:dev`, `start:prod`, `lint`, `format`, `test`, `test:cov`, `test:e2e`

**Status**: ✅ Verificado
**Evidence**:
- File: `package.json:10-20` — os nove scripts existem, um a um: `build` (`nest build`), `start`, `start:dev` (`nest start --watch`), `start:prod` (`node dist/main`), `lint` (`eslint "{src,test}/**/*.ts"`), `format` (`prettier --write`), `test` (`jest`), `test:cov` (`jest --coverage`), `test:e2e` (`jest --config ./test/jest-e2e.json`).
- Execução real: `build`, `lint`, `test`, `test:cov`, `test:e2e` e `start:dev` foram todos executados nesta auditoria e todos retornaram exit 0 (ver seção Gates Executed).

**Issues**:
- Não há `format:check`. O critério não o exige, mas o critério de fase ("`npm run lint` e `npm run format:check` passam verde", phase1.md, P01M03) e o gate de lint de `docs/technical/ci-cd.md:15` dependem dele. Fica como pendência explícita para o P01M03 — não é falha do P01M01.

---

### Criterion 3: `src/main.ts` faz bootstrap com prefixo global `/api` e porta lida de `PORT` (default `3001`)

**Status**: ✅ Verificado
**Evidence**:
- File: `src/main.ts:7` — `app.setGlobalPrefix('api')`
- File: `src/main.ts:8` — `const port = Number(process.env.PORT ?? 3001);`
- File: `src/main.ts:9` — `await app.listen(port)`
- Prova de execução: com `PORT` ausente, `ss -ltn` mostra `LISTEN *:3001` e `curl http://localhost:3001/api` responde `404` em 5,7ms (404 é o esperado: o root module ainda não tem controllers). O prefixo `/api` também é replicado no harness e2e (`test/app.e2e-spec.ts:14`).

**Issues**:
- `Number(process.env.PORT)` não valida a entrada. Com `PORT=abc` o valor vira `NaN` e `app.listen(NaN)` faz o Node escolher uma porta efêmera **em silêncio**, sem erro — falha de configuração que se manifesta como serviço no ar na porta errada. Severidade baixa hoje (o P01M08 vai substituir isso por validação Zod), mas é um caso de borda de corretude não tratado.
- `src/main.ts:8` lê `process.env` diretamente. É inevitável neste momento, mas contraria por antecipação o critério do P01M08 ("sem `process.env` espalhado pelo código"). Registrar para não sobreviver à fase.

---

### Criterion 4: `src/app.module.ts` existe como root module vazio e compila

**Status**: ✅ Verificado
**Evidence**:
- File: `src/app.module.ts:1-4` — `@Module({})` sobre `export class AppModule {}`, root module vazio conforme o critério.
- Prova de compilação: `npm run build` exit 0 e `dist/app.module.js` gerado.
- Prova de instanciação: `src/app.module.spec.ts:4-11` compila o módulo via `Test.createTestingModule` — teste passa.

---

### Criterion 5: `nest-cli.json`, `.nvmrc` (24) e `.gitignore` (node_modules, dist, coverage, .env) criados

**Status**: ✅ Verificado
**Evidence**:
- File: `nest-cli.json:1-8` — schema oficial, `collection: @nestjs/schematics`, `sourceRoot: src`, `deleteOutDir: true`.
- File: `.nvmrc:1` — `24`, coerente com `engines.node` e com `docs/technical/guidelines/coding-standards.md:30`.
- File: `.gitignore:1-4` — exatamente `node_modules`, `dist`, `coverage`, `.env`.
- Prova de eficácia (não só de existência): `git ls-files services/payflow-backoffice-api` lista 14 arquivos e **nenhum** de `dist/` ou `coverage/`, apesar de ambos existirem no working dir. `git status --short` está limpo.

---

### Criterion 6: `npm install && npm run start:dev` sobe a aplicação na porta 3001 sem erro

**Status**: ✅ Verificado
**Evidence**:
- `npm run start:dev` executado nesta auditoria. Log: `Found 0 errors. Watching for file changes.` → `[NestFactory] Starting Nest application...` → `[InstanceLoader] AppModule dependencies initialized +5ms` → `[NestApplication] Nest application successfully started +2ms`. Zero erro, zero warning.
- `ss -ltn` confirmou `LISTEN 0 511 *:3001` no PID do processo.
- `curl -o /dev/null -w '%{http_code}' http://localhost:3001/api` → `404` em 5,7ms (aplicação servindo; 404 correto para um módulo sem rotas).

**Issues**:
- Os logs de boot são o formatter colorido padrão do NestJS, não JSON estruturado. Isso é escopo do P01M10/M11, **não** deste critério — registrado apenas porque é critério de fase ("Todo log emitido no boot é JSON estruturado…") e ainda não está atendido.

---

## Gates Executed

`node_modules` **está presente** (431 pacotes no topo), então nenhum gate foi pulado.

| Gate | Comando | Exit | Resultado observado |
|---|---|---|---|
| Lint | `npm run lint` | **0** | `eslint "{src,test}/**/*.ts"` — nenhuma saída, zero erro, zero warning |
| Build | `npm run build` | **0** | `nest build` — `dist/` gerado, nenhum erro de tipo |
| Test (unit) | `npm test` | **0** | 1 suíte / 1 teste, **1 passed, 0 failed, 0 skipped** (`src/app.module.spec.ts` → "should compile", 6ms) |
| Test (e2e) | `npm run test:e2e` | **0** | 1 suíte / 1 teste, **1 passed, 0 failed, 0 skipped** (`test/app.e2e-spec.ts` → "bootstraps the application", 63ms). Encerrou sem handles pendentes |
| Coverage | `npm run test:cov` | **0** | Passa, mas **28,57% stmts / 0% branch / 0% funcs / 16,66% lines** global. `app.module.ts` 100%, `main.ts` 0% (linhas 1-14). Passa apenas porque **não há `coverageThreshold` configurado** |
| Pre-commit | `scripts/pre-commit.sh` | **0** | Executou os quatro gates do backoffice em sequência (lint → build → test → e2e), todos verdes: `[pre-commit] todos os gates passaram` |
| Dependências | `npm audit` | **0** | `found 0 vulnerabilities` — atende `docs/technical/ci-cd.md:28` (zero `critical`/`high`) |
| Boot | `npm run start:dev` | — | Sobe em ~2ms após compilação, escuta em `:3001`, responde HTTP |

Nenhum serviço Go tem `go.mod`, então o loop CORE do `pre-commit.sh` não executou nada — comportamento correto e esperado nesta fase.

**Regressões no restante do codebase**: nenhuma. `git status --short` limpo; nenhum outro serviço tem código.

## Code Quality

**Overall Rating**: Good

**Strengths**:
- **Escopo respeitado no código-fonte**: `app.module.ts` é literalmente o módulo vazio pedido, sem controllers/serviços de demonstração do boilerplate `nest new`. Nada de `AppController`/`AppService` órfãos para limpar depois.
- **`bootstrap()` bem escrito para o tamanho que tem**: `Promise<void>` explícito, `void bootstrap().catch(...)` com `process.exit(1)` — a rejeição não some silenciosamente, que é o erro clássico neste arquivo.
- **Política de idioma respeitada** (`coding-standards.md:52-57`): identificadores, descrições de teste e a mensagem de commit em inglês; artefatos de planejamento em português. O commit `70b409b feat(backoffice-api): complete P01M01 - NestJS 11 scaffold` segue Conventional Commits **com escopo do serviço**, exatamente como `coding-standards.md:63` exige — mesmo antes do commitlint existir (P01M04).
- **`.gitignore` comprovadamente eficaz**, não decorativo: `dist/` e `coverage/` existem no disco e nenhum dos dois entrou no índice.
- **Higiene**: zero `TODO`/`FIXME` no código, `tsconfig.build.json` já separa o build de produção dos specs, `test/` fora do `include` do `tsconfig.json`.

**Areas for Improvement**:
- **`@eslint/js` é importado mas não é dependência declarada.** `eslint.config.mjs:1` faz `import eslint from '@eslint/js'`, e `@eslint/js` **não** consta de `devDependencies` (`package.json:28-45`) nem do root do `package-lock.json`. Hoje funciona porque o npm iça `@eslint/js@9.39.5` (dependência transitiva do `eslint`) para `node_modules/@eslint/js`. É uma dependência implícita em estado de hoisting: qualquer mudança na árvore interna do ESLint quebra o gate de lint sem que nada no serviço tenha mudado. Conflita com `docs/technical/ci-cd.md:18` ("build reprodutível a partir de um checkout limpo, sem dependência de estado local").
- **`console.error` em `src/main.ts:13`.** `coding-standards.md:43` define `no-console: warn` e manda usar o logger estruturado. Hoje isso passa despercebido porque o `eslint.config.mjs` ainda não aplica a regra — ou seja, o gate está verde por omissão, não por conformidade.
- **O harness e2e não usa supertest**, apesar de `supertest@7` e `@types/supertest` estarem instalados. `test/app.e2e-spec.ts:22-24` afirma apenas `expect(app).toBeDefined()` — isso é sempre verdadeiro depois de `createNestApplication()` e não valida nada sobre HTTP. É um teste de valor quase nulo. (O critério que exige requisição real é do P01M06, ainda TODO — registrado aqui para não ser esquecido.)
- **Layout de módulo ainda não materializado**: `coding-standards.md:37` define `src/modules/<dominio>/{controller,service,dto,entities}` e o P01M07 detalha `src/common/`, `src/config/`, `src/infrastructure/`. Hoje `src/` tem só dois arquivos na raiz. Correto para o escopo do P01M01, mas nada da estrutura documentada existe ainda.
- **Sem `README.md` do serviço e sem `.env.example`** (escopo P01M07). Consequência prática imediata: as instruções de ativação de hooks e as credenciais de dev não têm onde morar.

## NFR Compliance

Ordem de prioridade conforme `.wiz/backoffice-api/prd.md:879` — *"Segurança é P1, empatada com testes"* —, que promove Segurança acima da tabela genérica de `docs/product/PRD.md:51`.

### P0 — Correctness: ✅ Atendido (com uma borda aberta)
A aplicação faz exatamente o que o milestone especifica: compila, sobe, aplica o prefixo `/api`, escuta em 3001, e o desligamento é limpo (e2e encerra sem handles pendentes). O erro de bootstrap é capturado e sai com código 1 (`main.ts:12-15`).
Borda não tratada: `Number(process.env.PORT)` sem validação → `PORT` não numérico produz `NaN` e bind silencioso em porta efêmera. Não é exigido por nenhum critério do P01M01 e será eliminado pelo P01M08, mas está registrado como débito de corretude com data de validade.

### P1 — Tests: ⚠️ Parcialmente atendido
Existem 2 testes, ambos passam, nenhum é `skip`, e o `pre-commit.sh` já os executa como gate. Isso satisfaz o mínimo desta milestone (que não pede testes explicitamente).
Lacunas objetivas: (a) **nenhum `coverageThreshold`** configurado — `package.json:46-56` não tem o bloco, então a cobertura de **28,57%** passa verde, muito abaixo dos 90% do critério de fase; (b) o teste e2e não exercita HTTP; (c) `main.ts` está a 0% de cobertura, incluindo o `catch` de bootstrap; (d) o gate P1 do §14 do PRD exige **Husky com lint-staged + test**, e não há Husky nem commitlint instalados (P01M04, TODO) — o enforcement de Conventional Commits ainda depende de disciplina humana, não de hook.

### P1 — Security: ✅ Atendido para o escopo
- Nenhum segredo, credencial ou valor real no código ou no `package.json` — conforme `coding-standards.md:64`. `.env` está no `.gitignore` do serviço e do repositório.
- `npm audit`: **0 vulnerabilidades**, atendendo `ci-cd.md:28`.
- Superfície de ataque: nenhuma. Não há controller, rota autenticável, DTO ou entrada de usuário — a regra "nenhuma fase entrega endpoint sem autenticação e autorização" (`prd.md:879`) não é violada porque não há endpoint.
- Observação para acompanhamento: `console.error(err)` em `main.ts:13` imprime o objeto de erro cru. Em falha de conexão a banco, isso pode carregar connection string com credenciais para stdout. Hoje é inócuo (não há banco); vira risco real no P01M16.

### P3 — Quality: ⚠️ Parcialmente atendido
Lint verde, build verde, código legível, idioma correto, commit no padrão, `.gitignore` eficaz. Contudo, **três configurações entregues nesta milestone não implementam a guideline que dizem implementar**, e como estão no diretório do serviço podem passar por "prontas":
- `tsconfig.json` **não tem `strict: true`** (tem apenas `strictNullChecks` + `noImplicitAny`), não tem `noImplicitOverride`, não tem `moduleResolution` nem path alias — todos exigidos por `coding-standards.md:32` e pelo P01M02.
- `eslint.config.mjs:4-9` aplica só `eslint.configs.recommended` + `tseslint.configs.recommended`. **Nenhuma** das regras nomeadas em `coding-standards.md:40-44` está configurada: `no-explicit-any` está como *error* (herdado do recommended) quando a guideline manda *warn*; `no-console` não está ligado; `no-unused-vars` não tem `argsIgnorePattern: '^_'`; `object-shorthand` e `prefer-arrow-callback` não existem. `eslint-config-prettier` não está instalado, então a exigência de "não conflitar" também não está satisfeita.
- Nenhum ADR foi produzido (P3 do PRD exige ADR para decisão relevante) — nenhuma decisão arquitetural foi tomada nesta milestone, então isso é apenas informativo.

### P4 — Performance: ✅ Atendido / N/A
Nenhum requisito de performance incide sobre um scaffold. Como indicador: boot em ~2ms após compilação e resposta HTTP em 5,7ms — folgadamente dentro do alvo de `< 100ms` de health check do §14 do PRD, embora o endpoint de health (P01M2x) ainda não exista.

## Improvement Opportunities

**Alta prioridade (fechar antes de a fase avançar)**
1. **Declarar `@eslint/js` em `devDependencies`** (`package.json`) e regenerar o lockfile. Uma linha; remove uma dependência transitiva implícita do caminho crítico do gate de lint.
2. **Fechar P01M02/M03/M05 sem herdar as configs como "prontas"**: a revisão dessas milestones precisa tratar `tsconfig.json`, `eslint.config.mjs` e o bloco `jest` como *não escritos*, não como *já existentes*. Especificamente: `strict: true` + `noImplicitOverride` + path alias; as sete regras de lint nominais + `eslint-config-prettier` por último; `coverageThreshold` global 90% e 85% em controllers.
3. **Instalar Husky + commitlint (P01M04)**. Enquanto não existirem, o gate P1 do §14 do PRD é honra-system, e o `pre-commit.sh` só roda se alguém o chamar à mão.

**Média prioridade**
4. **Validar `PORT`** — hoje `Number()` sem guarda. Será resolvido pelo schema Zod do P01M08; garantir que o `main.ts` deixe de ler `process.env` no mesmo movimento.
5. **Substituir `console.error` por logging estruturado** no handler de bootstrap quando o P01M10 entregar o `ILogger`, e assegurar que o erro não seja serializado cru (risco de vazar connection string a partir do P01M16).
6. **Fazer o teste e2e valer alguma coisa**: `request(app.getHttpServer()).get('/api/...')` com asserção de status, em vez de `expect(app).toBeDefined()`. O supertest já está instalado e sem uso.
7. **Adicionar `format:check`** ao `package.json` (`prettier --check`) — exigido pelo critério de fase e pelo gate de lint do CI.

**Baixa prioridade**
8. **Pinar as versões do stack travado** ou documentar a tolerância de caret: a guideline diz TypeScript **5.6**, o instalado é **5.9.3**. Decidir explicitamente (pin em `~5.6.x` ou atualizar a guideline) em vez de deixar a divergência acontecer por resolução de range.
9. **Registrar no README do serviço (P01M07)** que a suíte e2e compartilha `ts-jest` mas usa `rootDir` diferente, para evitar colisão futura de globs quando `src/` crescer.

## Verdict

**APPROVED WITH RECORDED DEBT**

**Razão da aprovação**: os seis critérios de aceite do P01M01 são verdadeiros e foram verificados por inspeção de arquivo e por execução, não por confiança no checkbox. Os quatro gates do `scripts/pre-commit.sh` passam a partir do estado atual do repositório, com zero teste falhando, zero teste pulado, zero erro de lint e zero vulnerabilidade de dependência. Não há regressão em nenhum outro ponto do codebase. Pelo padrão de qualidade do wiz-reviewer — nenhum teste falho/pulado, nenhum erro de lint em lugar nenhum — nada aqui justifica bloqueio.

**Débito aceito e registrado**:
- (D1) `@eslint/js` importado sem ser declarado como dependência.
- (D2) `tsconfig.json` sem `strict: true`, `eslint.config.mjs` sem nenhuma das regras da guideline, `jest` sem `coverageThreshold` — arquivos entregues por antecipação, incompletos frente às milestones que os governam.
- (D3) `console.error` e `process.env` diretos em `main.ts`.
- (D4) Suíte e2e sem asserção HTTP real; cobertura global em 28,57%.
- (D5) Sem Husky/commitlint: Conventional Commits não é enforçado no commit, apenas praticado.

**Gatilho explícito que torna este débito inaceitável** — qualquer um destes converte a aprovação em bloqueio retroativo da fase:

1. **P01M02, P01M03 ou P01M05 for marcado COMPLETE sem que D1 e D2 estejam corrigidos.** O motivo é concreto: enquanto `eslint.config.mjs` não aplicar `no-console`, `no-explicit-any: warn` e `no-unused-vars` com `argsIgnorePattern`, o "lint verde" reportado por este e por qualquer audit seguinte é um gate fictício — ele mede o conjunto default do ESLint, não o padrão do repositório. Aprovar código sob um gate fictício é pior do que não ter gate.
2. **Uma terceira milestone da Phase 1 for commitada antes do P01M04** (Husky + commitlint). O gate P1 do §14 do PRD é enforcement no commit; postergá-lo por mais de duas milestones significa que a fase inteira dependeu de disciplina manual.
3. **Qualquer código que toque banco, Redis ou segredo (P01M08 em diante) entrar com D3 em aberto** — `console.error(err)` cru no bootstrap deixa de ser cosmético no instante em que existir uma connection string para vazar, e passa a ser violação direta de "nenhum dado sensível em log" (P1 Segurança, `logging.md`).
