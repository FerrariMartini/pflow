# AI-Augmented SDLC — o ciclo completo

Este documento descreve, fase a fase, como a IA participa do ciclo de vida do software neste projeto, e onde a decisão humana é obrigatória. A responsabilidade final por correção, segurança e qualidade é sempre do desenvolvedor — a estrutura abaixo existe para tornar isso verificável, não apenas afirmado.

## 1. Planejamento: de PRD a milestone rastreável

A camada de planejamento é o **PayFlow SDLC Kit** (`.claude/agents/wiz-*.md`, `.claude/commands/wiz-*.md`), fork adaptado do [wiz-cursor](https://github.com/NSXBet/wiz-cursor) — ver `.claude/NOTICE.md` para o que foi portado e o que foi estendido neste repositório.

1. O PRD (`docs/product/PRD.md`) e a especificação técnica (`docs/technical/`) são escritos com apoio de IA para estruturação, mas as decisões de escopo e prioridade são humanas — a IA aponta lacunas, não decide.
2. `/wiz-prd <slug> "<ideia>"` gera o PRD de planejamento por Q&A. As perguntas de esclarecimento são geradas pela IA e **respondidas por humano** — é assim que hallucination é contida nesta etapa: o plano não avança sem decisão explícita nos pontos que exigem julgamento (política de teste, prioridade de NFR, trade-off de escopo).
3. `/wiz-phases <slug>` decompõe o PRD em **fases**, e `/wiz-milestones <slug>` decompõe cada fase em **milestones** identificadas no formato `P0XM0Y` (fase X, milestone Y). O estado de planejamento fica em `.wiz/<slug>/` — `prd.md`, `phases/phaseN.md`, e depois `reviews/` e `retros/`. O mapeamento desse plano para board (épico / task / subtask) existia via skill + API do Jira e está descrito em `.claude/jira-visibility.md`; neste repositório não é executado.
4. Uma milestone só é implementável quando tem **critério de aceite testável** (Definition of Ready, ver `docs/technical/quality/qa-guidelines.md`). O contexto que rege a implementação não fica embutido na milestone: `.wiz/context/authoritative-sources.md` aponta para as guidelines em `docs/technical/guidelines/` que devem ser carregadas da fonte a cada execução — é isso que permite implementar sem inventar requisito nem depender de a IA "lembrar" a convenção.

Cada linha de código é rastreável a um requisito aprovado por humano — não a uma conversa solta com a IA.

## 2. Arquitetura e ADRs

- Trade-offs (monólito vs. microsserviços, outbox vs. publicação direta no broker, gateway centralizado vs. autenticação distribuída) são discutidos com a IA como *sparring partner*: a proposta vem da experiência com sistemas de pagamento, a IA ajuda a mapear consequências e casos de borda.
- Toda decisão arquitetural relevante vira ADR (`docs/decisions/`), com alternativas consideradas e consequências — não só a decisão final.

## 3. Implementação

`/wiz-next [slug]` executa a próxima milestone `🚧 TODO`:

1. Lê o critério de aceite da milestone e carrega o contexto local (fase + guidelines apontadas por `.wiz/context/authoritative-sources.md`).
2. Consulta o especialista de linguagem (`wiz-typescript-specialist` para o Backoffice, `wiz-go-specialist` para CORE, entre outros) quando a aplicação da guideline deixa dúvida.
3. Implementa.
4. Roda os gates locais — lint, build, testes (`docs/technical/ci-cd.md`, `scripts/pre-commit.sh`).
5. O especialista de linguagem revisa o diff, **obrigatoriamente antes do commit** — um check de padrão de código, não uma auditoria completa de NFRs. Reprovado exige correção e nova revisão antes de prosseguir.
6. Commit em Conventional Commits, com o status da milestone atualizado para `✅ COMPLETE`.

Essa revisão do especialista é local a cada milestone. A auditoria formal contra os gates P0–P4 é feita sob demanda, separadamente: `/wiz-review-milestone <slug> <id>` para uma milestone específica, `/wiz-review-phase <slug> <n>` para a fase inteira — ambas delegam ao agente `wiz-reviewer` e a nota vai para `.wiz/<slug>/reviews/`.

Fora do fluxo de milestone — correção de bug, investigação pontual, ajuste de documentação — o trabalho é conduzido por prompt estruturado direto, sem passar pelos comandos `wiz-*`. Ver `docs/technical/prompt-engineering.md`.

## 4. Testes

Testes unitários e e2e são derivados dos critérios de aceite e dos casos de borda especificados na milestone (idempotência, transição de estado inválida, payload malformado) — não gerados a partir do código já escrito, o que produziria testes que apenas confirmam o comportamento existente sem validar a regra de negócio.

## 5. Revisão e qualidade

- Cada milestone corresponde a um ou poucos commits pequenos e descritivos, revisáveis isoladamente.
- Os gates de CI (`docs/technical/ci-cd.md`) são os mesmos independente de o código ter sido escrito com ou sem IA.
- A revisão formal produz artefato: quando `/wiz-review-milestone` ou `/wiz-review-phase` roda, a nota vai para `.wiz/<slug>/reviews/`, seguindo o `PULL_REQUEST_TEMPLATE.md` — o que foi checado contra as guidelines aplicáveis, achados (inclusive os não-bloqueantes, registrados como débito técnico consciente em vez de omitidos) e veredito.
- Achado de review não termina no commit: ao fechar uma fase, `/wiz-retro` (agente `wiz-retro-analyst`) agrupa os achados das reviews da fase por tipo de desvio e decide, por grupo, se vira atualização de guideline, ADR, ou permanece débito aceito (`docs/technical/retrospective.md`). O relatório vai para `.wiz/<slug>/retros/`.
- Métricas do processo definidas em `docs/technical/quality/ai-process-metrics.md`.

## 6. Limites e responsabilidade

- Decisões de segurança (`docs/technical/architecture/security.md`) são especificadas e validadas por humano; a IA implementa seguindo a especificação, não o contrário.
- Os agentes do SDLC Kit **deferem** a `docs/technical/guidelines/` — nenhum carrega convenção própria. Um agente com opinião divergente da guideline documentada criaria uma segunda fonte de verdade, e é isso que a regra de fonte única evita.
- Nenhum dado, credencial ou lógica de negócio de sistemas reais é usado como entrada para a IA neste projeto.
