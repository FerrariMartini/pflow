# Phase 2: Kernel HTTP — Erros Tipados, Validação, Masking de PII e Borda Segura

**Duration**: ~3 days (22 milestones @ 1h each)
**Dependencies**: Phase 1
**Status**: 🚧 TODO

## Goal

Construir a camada transversal (`src/common/`) que todo endpoint das fases seguintes vai herdar, de forma que nenhuma feature precise reimplementar erro, validação, masking ou cabeçalho de segurança — e que nenhum endpoint futuro possa escapar desses controles.

Entregas principais:
- Hierarquia `DomainError` com `code` estável (contrato público, ver `docs/technical/guidelines/error-handling.md`) e `DomainExceptionFilter` como único ponto de tradução para status HTTP; `AllExceptionsFilter` para falha técnica retornando 500 genérico sem stack trace.
- `ValidationPipe` global com `whitelist`, `forbidNonWhitelisted` e `transform`; DTOs de entrada sempre validados com `class-validator`.
- `LoggingInterceptor` propagando `correlationId`/`request_id` e as tags obrigatórias (`tenant_id`, `organization_id`, `user_id`, `trace_id`) para logs e traces.
- `MaskingInterceptor` global de responses e masking de PII em log (CPF `***.***.789-01`, email `c***@example.com`, telefone `***4321`).
- Helmet.js com configuração OWASP (CSP, HSTS, X-Frame-Options), CORS restrito a `FRONTEND_URL`, `ThrottlerModule` global (100 req/min).
- `PaginationDto` / `PaginatedResponseDto` compartilhados (default 20, max 100) e `BaseEntity`.
- Swagger/OpenAPI auto-gerado por decorators, com o formato de erro do `docs/contract/contract.md` documentado.
- Convenção de prefixo `/api` e bootstrap consolidado em `main.ts`.

## Phase Acceptance Criteria

- Lançar um `DomainError` de qualquer service produz o envelope `{ error: { code, message, correlationId } }` do `docs/contract/contract.md`, com o mapeamento para HTTP em um único filtro — verificado por teste e2e.
- Uma exceção técnica (ex: banco indisponível simulado) retorna 500 genérico, sem stack trace nem string de conexão no corpo da resposta, e gera log `error` com stack trace apenas no log interno.
- Payload com campo não declarado no DTO é rejeitado com 400 (`forbidNonWhitelisted`), coberto por teste.
- Resposta contendo CPF, email ou telefone sai mascarada pelo `MaskingInterceptor`; teste unitário cobre os três formatos de máscara e o caso de campo ausente.
- Nenhum log emitido durante uma requisição autenticada ou anônima contém PII em claro — teste de integração inspeciona o transporte de log.
- Helmet, CORS restrito e Throttler estão ativos globalmente; teste e2e prova 429 após estourar o limite e prova a presença dos headers de segurança.
- Swagger disponível em ambiente não-produtivo, com todos os DTOs comuns e o schema de erro documentados.
- Cobertura ≥ 90% em filtros, interceptors e pipes que carregam regra; `scripts/pre-commit.sh` verde.

## Milestones

<!-- Milestones appended by /wiz-milestones -->
### P02M01: Criar a estrutura de `src/common/` e o `CommonModule`

**Status:** 🚧 TODO
**ID:** P02M01

**Goal**

Criar o esqueleto de diretórios de `src/common/` conforme a §9 do PRD (`decorators/`, `guards/`, `interceptors/`, `filters/`, `interfaces/`, `dto/`, `entities/`, `services/`, `errors/`) e o `CommonModule` que centraliza o registro dos providers globais desta fase.

**Acceptance Criteria**

- [ ] Diretórios de `src/common/` criados exatamente com os nomes da §9 do PRD, acrescidos de `errors/`
- [ ] `src/common/common.module.ts` criado como `@Global()` e importado por `AppModule`
- [ ] `CommonModule` compila sem provider órfão e sem import circular
- [ ] Barrel `index.ts` por subdiretório, sem reexportar símbolo inexistente
- [ ] Nenhum diretório vazio deixado no commit (todo diretório tem ao menos o barrel ou um arquivo real)
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---

### P02M02: Definir a classe base `DomainError` e o catálogo de códigos estáveis

