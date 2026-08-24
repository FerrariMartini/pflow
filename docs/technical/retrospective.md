# Retrospectiva e melhoria contínua

Os demais documentos (`docs/technical/guidelines/`, `docs/technical/ci-cd.md`) descrevem o padrão atual. Este documento define **quando e como esse padrão muda** — sem isso, guideline vira documento estático que ninguém revisita, e o mesmo erro se repete em serviços diferentes porque a lição da primeira vez nunca voltou pra regra escrita.

## Gatilhos de retrospectiva

Não é só "depois de um incidente em produção" — isso é tarde demais e caro demais como único gatilho. Gatilhos, do mais barato ao mais caro:

1. **Fim de uma fase** — ao fechar todas as milestones de uma fase, `/wiz-retro <slug> <fase>` revisita as notas de review daquela fase (`.wiz/<slug>/reviews/`) em conjunto, não isoladamente. Um achado isolado é um achado; o mesmo tipo de achado em duas milestones da mesma fase é um padrão.
2. **Sinal em `docs/technical/quality/ai-process-metrics.md`** — se a taxa de achado em review para um tipo específico de desvio se repete entre serviços diferentes, a guideline (não a implementação) provavelmente está pouco clara ou desatualizada.
3. **Incidente em produção** (ver `docs/technical/infrastructure/sre-runbook.md`) — o gatilho mais caro. Todo incidente cuja causa raiz é rastreável a uma implementação que seguiu a guideline corretamente, mas a guideline estava errada/incompleta, gera atualização obrigatória da guideline como parte do encerramento do incidente — não é opcional nem faseado para "depois".

## O que decidir numa retrospectiva

Para cada achado revisitado, a decisão é uma destas três — e a retro precisa registrar explicitamente qual foi escolhida, não deixar implícito:

- **Manter como débito técnico aceito** — o achado é real, mas o custo de generalizar uma regra a partir de uma única ocorrência é maior que o risco de deixar como está. Continua sendo monitorado (próxima ocorrência do mesmo padrão vira gatilho automático de revisão).
- **Atualizar a guideline** — o achado se repetiu ou o impacto justifica mudar a regra escrita, não só o código de um serviço. A guideline correspondente em `docs/technical/guidelines/` é editada e recebe, ao fim do arquivo, uma entrada de histórico: data, motivo e link para a retro que originou a mudança. Guideline alterada sem essa entrada perde a rastreabilidade de por que mudou.
- **Virar ADR** — se a mudança tem trade-off arquitetural relevante (não é só estilo/convenção), vira um ADR novo em `docs/decisions/`, não só uma edição silenciosa da guideline.

## Onde as retrospectivas ficam

`.wiz/<slug>/retros/phase-<n>-retro.md` — uma por fase encerrada, não uma por milestone: a granularidade de milestone já está nas notas de review em `.wiz/<slug>/reviews/`.

O comando `/wiz-retro` delega ao agente `wiz-retro-analyst`, que lê as notas de review da fase, agrupa achados por tipo de desvio e exige uma das três decisões acima para cada um — incluindo, quando a decisão é manter o débito, o gatilho explícito que a reabriria. `/wiz-retro` e `wiz-retro-analyst` são uma extensão feita neste fork sobre o wiz-cursor upstream, que não tinha um comando de fechamento de fase equivalente (ver `.claude/NOTICE.md`).

## Por que isso fecha o ciclo do SDLC assistido por IA

Sem esse mecanismo, cada nova sessão de IA (ver `docs/technical/prompt-engineering.md`, gestão de janela de contexto) reaprenderia — ou pior, não reaprenderia — a mesma lição que uma sessão anterior já pagou o preço de descobrir. A retro é o que transforma um achado de review de "informação perdida numa conversa antiga" em "regra persistida que a próxima sessão consulta via `.wiz/context/authoritative-sources.md`".
