## Milestone

- ID: `P<fase>M<milestone>` — ex: `P02M01` (ver `.wiz/<slug>/phases/phase<fase>.md`)
- Contexto consultado: <link para a(s) guideline(s) em `docs/technical/guidelines/` que regem esta implementação — apontadas por `.wiz/context/authoritative-sources.md`>

## O que mudou e por quê

<!-- Não descreva "o quê" apenas — o diff já mostra isso. Descreva o "porquê", especialmente se algo se desviou da guideline consultada (ver nota de review, se houver). -->

## Checklist

- [ ] Lint limpo (`npm run lint` / `golangci-lint run`) — ver `docs/technical/ci-cd.md`
- [ ] Build sem erro
- [ ] Testes cobrindo o critério de aceite da milestone, incluindo ao menos um caso de borda/rejeição
- [ ] Nenhum segredo, credencial ou dado real introduzido
- [ ] Contrato de API/evento atualizado em `docs/contract/contract.md`, se este PR muda contrato
- [ ] ADR criado em `docs/decisions/`, se este PR envolve decisão arquitetural relevante
- [ ] Revisão do especialista de linguagem feita antes do commit (obrigatória em `/wiz-next`)
- [ ] Se este PR fechou uma auditoria formal, nota de review escrita em `.wiz/<slug>/reviews/milestone-<id>-review.md`

## Revisão

<!-- Preenchido pelo revisor: o que foi checado contra as guidelines aplicáveis, qualquer achado (mesmo que não bloqueante), veredito. -->
