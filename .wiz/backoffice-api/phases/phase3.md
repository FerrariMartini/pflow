# Phase 3: Autenticação, 2FA por Email e Ciclo de Vida de Sessão

**Duration**: ~4 days (32 milestones @ 1h each)
**Dependencies**: Phase 1, Phase 2
**Status**: 🚧 TODO

## Goal

Entregar o fluxo de autenticação completo do painel (`src/auth/`) — pré-requisito absoluto de qualquer endpoint de negócio, conforme a restrição do §15 do PRD ("nenhuma fase entrega endpoint sem autenticação e autorização").

Entregas principais:
- `POST /api/auth/login`: bcrypt salt 12, retorno bifurcado entre `{ two_factor_required, session_token }` e emissão direta de JWT.
- `POST /api/auth/2fa/verify` e `POST /api/auth/2fa/resend`: OTP de 6 dígitos por email (AWS SES em produção, MailHog em dev), máximo 3 tentativas e 3 reenvios, sessão pré-2FA no Valkey Auth (`2fa:session:*`, `2fa:otp:*`, TTL 5min). Obrigatório para ADMIN e COMPLIANCE.
- `POST /api/auth/refresh` e `POST /api/auth/logout`: access token 15min + refresh token 2 dias em cookie HttpOnly `Secure` `SameSite=Strict`; logout com blacklist `jwt_blacklist:{jti}` (TTL = tempo restante) e invalidação do refresh.
- `PUT /api/auth/password`: exige senha atual; password policy OWASP (mín. 8 chars, maiúscula + minúscula + dígito + especial, rejeita as top 10k senhas comuns).
- Account lockout: 5 falhas → bloqueio de 15min via `login_attempts:{email}` no Valkey Auth.
- `JwtStrategy` (Passport) + `JwtAuthGuard` global com decorator `@Public()` para as exceções (`/api/health*`, login) — deny-by-default no nível de autenticação.
- Payload do JWT com `user_id`, `email`, `organization_id`, `role`, `tenant_ids`, `jti`.
- ADR registrando o desvio consciente do baseline OIDC de `docs/technical/architecture/security.md` para JWT local + 2FA por email neste serviço, com a justificativa e o caminho de convergência.

## Phase Acceptance Criteria

- Fluxo completo login → OTP no MailHog → verify → JWT em cookie HttpOnly coberto por teste e2e, incluindo o caminho sem 2FA para perfis não obrigatórios.
- Token JWT não é acessível via JavaScript (cookie `HttpOnly`, `Secure`, `SameSite=Strict`) e o teste e2e valida os atributos do `Set-Cookie`.
- Account lockout testado: 5 tentativas falhas bloqueiam por 15min, a 6ª retorna erro de bloqueio mesmo com senha correta, e o contador expira sozinho.
- 2FA testado nos casos de borda: OTP inválido, OTP expirado, 4ª tentativa, 4º reenvio e `session_token` expirado — cada um com `DomainError` tipado próprio e teste dedicado.
- Password policy rejeita senha fraca e senha da lista das top 10k; hash gerado é bcrypt com salt rounds 12, verificado por teste unitário.
- Logout coloca o `jti` na blacklist e uma requisição subsequente com o mesmo token retorna 401 — coberto por e2e contra Valkey real do compose.
- Nenhum log de qualquer rota de auth contém senha, OTP, token ou email em claro (email aparece mascarado).
- Cobertura ≥ 90% em `AuthService`, `TokenService` e `TwoFactorService`; `scripts/pre-commit.sh` verde.
- ADR do modelo de autenticação criado em `docs/decisions/` e `docs/contract/contract.md` atualizado com os endpoints de auth no mesmo PR.

## Milestones

<!-- Milestones appended by /wiz-milestones -->
### P03M01: Registrar ADR do modelo de autenticação do backoffice

**Status:** 🚧 TODO
**ID:** P03M01

**Goal**

Documentar, antes de qualquer linha de implementação, a decisão de usar JWT local + 2FA por email neste serviço em vez do baseline OIDC descrito em `docs/technical/architecture/security.md`, conforme a regra de `docs/technical/guidelines/coding-standards.md` ("toda decisão arquitetural relevante vira ADR antes da implementação, não depois").