**Status:** 🚧 TODO
**ID:** P02M02

**Goal**

Implementar `src/common/errors/domain-error.ts` com a classe base abstrata `DomainError` e o catálogo de códigos de erro estáveis, tratando o `code` como contrato público conforme `docs/technical/guidelines/error-handling.md` e `docs/contract/contract.md`.

**Acceptance Criteria**

- [ ] `DomainError` é uma classe abstrata que estende `Error`, expõe `readonly code: string` e aceita `message` e um `details?` opcional
- [ ] `name` da instância é o nome da subclasse e o stack trace é capturado corretamente (`Error.captureStackTrace` / `Object.setPrototypeOf`)
- [ ] Catálogo de códigos declarado como objeto `as const` (ex.: `ERROR_CODES`) com tipo derivado, em arquivo próprio — nenhum código de erro em string literal solta
- [ ] Catálogo inclui, no mínimo, `TRANSACTION_NOT_FOUND` e `INVALID_RECONCILIATION_TRANSITION` citados na guideline
- [ ] Comentário no arquivo declara explicitamente que alterar um `code` existente é breaking change de contrato e exige versionamento da API
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---

### P02M03: Criar as subclasses tipadas de `DomainError` e o mapa código → status HTTP

**Status:** 🚧 TODO
**ID:** P02M03

**Goal**

Implementar as subclasses tipadas de `DomainError` por categoria semântica (não encontrado, entrada inválida, conflito de estado, não autorizado, proibido) e o mapa único que traduz cada categoria para o status HTTP correspondente, com testes unitários.

**Acceptance Criteria**

- [ ] Subclasses criadas cobrindo, no mínimo, os casos 404, 400/422, 409, 401 e 403, cada uma recebendo um `code` do catálogo
- [ ] O mapeamento categoria → status HTTP vive em um único módulo exportado, sem `switch` duplicado em outro arquivo
- [ ] O mapa tem fallback explícito e determinístico para categoria desconhecida (nunca `undefined` chegando ao filtro)
- [ ] Teste unitário verifica, para cada subclasse, o `code`, a categoria e o status HTTP resolvido
- [ ] Teste unitário prova que `instanceof DomainError` é verdadeiro em todas as subclasses (herança preservada após transpilação)
- [ ] Cobertura ≥ 90% nos arquivos de `src/common/errors/`
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---

### P02M04: Implementar o `DomainExceptionFilter` com o envelope de erro do contrato

**Status:** 🚧 TODO
**ID:** P02M04

**Goal**

Implementar o `DomainExceptionFilter` como o único ponto de tradução de `DomainError` para resposta HTTP, produzindo exatamente o envelope `{ error: { code, message, correlationId } }` de `docs/contract/contract.md`, com testes unitários.

**Acceptance Criteria**

- [ ] `@Catch(DomainError)` aplicado; o filtro resolve o status HTTP exclusivamente pelo mapa do P02M03
- [ ] Resposta serializada é exatamente `{ error: { code, message, correlationId } }` — sem campos extras, sem `statusCode` duplicado no corpo
- [ ] `correlationId` é lido do contexto da requisição; ausência de contexto não quebra o filtro (gera valor de fallback e loga `warn`)
- [ ] Erro de negócio é logado em nível `warn` (não `error`), com `code` e `correlationId`, sem stack trace
- [ ] Teste unitário cobre: cada categoria de erro, presença e ausência de `correlationId`, e a forma exata do corpo da resposta
- [ ] Nenhum controller do serviço traduz `DomainError` para status HTTP por conta própria — verificado por inspeção/grep
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---

### P02M05: Implementar o `AllExceptionsFilter` com 500 genérico e sem vazamento

**Status:** 🚧 TODO
**ID:** P02M05

**Goal**

Implementar o `AllExceptionsFilter` para falha técnica, retornando 500 com corpo genérico (sem stack trace, sem mensagem de driver, sem string de conexão) e registrando o erro completo apenas no log interno em nível `error`.

**Acceptance Criteria**

