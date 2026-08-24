# Visibilidade no Jira (fora deste repositório)

No processo original de controle e visibilidade do SDLC, os artefatos de `.wiz/<slug>/` eram projetados para um board. Uma Cursor Skill lia o planejamento gerado pelo kit (`prd.md`, `phases/phaseN.md` e as milestones `P0XM0Y` dentro de cada fase) e criava issues via API REST do Jira, com este mapeamento:

| Artefato em `.wiz/<slug>/` | Issue no Jira |
|---|---|
| `prd.md` | documentação do **épico** |
| cada `phases/phaseN.md` | **task** filha do épico |
| cada milestone `P0XM0Y` | **subtask** filha da task da fase |

A fonte de verdade do plano continuava no Git (`.wiz/<slug>/`). O Jira era a camada de visibilidade para gestão — não substituto do planejamento.

Essa skill e as chamadas à API **não fazem parte deste repositório**: não há skill versionada, não há script de exportação e não há credencial. Aqui o rastreio é `.wiz/<slug>/` + `/wiz-status`. Este arquivo registra o processo; não o executa.