**Acceptance Criteria**

- [ ] Novo ADR criado em `docs/decisions/` com o próximo número sequencial disponível (posterior a `adr-0002`), seguindo o formato dos ADRs existentes (contexto, decisão, consequências, alternativas)
- [ ] O ADR declara explicitamente que diverge do baseline "Backoffice (operador humano): OIDC contra o provedor de identidade da empresa" de `docs/technical/architecture/security.md` e justifica a divergência
- [ ] O ADR descreve o caminho de convergência para OIDC (o que precisa existir para migrar e o que ficaria inalterado: RBAC por `role`, escopo por `organization_id`/`tenant_ids`)
- [ ] O ADR registra os controles compensatórios adotados (bcrypt salt 12, 2FA obrigatório para ADMIN e COMPLIANCE, account lockout, blacklist de `jti`, cookie `HttpOnly`/`Secure`/`SameSite=Strict`)
- [ ] `docs/technical/architecture/security.md` referencia o novo ADR na linha do backoffice, para que a leitura da arquitetura não conflite com a implementação

---

### P03M02: Criar entidade `BackofficeUser` e repositório de autenticação

**Status:** 🚧 TODO
**ID:** P03M02

**Goal**

Mapear a tabela `backoffice_users` do `backoffice-db` como entidade TypeORM e expor o acesso de leitura/escrita necessário à autenticação atrás da interface `IUserRepository`, sem que nenhum service conheça o TypeORM diretamente.

**Acceptance Criteria**

- [ ] Entidade `BackofficeUser` mapeada em `src/users/entities/` com `id`, `organization_id`, `email`, `name`, `role`, `tenant_ids`, `active`, `password_hash`, `two_factor_enabled`, `created_at`, `updated_at`, `deleted_at`, `deleted_by`
- [ ] `password_hash` marcado com `select: false` para nunca vir em consulta genérica; a leitura para login usa seleção explícita
- [ ] Interface `IUserRepository` em `src/users/interfaces/` com `findByEmail(email)`, `findById(id)` e `updatePasswordHash(id, hash)`; implementação `UserRepository` registrada por token (`provide: 'IUserRepository'`) conforme `docs/technical/guidelines/dependency-injection.md`
- [ ] `findByEmail` normaliza o email (trim + lowercase) e ignora registros com `deleted_at` preenchido
- [ ] Teste de integração contra o `backoffice-db` do compose cobre usuário existente, usuário inexistente, usuário inativo e usuário soft-deleted
- [ ] `npm run lint` e `npm run build` passam sem erro nem warning novo

---

### P03M03: Implementar `PasswordService` com bcrypt salt rounds 12

**Status:** 🚧 TODO
**ID:** P03M03

**Goal**

Centralizar hashing e verificação de senha em um único serviço injetável, com bcrypt e salt rounds 12 conforme a §10 do PRD, de forma que nenhum outro ponto do código chame `bcrypt` diretamente.

**Acceptance Criteria**

- [ ] `PasswordService` criado em `src/auth/services/` implementando `IPasswordService` com `hash(plain)` e `compare(plain, hash)`
- [ ] Salt rounds fixado em 12 e exposto como constante nomeada; teste unitário lê o prefixo do hash gerado e afirma `$2b$12$`
- [ ] `compare` nunca lança para hash malformado — retorna `false` e emite log `warn` sem incluir a senha nem o hash
- [ ] `compare` executa contra um hash dummy pré-computado quando o usuário não existe, para que o tempo de resposta de "email inexistente" e "senha errada" não seja distinguível (mitigação de user enumeration)
- [ ] Nenhum outro arquivo do repositório importa `bcrypt` diretamente — verificado por busca no código e registrado como critério de review
- [ ] Testes unitários cobrem hash + compare com sucesso, compare com senha errada, hash inválido e o caminho do hash dummy

---

### P03M04: Implementar validador de password policy OWASP

**Status:** 🚧 TODO
**ID:** P03M04

**Goal**

Implementar a política de senha da §10 do PRD (mínimo 8 caracteres, ao menos uma maiúscula, uma minúscula, um dígito e um caractere especial) como regra de domínio reutilizável, aplicável tanto na troca de senha quanto no futuro cadastro de usuário da Phase 8.