- [ ] `@Catch()` sem argumento; delega para o comportamento nativo do Nest quando a exceção já é `HttpException` de 4xx conhecida
- [ ] Corpo da resposta 500 usa o mesmo envelope do contrato, com `code` genérico (ex.: `INTERNAL_ERROR`) e mensagem fixa que não deriva da exceção original
- [ ] Log em nível `error` contém a mensagem original, o stack trace e o `correlationId` — e é o único lugar onde o stack aparece
- [ ] Teste unitário prova que uma exceção contendo string de conexão (`postgres://user:pass@host/db`) não expõe nenhum trecho dela no corpo da resposta
- [ ] Teste unitário prova que o corpo da resposta não contém a substring `at ` de stack trace nem o nome da classe da exceção original
- [ ] Cobertura ≥ 90% no arquivo do filtro
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---

### P02M06: Registrar os filtros globalmente e fixar a ordem de precedência

**Status:** 🚧 TODO
**ID:** P02M06

**Goal**

Registrar `DomainExceptionFilter` e `AllExceptionsFilter` como filtros globais via `APP_FILTER` no `CommonModule`, garantindo que o filtro específico tenha precedência sobre o catch-all, e provar o comportamento com teste e2e.

**Acceptance Criteria**

- [ ] Ambos os filtros registrados por `APP_FILTER` (injetáveis, com logger injetado por DI — nunca instanciados com `new` no `main.ts`)
- [ ] A ordem de registro garante que `DomainError` cai no `DomainExceptionFilter`, não no catch-all
- [ ] Teste e2e com controller de fixture: rota que lança `DomainError` retorna o status mapeado e o envelope do contrato
- [ ] Teste e2e com controller de fixture: rota que lança erro técnico genérico retorna 500 genérico
- [ ] Teste e2e prova que ambos os corpos carregam o mesmo `correlationId` enviado no header da requisição
- [ ] Controllers de fixture ficam restritos ao diretório de teste, fora do bundle de produção
- [ ] `npm run lint`, `npm test` e `npm run test:e2e` passam sem erro, falha ou teste pulado

---
### P02M07: Configurar o `ValidationPipe` global e o `exceptionFactory` no envelope

**Status:** 🚧 TODO
**ID:** P02M07

**Goal**

Registrar o `ValidationPipe` global com `whitelist`, `forbidNonWhitelisted` e `transform` ativos, e um `exceptionFactory` que converte a falha de validação em um `DomainError` tipado, para que a resposta 400 saia pelo mesmo envelope de erro do contrato.

**Acceptance Criteria**

- [ ] `ValidationPipe` registrado via `APP_PIPE` com `{ whitelist: true, forbidNonWhitelisted: true, transform: true, transformOptions: { enableImplicitConversion: false } }`
- [ ] `enableImplicitConversion` desativado e a conversão de tipo feita por `@Type()` explícito nos DTOs, para não mascarar payload inválido
- [ ] `exceptionFactory` monta um `DomainError` de validação com `code` estável (ex.: `VALIDATION_ERROR`) e agrega os campos inválidos em `details`
- [ ] A resposta de validação segue o envelope `{ error: { code, message, correlationId } }`, com o detalhamento por campo em chave dedicada dentro de `error`
- [ ] Mensagens de validação estão em inglês, conforme a política de idioma de `docs/technical/guidelines/coding-standards.md`
- [ ] Teste unitário do `exceptionFactory` cobre erro em campo simples, campo aninhado e múltiplos campos
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---

### P02M08: Testar a validação de entrada ponta a ponta

**Status:** 🚧 TODO
**ID:** P02M08

**Goal**

Escrever os testes e2e que provam o comportamento do `ValidationPipe` global sobre um DTO de fixture, cobrindo rejeição de campo não declarado, remoção por whitelist, coerção por `transform` e caminho de sucesso.

**Acceptance Criteria**

- [ ] Teste e2e: payload com campo não declarado no DTO retorna 400 com o `code` de validação (efeito de `forbidNonWhitelisted`)
- [ ] Teste e2e: payload com tipo errado em campo declarado retorna 400 e nomeia o campo no detalhamento
- [ ] Teste e2e: payload válido com query string numérica chega ao handler já convertido pelo `transform` (`typeof === 'number'`)
- [ ] Teste e2e: payload válido retorna 2xx e o corpo esperado
- [ ] Teste e2e prova que o corpo do 400 não ecoa o valor bruto rejeitado quando ele é um campo de PII
- [ ] `npm run lint`, `npm test` e `npm run test:e2e` passam sem erro, falha ou teste pulado

