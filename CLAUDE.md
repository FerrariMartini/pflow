# CLAUDE.md

Orientações para o Claude Code (ou qualquer assistente de IA) trabalhando neste repositório.

## Contexto

PayFlow Hub é um hub de pagamentos instantâneos: microsserviços orientados a eventos cobrindo cash-in, cash-out, notificação outbound, auditoria e backoffice operacional. Ver `docs/product/PRD.md` e `docs/technical/architecture/overview.md` antes de propor mudanças estruturais.

## Como o trabalho é conduzido

- **Trabalho planejado** → PayFlow SDLC Kit (`.claude/`, fork do [wiz-cursor](https://github.com/NSXBet/wiz-cursor)): `/wiz-prd` (PRD por Q&A), `/wiz-phases` e `/wiz-milestones` (fases e milestones), `/wiz-next` (implementação com revisão obrigatória do especialista de linguagem antes do commit), `/wiz-review-milestone` e `/wiz-review-phase` (auditoria sob demanda), `/wiz-retro` (fecha a fase), `/wiz-status`. Ver `.claude/NOTICE.md` e `/wiz-help`.
- **Trabalho isolado** (bug, investigação, ajuste pontual) → prompt estruturado direto, sem passar pelos comandos. Ver `docs/technical/prompt-engineering.md`.

Princípios que valem nos dois casos:

- **Documentar decisão, não só código.** Decisão arquitetural relevante vira ADR em `docs/decisions/`.
- **Commits pequenos e descritivos.** Cada commit reflete uma unidade de trabalho coerente, com mensagem explicando o porquê.
- **Testar o que é escrito.** Código novo em `services/payflow-backoffice-api` vem acompanhado de teste (unitário ou e2e, conforme o caso).

## Regras de escopo

- `services/payflow-backoffice-api` é o serviço com implementação executável. Os demais estão especificados e planejados — não gerar código de implementação para eles sem alinhar antes.
- **`docs/` na raiz é a única fonte de verdade.** Nenhum serviço tem pasta `docs/` própria. Os especialistas de linguagem (`.claude/agents/wiz-*-specialist.md`) carregam um stack preferido genérico como fallback, mas devem deferir explicitamente para `docs/technical/guidelines/` sempre que houver conflito — um agente que aplica o próprio default sem checar a guideline documentada é bug do agente, não uma segunda opinião válida.
- Contexto específico de um serviço entra em `.wiz/<slug>/` (estado de planejamento gerado pelos comandos `wiz-*`) ou no README do próprio serviço, nunca em uma cópia de `docs/`.
- Nenhum dado, nome de cliente, credencial ou lógica de negócio de sistemas reais deve ser referenciado neste repositório.

## Convenções técnicas

Ver `docs/technical/guidelines/` (coding-standards, dependency-injection, error-handling, logging) e `docs/technical/ci-cd.md` (gates de qualidade, cobertura mínima, pipeline).