**Acceptance Criteria**

- [ ] `PasswordPolicyService` (ou validador equivalente em `src/auth/services/`) expõe `validate(plain)` retornando a lista de regras violadas em vez de apenas um booleano
- [ ] Regras implementadas: comprimento mínimo 8, presença de maiúscula, minúscula, dígito e caractere especial
- [ ] Violação de política lança `WeakPasswordError` (subclasse de `DomainError`) com `code` estável e mensagem que descreve as regras não atendidas sem ecoar a senha
- [ ] Decorator `class-validator` customizado (ex: `@IsStrongPassword()`) expõe a mesma regra para uso em DTOs, sem duplicar a lógica
- [ ] Testes unitários parametrizados cobrem uma senha válida e um caso de rejeição por cada regra isolada, mais o caso de string vazia e de senha só com espaços

---

### P03M05: Rejeitar senhas da lista das top 10k mais comuns

**Status:** 🚧 TODO
**ID:** P03M05

**Goal**

Complementar a password policy com a checagem contra a lista das 10 mil senhas mais comuns exigida pela §10 do PRD, com custo de lookup constante e sem impacto perceptível no tempo de resposta.

**Acceptance Criteria**

- [ ] Lista das top 10k senhas comuns versionada no repositório (arquivo de dados dedicado, uma senha por linha), com a origem documentada em comentário/README do diretório
- [ ] Lista carregada uma única vez no boot para um `Set` em memória; o lookup é case-insensitive e não relê o arquivo a cada requisição
- [ ] Senha presente na lista é rejeitada com `CommonPasswordError` (`DomainError` com `code` próprio, distinto de `WeakPasswordError`)
- [ ] A verificação roda depois das regras de complexidade, para que uma senha fraca e comum reporte a violação mais específica de forma determinística
- [ ] Teste unitário afirma que a lista carregada tem 10.000 entradas, rejeita ao menos três senhas conhecidas da lista (em caixas diferentes) e aceita uma senha forte fora dela
- [ ] Teste garante que o carregamento da lista não ocorre em tempo de requisição (mock/spy no leitor de arquivo)

---

### P03M06: Definir os `DomainError` de autenticação e seu mapeamento HTTP

**Status:** 🚧 TODO
**ID:** P03M06

**Goal**

Criar a hierarquia de erros tipados do módulo de auth sobre o `DomainError` da Phase 2, com `code` estável, e registrar cada `code` como contrato público, conforme `docs/technical/guidelines/error-handling.md`.

**Acceptance Criteria**

- [ ] Subclasses de `DomainError` criadas em `src/auth/errors/` para, no mínimo: `INVALID_CREDENTIALS`, `ACCOUNT_LOCKED`, `ACCOUNT_INACTIVE`, `TWO_FACTOR_SESSION_EXPIRED`, `INVALID_OTP`, `OTP_ATTEMPTS_EXCEEDED`, `OTP_RESEND_LIMIT_EXCEEDED`, `INVALID_REFRESH_TOKEN`, `TOKEN_REVOKED`, `WEAK_PASSWORD`, `COMMON_PASSWORD` e `CURRENT_PASSWORD_MISMATCH`
- [ ] Mapeamento para status HTTP declarado exclusivamente no `DomainExceptionFilter` da Phase 2 — nenhum controller de auth traduz erro para status
- [ ] `INVALID_CREDENTIALS` é o único `code` retornado para email inexistente, senha errada e usuário inativo do ponto de vista do cliente, evitando user enumeration; a distinção fica apenas no log interno
- [ ] Todos os `code` acrescentados à tabela de erros de `docs/contract/contract.md`, com o status HTTP correspondente
- [ ] Nenhuma mensagem de erro de auth expõe email, senha, OTP ou token; teste unitário afirma isso para cada subclasse
- [ ] Teste unitário verifica que cada erro produz o envelope `{ error: { code, message, correlationId } }` esperado ao passar pelo filtro

---
### P03M07: Implementar `AuthCacheService` sobre o Valkey Auth

**Status:** 🚧 TODO
**ID:** P03M07

**Goal**