---

### P02M09: Implementar o `RequestContextService` e o middleware de `correlationId`

**Status:** 🚧 TODO
**ID:** P02M09

**Goal**

Criar o contexto por requisição baseado em `AsyncLocalStorage` (`src/common/services/`) e o middleware que resolve o `correlationId`/`request_id` — reaproveitando o header recebido ou gerando um UUID novo — e o disponibiliza para logs, filtros e interceptors sem passar parâmetro em cadeia.

**Acceptance Criteria**

- [ ] `RequestContextService` implementado sobre `AsyncLocalStorage`, exposto por interface/token conforme `docs/technical/guidelines/dependency-injection.md`
- [ ] Middleware lê `x-correlation-id` (ou `x-request-id`) da requisição e gera UUID v4 quando ausente
- [ ] O `correlationId` resolvido é devolvido no header da resposta, permitindo ao cliente correlacionar o incidente
- [ ] O contexto expõe `correlationId`, `request_id`, `tenant_id`, `organization_id`, `user_id` e `trace_id`, com os campos de identidade opcionais nesta fase (preenchidos pela Phase 3)
- [ ] Ler o contexto fora de uma requisição retorna `undefined` de forma segura, sem lançar
- [ ] Escopo do provider permanece singleton (`DEFAULT`); nenhum provider `REQUEST` introduzido
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---

### P02M10: Implementar o `LoggingInterceptor` com as tags obrigatórias

**Status:** 🚧 TODO
**ID:** P02M10

**Goal**

Implementar o `LoggingInterceptor` global que registra início e fim de cada requisição em JSON estruturado, carregando `correlationId` e as tags obrigatórias `tenant_id`, `organization_id`, `user_id`, `request_id` e `trace_id` da §7 do PRD.

**Acceptance Criteria**

- [ ] Interceptor registrado via `APP_INTERCEPTOR` no `CommonModule`, com o logger Winston injetado por interface/token
- [ ] Log de conclusão inclui método, rota, status HTTP e duração em milissegundos
- [ ] As cinco tags obrigatórias estão presentes em todo log emitido no ciclo da requisição, com valor `null` explícito quando ainda não disponível — nunca chave ausente
- [ ] `trace_id` é obtido do `dd-trace-js` quando há span ativo, sem quebrar quando o tracer está desabilitado em teste
- [ ] Nível `info` para 2xx/3xx, `warn` para 4xx e `error` para 5xx, conforme `docs/technical/guidelines/logging.md`
- [ ] Corpo de requisição e de resposta não são logados em nenhum nível
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---

### P02M11: Testar a propagação de `correlationId` e as tags do `LoggingInterceptor`

**Status:** 🚧 TODO
**ID:** P02M11

**Goal**

Cobrir com testes o middleware de contexto e o `LoggingInterceptor`, provando a propagação do `correlationId` ponta a ponta e a presença invariável das tags obrigatórias.

**Acceptance Criteria**

- [ ] Teste unitário: `correlationId` recebido no header é preservado; ausente, um UUID v4 válido é gerado
- [ ] Teste unitário: o mesmo `correlationId` aparece no log de requisição, no log de resposta e no header da resposta
- [ ] Teste unitário verifica a presença das cinco tags obrigatórias em cada registro capturado do transporte de log
- [ ] Teste unitário cobre a seleção de nível de log para 200, 400 e 500
- [ ] Teste unitário prova que o contexto não vaza entre requisições concorrentes (duas execuções paralelas mantêm `correlationId` distintos)
- [ ] Cobertura ≥ 90% no `LoggingInterceptor` e no `RequestContextService`
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---

### P02M12: Implementar os utilitários de masking de PII

**Status:** 🚧 TODO
**ID:** P02M12

**Goal**

Implementar as funções puras de masking de CPF, email e telefone com o formato exato definido na §7 do PRD, junto com o teste unitário exaustivo de cada formato e dos casos de borda.

**Acceptance Criteria**

