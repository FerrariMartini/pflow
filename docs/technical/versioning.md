# Versionamento e Changelog

## Princípio: versão por serviço, não por monorepo

Cada serviço tem sua própria versão (`package.json`/`go.mod`) e seu próprio `CHANGELOG.md` — não existe um número de versão único para o `payflow-hub` inteiro. Isso reflete a realidade de microsserviços: cada um é deployado, versionado e tem cadência de release independente (ver `docs/technical/ci-cd.md`, seção "Deploy progressivo"). Um changelog único pro monorepo misturaria mudanças de serviços que nem são deployados juntos.

## SemVer (MAJOR.MINOR.PATCH)

| Tipo de commit (Conventional Commits) | Bump | Seção no changelog |
|---|---|---|
| `fix:` | PATCH | Bug Fixes |
| `feat:` | MINOR | Features |
| `feat!:` ou rodapé `BREAKING CHANGE:` | MAJOR | Breaking Changes |
| `docs:`, `chore:`, `test:`, `refactor:`, `style:` | nenhum | (aparecem no changelog só como "Other", não forçam release) |

O bump é derivado automaticamente do histórico de commits — não é um número escolhido manualmente a cada release. Isso só funciona porque Conventional Commits já é gate obrigatório neste projeto (`docs/technical/guidelines/coding-standards.md`, seção Geral) e enforçado no commit via `commitlint` + `husky` (`services/payflow-backoffice-api`).

## Ferramenta

`payflow-backoffice-api` usa [`semantic-release`](https://semantic-release.gitbook.io/): a cada merge na branch principal, analisa os commits desde a última tag, calcula a próxima versão, gera o `CHANGELOG.md` e cria a tag — sem passo manual. Os serviços em Go seguem o mesmo princípio com ferramenta equivalente do ecossistema (`svu` + `git-chglog`), configurada junto com a primeira release de cada um.

## Versão de contrato ≠ versão de pacote, mas está relacionada

`docs/contract/contract.md` já define que mudança breaking de contrato REST exige novo prefixo de path (`/v2/...`) e mudança breaking de evento exige novo tópico/versão. A relação com SemVer do pacote:

- **Todo bump de versão de contrato é MAJOR de pacote** — se `/v1` vira `/v2`, o serviço necessariamente teve um `BREAKING CHANGE` no seu changelog.
- **Nem todo MAJOR de pacote muda o contrato público** — um refactor interno grande (ex: trocar o repositório in-memory por Postgres) pode justificar MAJOR sem que `/v1` deixe de existir para o integrador. Um refactor desse porte, quando implementado como milestone, tem sua nota de review em `.wiz/<slug>/reviews/`.

## Política de deprecação de contrato

Quando uma versão de contrato é aposentada (ex: `/v1` em favor de `/v2`):

1. `/v1` continua respondendo por no mínimo 6 meses após `/v2` ser publicado, prazo comunicado no changelog do serviço no momento em que `/v2` sai.
2. Resposta de `/v1` passa a incluir header `Sunset: <data>` (RFC 8594) a partir do dia em que `/v2` é publicado — integrador não é pego de surpresa.
3. Remoção efetiva de `/v1` é, ela mesma, um `BREAKING CHANGE` registrado no changelog, mesmo não sendo uma mudança de comportamento (é uma remoção de superfície).

## Estado atual

`services/payflow-backoffice-api/CHANGELOG.md` está em 0.1.0, sem seção de breaking changes — nenhum contrato publicado foi alterado desde a versão inicial. A configuração do `semantic-release` está em `.releaserc.json`, com `npmPublish: false` (o pacote é privado; o release produz tag e changelog, não publicação em registry).