Encapsular todas as chaves de autenticação da §7 do PRD (`jwt_blacklist:{jti}`, `2fa:otp:{user_id}`, `2fa:session:{session_token}`, `login_attempts:{email}`) em um único serviço tipado sobre a conexão Valkey Auth (`REDIS_AUTH_URL`) criada na Phase 1, para que nenhum service monte string de chave à mão.

**Acceptance Criteria**

- [ ] `AuthCacheService` criado em `src/auth/services/`, implementando `IAuthCacheService` e injetando o `ICacheService` da conexão Valkey Auth (nunca o Redis Core)
- [ ] Construtores de chave centralizados em um único módulo de constantes, com os prefixos exatos da §7 do PRD e o TTL padrão de cada família de chave (blacklist = tempo restante do token, `2fa:*` = 5min, `login_attempts:*` = 15min)
- [ ] `login_attempts:{email}` usa hash do email normalizado como componente da chave, para que o email em claro não fique legível em um `KEYS`/dump do Valkey
- [ ] Métodos expostos são semânticos (`blacklistJti`, `isJtiBlacklisted`, `storeOtp`, `readOtp`, `storeTwoFactorSession`, ...), não `get`/`set` genéricos
- [ ] Teste de integração contra o Valkey Auth do compose valida escrita, leitura, expiração de TTL (com TTL curto) e ausência de chave
- [ ] Teste afirma que nenhuma chave escrita pelo serviço colide com os prefixos do Redis Core (`tenant:*`, `routing:*`, `cb:*`)

---

### P03M08: Definir o payload do JWT, a interface `ITokenService` e a configuração de tokens

**Status:** 🚧 TODO
**ID:** P03M08

**Goal**

Fixar o contrato do token antes da implementação: tipo do payload com os campos da §10 do PRD e a configuração validada de segredo e tempos de vida (access 15min, refresh 2 dias).

**Acceptance Criteria**

- [ ] Tipo `AuthTokenPayload` declarado com `user_id`, `email`, `organization_id`, `role`, `tenant_ids`, `jti`, além de `iat` e `exp`, sem campo opcional adicional não previsto no PRD
- [ ] Interface `ITokenService` em `src/auth/interfaces/` declarando emissão e verificação de access token e refresh token
- [ ] Schema Zod da Phase 1 estendido com `JWT_SECRET` (obrigatório, comprimento mínimo), `JWT_ACCESS_TTL` (default `15m`) e `JWT_REFRESH_TTL` (default `2d`); boot falha se `JWT_SECRET` estiver ausente ou for o valor de dev em `NODE_ENV=production`
- [ ] `JwtModule` do NestJS registrado de forma assíncrona a partir da configuração validada, nunca lendo `process.env` diretamente dentro do service
- [ ] Teste unitário do schema de configuração cobre segredo ausente, segredo curto, TTL inválido e os defaults
- [ ] Nenhum valor de `JWT_SECRET` aparece em log de boot; teste inspeciona o transporte de log do bootstrap

---

### P03M09: Emitir e verificar o access token com `jti`

**Status:** 🚧 TODO
**ID:** P03M09

**Goal**

Implementar em `TokenService` a emissão do access token de 15 minutos com o payload completo e um `jti` único por token, e a verificação que rejeita token expirado, com assinatura inválida ou com payload incompleto.

**Acceptance Criteria**

- [ ] `TokenService.issueAccessToken(user)` gera token assinado com HS256, TTL de 15min e `jti` UUID v4 gerado por CSPRNG, único a cada emissão
- [ ] O payload emitido contém exatamente `user_id`, `email`, `organization_id`, `role`, `tenant_ids` e `jti`, populados a partir da entidade `BackofficeUser`; `tenant_ids` reflete o valor persistido no usuário (a resolução de lista vazia para todos os tenants da Organization é entregue na Phase 4)
- [ ] `TokenService.verifyAccessToken(token)` lança `InvalidTokenError` para token expirado, assinatura inválida, algoritmo diferente do configurado e payload sem os campos obrigatórios
- [ ] Verificação fixa o algoritmo aceito explicitamente, rejeitando `alg: none` e troca de algoritmo — coberto por teste com token forjado
- [ ] Nenhum log emitido pelo `TokenService` contém o token, o segredo ou o `jti` completo
- [ ] Testes unitários cobrem emissão, round-trip de verificação, expiração (com clock controlado), assinatura inválida e `jti` distinto entre duas emissões consecutivas