- [ ] `maskCpf` produz `***.***.789-01` a partir de CPF com e sem pontuação
- [ ] `maskEmail` produz `c***@example.com`, preservando o primeiro caractere do local part e o domínio íntegro
- [ ] `maskPhone` produz `***4321`, preservando os quatro últimos dígitos independentemente de formatação e DDI
- [ ] Cada função é pura, sem I/O e sem dependência de framework, e retorna a máscara total quando o valor é curto demais para preservar o sufixo
- [ ] Entrada `null`, `undefined`, string vazia ou valor fora do formato esperado não lança e retorna valor mascarado seguro (nunca o valor original)
- [ ] Teste unitário em tabela de casos cobre os três formatos, cada caso de borda acima e a idempotência (mascarar um valor já mascarado não o corrompe)
- [ ] Cobertura de 100% nos utilitários de masking
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---
### P02M13: Implementar o `MaskingInterceptor` global de responses

**Status:** 🚧 TODO
**ID:** P02M13

**Goal**

Implementar o `MaskingInterceptor` global que aplica os utilitários do P02M12 sobre o corpo de resposta, identificando os campos de PII por convenção de nome e por decorator explícito, sem que cada módulo precise lembrar de mascarar.

**Acceptance Criteria**

- [ ] Interceptor registrado via `APP_INTERCEPTOR`, executando depois do handler e antes da serialização
- [ ] Decorator `@MaskPii(type)` disponível para marcar propriedade de DTO/entity, com os tipos `cpf`, `email` e `phone`
- [ ] Lista de nomes de campo reconhecidos por convenção (`cpf`, `document`, `email`, `phone`, `msisdn`) configurada em um único lugar
- [ ] Percorre objetos aninhados, arrays e o campo `data` de resposta paginada, preservando a estrutura e os tipos não-PII
- [ ] Campo ausente, `null` ou valor não-string é ignorado sem lançar
- [ ] Profundidade máxima de travessia limitada e referência circular tratada, para não travar em payload malformado
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---

### P02M14: Testar o `MaskingInterceptor` sobre payloads aninhados e coleções

**Status:** 🚧 TODO
**ID:** P02M14

**Goal**

Cobrir com testes o `MaskingInterceptor`, provando os três formatos de máscara na resposta HTTP, o comportamento em estrutura aninhada e o caso de campo ausente exigido pelos critérios da fase.

**Acceptance Criteria**

- [ ] Teste unitário: resposta simples contendo `cpf`, `email` e `phone` sai com as três máscaras exatas da §7 do PRD
- [ ] Teste unitário: objeto aninhado em dois níveis e array de objetos são mascarados em todos os elementos
- [ ] Teste unitário: campo de PII ausente no payload não gera erro nem chave nova na resposta
- [ ] Teste unitário: campo marcado com `@MaskPii` mas de nome não convencional também é mascarado
- [ ] Teste e2e: uma rota de fixture que devolve PII responde já mascarada através do pipeline completo
- [ ] Cobertura ≥ 90% no `MaskingInterceptor`
- [ ] `npm run lint`, `npm test` e `npm run test:e2e` passam sem erro, falha ou teste pulado

---

### P02M15: Aplicar masking de PII no logger Winston e testar o transporte de log

**Status:** 🚧 TODO
**ID:** P02M15

**Goal**

Adicionar um formatter de masking ao pipeline do Winston, para que nenhum log emitido durante uma requisição carregue CPF, email ou telefone em claro, e provar isso com teste de integração que inspeciona o transporte de log.

**Acceptance Criteria**

- [ ] Formatter de masking encadeado no Winston antes do formatter JSON, aplicado tanto ao `message` quanto aos metadados estruturados
- [ ] O formatter reaproveita os utilitários do P02M12 — nenhuma regex de máscara duplicada no código do logger
- [ ] Segredos e credenciais (`password`, `token`, `authorization`, `secret`, `x-signature`) são redigidos por completo, conforme `docs/technical/guidelines/logging.md`
- [ ] Teste de integração com transporte em memória: requisição carregando PII produz logs sem nenhuma ocorrência do valor original
- [ ] Teste de integração cobre requisição anônima e requisição com contexto de usuário preenchido
- [ ] Teste prova que o custo do formatter não altera a estrutura do log (campos obrigatórios `timestamp`, `level`, `service`, `correlationId` intactos)
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---

### P02M16: Configurar Helmet com perfil OWASP e CORS restrito a `FRONTEND_URL`

