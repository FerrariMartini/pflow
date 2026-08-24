# PayFlow Hub

Hub de pagamentos instantâneos — microsserviços orientados a eventos, cobrindo cash-in, cash-out, notificação outbound por webhook, trilha de auditoria e backoffice operacional.

Este repositório documenta o ciclo de vida completo do software com IA integrada ao processo: do PRD à arquitetura, do planejamento rastreável à implementação, revisão de código e retrospectiva. Domínio, nomes e dados são fictícios.

## Como a IA entra no ciclo

Dois regimes distintos, com ferramentas distintas:

- **PayFlow SDLC Kit** ([`.claude/`](./.claude)) — agentes e comandos que conduzem o trabalho planejado, fork adaptado do [wiz-cursor](https://github.com/NSXBet/wiz-cursor) (ver [`.claude/NOTICE.md`](./.claude/NOTICE.md)). `/wiz-prd` gera o PRD por Q&A; `/wiz-phases` e `/wiz-milestones` decompõem em fases e milestones rastreáveis; `/wiz-next` implementa cada milestone com revisão obrigatória do especialista de linguagem antes do commit; `/wiz-review-milestone` e `/wiz-review-phase` auditam sob demanda; `/wiz-retro` fecha a fase, decidindo por achado se vira débito aceito, atualização de guideline ou ADR.
- **Prompt estruturado** ([`docs/technical/prompt-engineering.md`](./docs/technical/prompt-engineering.md)) — para o trabalho que não cabe em uma milestone planejada: correção de bug, investigação pontual, decisão de arquitetura isolada.

O que amarra os dois é a regra de fonte única: [`docs/`](./docs) é a única origem de padrão técnico. Nenhum serviço tem `docs/` própria, e nenhum agente carrega convenção própria — ambos referenciam o mesmo lugar, o que mantém humano e IA lendo a mesma coisa.

## Estrutura

```
payflow-hub/
├── .claude/
│   ├── agents/wiz-*.md             # planner, reviewer, milestone-analyst, retro-analyst, especialistas de linguagem
│   ├── commands/wiz-*.md           # /wiz-prd, /wiz-phases, /wiz-milestones, /wiz-next, /wiz-review-*, /wiz-retro, /wiz-status
│   └── NOTICE.md                   # origem (fork do wiz-cursor) e adaptações feitas neste repositório
├── .wiz/
│   ├── context/                    # authoritative-sources.md — aponta o planejamento para docs/technical/guidelines/
│   └── <slug>/                     # um diretório por PRD (ex. backoffice-api/), gerado pelos comandos wiz-*
│       ├── prd.md
│       ├── phases/phaseN.md        # milestones no formato P0XM0Y
│       ├── reviews/                # nota de review por milestone/fase concluída
│       └── retros/                 # retrospectiva por fase encerrada
├── docs/
│   ├── product/PRD.md              # produto, personas, NFRs
│   ├── technical/
│   │   ├── architecture/           # visão geral, segurança, observabilidade
│   │   ├── infrastructure/         # AWS, runbook de SRE
│   │   ├── guidelines/             # DI, error handling, logging, coding standards
│   │   ├── quality/                # diretrizes de QA + métricas do processo de IA
│   │   ├── ci-cd.md                # pipeline e critérios de qualidade (gates)
│   │   ├── ai-augmented-sdlc.md    # o ciclo completo, fase a fase
│   │   ├── prompt-engineering.md   # prompt estruturado e gestão de contexto
│   │   ├── versioning.md           # SemVer por serviço, changelog, deprecação de contrato
│   │   └── retrospective.md        # quando e como as guidelines evoluem
│   ├── contract/                   # convenções de API/evento
│   └── decisions/                  # ADRs
├── services/
│   ├── payflow-gateway/            # borda: autenticação, rate limit, roteamento
│   ├── payflow-cashin-service/     # entrada de pagamentos
│   ├── payflow-cashout-service/    # saída de pagamentos
│   ├── payflow-webhook-service/    # notificação outbound com retry e DLQ
│   ├── payflow-outbox-relay/       # publicação confiável de eventos (padrão outbox)
│   ├── payflow-audit-service/      # trilha de auditoria append-only
│   └── payflow-backoffice-api/     # API operacional (NestJS) — consulta e conciliação
├── PULL_REQUEST_TEMPLATE.md        # checklist de PR: contexto consultado + nota de review
├── CONTRIBUTING.md                 # onboarding: leitura, primeira milestone, erros comuns
└── CLAUDE.md                       # orientação de IA para este repositório
```

`payflow-backoffice-api` é o serviço com implementação executável. Os demais estão especificados e planejados — contrato, eventos e milestones definidos, prontos para execução.

## Como ler este repositório

1. [`docs/product/PRD.md`](./docs/product/PRD.md) — contexto de produto, personas e NFRs priorizados.
2. [`docs/technical/architecture/overview.md`](./docs/technical/architecture/overview.md) — visão geral da arquitetura, com links para segurança, observabilidade e infraestrutura.
3. [`docs/technical/ai-augmented-sdlc.md`](./docs/technical/ai-augmented-sdlc.md) — o ciclo completo com IA, fase a fase.
4. [`.wiz/backoffice-api/prd.md`](./.wiz/backoffice-api/prd.md) e [`.wiz/backoffice-api/phases/`](./.wiz/backoffice-api/phases) — rastreabilidade de ponta a ponta do único serviço com implementação: PRD, fases e milestones gerados pelo PayFlow SDLC Kit.
5. [`CONTRIBUTING.md`](./CONTRIBUTING.md) — como um novo desenvolvedor (ou uma sessão nova de IA) entra no fluxo.

## Stack

- **Serviços de domínio**: Go, arquitetura hexagonal, comunicação assíncrona via Kafka
- **Backoffice API**: Node.js, NestJS, TypeScript
- **IA**: Claude Code — ver [`docs/technical/ai-augmented-sdlc.md`](./docs/technical/ai-augmented-sdlc.md)