---

### P03M10: Emitir, verificar e rotacionar o refresh token

**Status:** 🚧 TODO
**ID:** P03M10

**Goal**

Implementar o refresh token de 2 dias com identificador próprio e registro no Valkey Auth, de modo que ele possa ser invalidado individualmente no logout e na troca de senha.

**Acceptance Criteria**

- [ ] `TokenService.issueRefreshToken(user)` gera token de TTL 2 dias com `jti` próprio, distinto do `jti` do access token, e marca o tipo do token no payload para que um refresh não seja aceito como access
- [ ] O `jti` do refresh é registrado no Valkey Auth via `AuthCacheService`, vinculado ao `user_id`, com TTL igual ao do token
- [ ] `verifyRefreshToken` rejeita token cujo `jti` não esteja registrado (já invalidado), token expirado, assinatura inválida e token do tipo access
- [ ] `revokeRefreshToken(jti)` remove o registro e é idempotente (revogar duas vezes não lança)
- [ ] Teste de integração contra o Valkey do compose cobre emitir → verificar → revogar → verificar de novo (rejeitado)
- [ ] Testes unitários cobrem confusão de tipo (access usado como refresh e vice-versa) e refresh expirado

---

### P03M11: Implementar a blacklist de `jti` com TTL igual ao tempo restante

**Status:** 🚧 TODO
**ID:** P03M11

**Goal**

Implementar a revogação de access token via `jwt_blacklist:{jti}` no Valkey Auth com TTL calculado a partir do `exp` do próprio token, garantindo que a chave desapareça exatamente quando o token deixaria de ser válido por si só.

**Acceptance Criteria**

- [ ] `TokenService.revokeAccessToken(payload)` grava `jwt_blacklist:{jti}` com TTL = `exp - now` arredondado para cima em segundos
- [ ] Token já expirado no momento da revogação não gera chave (TTL ≤ 0 é no-op), evitando lixo permanente no Valkey
- [ ] `isAccessTokenRevoked(jti)` retorna `true` enquanto a chave existir e `false` após a expiração
- [ ] Falha de conexão com o Valkey Auth durante a checagem de blacklist resulta em negação da requisição (fail-closed), nunca em aceitação silenciosa — comportamento coberto por teste com o cache indisponível
- [ ] Teste de integração contra o Valkey do compose valida o TTL efetivo da chave (`TTL` dentro da margem esperada) e a expiração automática com TTL curto
- [ ] Nenhum log registra o `jti` completo nem o token; a correlação usa `correlationId` e `user_id`

---

### P03M12: Emitir os tokens em cookie HttpOnly, Secure e SameSite=Strict

**Status:** 🚧 TODO
**ID:** P03M12

**Goal**

Centralizar a escrita e a limpeza dos cookies de access e refresh token em um único helper, com os atributos de segurança exigidos pela §10 do PRD, para que nenhum controller monte `Set-Cookie` à mão.

**Acceptance Criteria**

- [ ] `AuthCookieService` (ou helper equivalente em `src/auth/services/`) expõe `setAuthCookies(res, accessToken, refreshToken)` e `clearAuthCookies(res)`
- [ ] Ambos os cookies são emitidos com `HttpOnly`, `SameSite=Strict` e `Path` restrito; `Secure` é sempre `true` fora de ambiente de desenvolvimento local e o comportamento é derivado da configuração validada, não de checagem ad-hoc de `process.env`
- [ ] `Max-Age` do cookie de access é 15min e o de refresh é 2 dias, derivados das mesmas constantes de TTL do `TokenService` (sem número mágico duplicado)
- [ ] Nomes dos cookies definidos como constantes compartilhadas, reutilizadas pela `JwtStrategy` e pelo endpoint de refresh
- [ ] `cookie-parser` habilitado no bootstrap e a configuração de CORS da Phase 2 ajustada para `credentials: true` restrito a `FRONTEND_URL`
- [ ] Teste e2e inspeciona o header `Set-Cookie` da resposta de login e afirma a presença de `HttpOnly`, `Secure`, `SameSite=Strict` e do `Max-Age` correto em cada cookie

---