**Status:** 🚧 TODO
**ID:** P02M16

**Goal**

Aplicar o Helmet.js com configuração OWASP (CSP, HSTS, X-Frame-Options e demais headers) e restringir o CORS exclusivamente à origem de `FRONTEND_URL`, com credenciais habilitadas para o cookie HttpOnly que a Phase 3 vai emitir.

**Acceptance Criteria**

- [ ] Helmet habilitado no bootstrap com CSP explícita (sem `unsafe-inline` em `script-src`), HSTS com `includeSubDomains` e `X-Frame-Options: DENY`
- [ ] `x-powered-by` removido da resposta
- [ ] CORS aceita apenas a origem de `FRONTEND_URL`, com `credentials: true` e lista explícita de métodos e headers permitidos — nunca `origin: true` ou `*`
- [ ] `FRONTEND_URL` é lido do módulo de configuração validado por Zod da Phase 1; ausência da variável falha o boot
- [ ] Swagger continua carregando em ambiente não-produtivo apesar da CSP (exceção documentada e restrita à rota de docs)
- [ ] Configuração de Helmet e CORS vive no bootstrap, não espalhada por módulos
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---

### P02M17: Configurar o `ThrottlerModule` global e o envelope do 429

**Status:** 🚧 TODO
**ID:** P02M17

**Goal**

Registrar o `ThrottlerModule` global com limite de 100 requisições por minuto e traduzir a `ThrottlerException` para o envelope de erro do contrato, mantendo um único formato de erro em toda a API.

**Acceptance Criteria**

- [ ] `ThrottlerModule` configurado com `ttl` de 60 s e `limit` de 100, com ambos os valores vindos do módulo de configuração e com esse default
- [ ] `ThrottlerGuard` registrado como guard global via `APP_GUARD`
- [ ] `ThrottlerException` é traduzida para o envelope `{ error: { code, message, correlationId } }` com `code` estável (ex.: `RATE_LIMIT_EXCEEDED`) e status 429
- [ ] Headers de rate limit (`Retry-After` e equivalentes) presentes na resposta 429
- [ ] Decorator de isenção (`@SkipThrottle()`) aplicado apenas ao health check, com o motivo comentado
- [ ] Estouro do limite gera log `warn` com `correlationId` e identificador do chamador — sem PII
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---

### P02M18: Testar a borda segura ponta a ponta

**Status:** 🚧 TODO
**ID:** P02M18

**Goal**

Escrever os testes e2e que provam que Helmet, CORS restrito e Throttler estão ativos globalmente, cobrindo o critério de aceite da fase sobre headers de segurança e retorno 429.

**Acceptance Criteria**

- [ ] Teste e2e verifica a presença e o valor de `Content-Security-Policy`, `Strict-Transport-Security` e `X-Frame-Options` em uma resposta qualquer
- [ ] Teste e2e verifica que `x-powered-by` está ausente
- [ ] Teste e2e: requisição com `Origin` diferente de `FRONTEND_URL` não recebe `Access-Control-Allow-Origin` permissivo
- [ ] Teste e2e: estourar o limite configurado retorna 429 com o envelope de erro do contrato
- [ ] Teste e2e prova que o health check não é bloqueado pelo throttler
- [ ] O limite usado no teste vem de configuração reduzida no ambiente de teste, sem disparar 100 requisições reais nem `sleep` fixo
- [ ] `npm run lint`, `npm test` e `npm run test:e2e` passam sem erro, falha ou teste pulado

---
### P02M19: Criar `PaginationDto`, `PaginatedResponseDto` e `BaseEntity`

**Status:** 🚧 TODO
**ID:** P02M19

**Goal**

Implementar os contratos compartilhados de paginação (`src/common/dto/`) com default 20 e máximo 100 itens por página, e a `BaseEntity` (`id`, `created_at`, `updated_at`) que as entidades das fases seguintes vão estender.

**Acceptance Criteria**

- [ ] `PaginationDto` expõe `page` (default 1, mínimo 1) e `limit` (default 20, mínimo 1, máximo 100), validados por `class-validator` e convertidos por `@Type(() => Number)`
- [ ] `limit` acima de 100 é rejeitado com 400 pelo `ValidationPipe` — não silenciosamente truncado
- [ ] `PaginatedResponseDto<T>` é genérico e expõe `data: T[]` mais os metadados `page`, `limit`, `total` e `total_pages`
- [ ] `total_pages` é derivado e correto para `total` zero, exato e não múltiplo de `limit`
- [ ] `BaseEntity` define `id` (UUID), `created_at` e `updated_at` com as colunas TypeORM correspondentes, pronta para ser estendida
- [ ] Teste unitário cobre os defaults, os limites de borda (0, 1, 100, 101) e o cálculo de `total_pages`
- [ ] `npm run lint` e `npm test` passam sem erro, falha ou teste pulado

---

### P02M20: Configurar Swagger/OpenAPI com o schema de erro documentado

**Status:** 🚧 TODO
**ID:** P02M20

**Goal**

Configurar o Swagger auto-gerado por decorators, disponível apenas em ambiente não-produtivo, documentando os DTOs comuns e o envelope de erro de `docs/contract/contract.md` como resposta padrão da API.

**Acceptance Criteria**

- [ ] `SwaggerModule` configurado no bootstrap com título, versão e descrição do serviço, servido em rota sob o prefixo `/api`
- [ ] Swagger é montado somente quando o ambiente não é produção, verificado por teste
- [ ] Um `ErrorResponseDto` documenta o envelope `{ error: { code, message, correlationId } }` e está registrado como schema reutilizável
- [ ] Respostas 400, 401, 403, 404, 429 e 500 declaradas como padrão global apontando para o `ErrorResponseDto`, sem repetição por controller
- [ ] `PaginationDto` e `PaginatedResponseDto` aparecem no schema com os limites (default 20, max 100) descritos
- [ ] Plugin CLI do Swagger habilitado no `nest-cli.json` para inferir tipos sem poluir os DTOs de decorator redundante
- [ ] `npm run lint`, `npm test` e `npm run test:e2e` passam sem erro, falha ou teste pulado

---

### P02M21: Consolidar o `main.ts` e publicar o catálogo de códigos de erro

**Status:** 🚧 TODO
**ID:** P02M21

**Goal**

Consolidar o bootstrap em `main.ts` com o prefixo global `/api` e a ordem correta de inicialização dos controles desta fase, e registrar o catálogo de códigos de erro em `docs/contract/contract.md`, conforme a regra de não alterar contrato sem atualizar a documentação no mesmo PR.

**Acceptance Criteria**

- [ ] `setGlobalPrefix('api')` aplicado uma única vez, com a rota de health continuando a responder em `GET /api/health`
- [ ] Ordem de bootstrap explícita e comentada: config validada → Helmet → CORS → prefixo global → Swagger (não-produtivo) → listen
- [ ] Filtros, pipe, guard e interceptors globais são registrados por DI no `CommonModule`, e o `main.ts` não instancia nenhum deles com `new`
- [ ] `main.ts` não contém regra de negócio nem leitura direta de `process.env` — tudo passa pelo módulo de configuração da Phase 1
- [ ] `docs/contract/contract.md` atualizado com o catálogo de códigos de erro do backoffice e a nota de que o `code` é contrato público versionado
- [ ] Nenhum `console.log` remanescente no caminho de bootstrap; o boot loga em JSON estruturado
- [ ] `npm run lint`, `npm test` e `npm run test:e2e` passam sem erro, falha ou teste pulado

---

### P02M22: Verificar conclusão da Phase 2

**Status:** 🚧 TODO
**ID:** P02M22

**Goal**

Verificar que todos os requisitos da Phase 2 foram atendidos, os testes passam e a fase está pronta para sign-off antes de avançar para a Phase 3.

**Acceptance Criteria**

- [ ] Todos os milestones anteriores da Phase 2 estão marcados como concluídos
- [ ] `scripts/pre-commit.sh` passa verde a partir de um checkout limpo
- [ ] Cobertura ≥ 90% em filtros, interceptors e pipes que carregam regra
- [ ] Todos os critérios de aceite da fase (seção "Phase Acceptance Criteria") estão satisfeitos e verificados
- [ ] Nenhum bug ou pendência aberta desta fase
- [ ] Documentação atualizada
- [ ] Pronto para avançar para a Phase 3

---
