# NOTICE

O **PayFlow SDLC Kit** — os agentes e comandos em `.claude/agents/` e `.claude/commands/` — é um fork adaptado do **[wiz-cursor](https://github.com/NSXBet/wiz-cursor)**, framework open source de agentes de IA para SDLC criado pela NSXBet.

Não escrevi a ferramenta. O que fiz foi adaptá-la para rodar neste projeto:

- **Portada de Cursor para Claude Code** — os agentes ganharam frontmatter (`name`/`description`) para serem registrados como subagentes, e as referências de delegação passaram de caminho de arquivo (`.cursor/agents/*.md`) para nome de agente.
- **Estado por PRD, na raiz** — cada PRD tem seu próprio diretório `.wiz/<slug>/` (ex. `.wiz/backoffice-api/`), com `prd.md`, `phases/`, `reviews/` e `retros/`. Não é um `.wiz/` por serviço nem um único `.wiz/` compartilhado por todos os PRDs — o slug do PRD é o que separa o estado de planejamentos distintos, mesmo quando vários PRDs vivem no mesmo serviço.
- **Contexto local apontando para `docs/`** — as guidelines, ADRs e contratos do repositório entram como contexto autoritativo do planejamento, de modo que a ferramenta siga os padrões já definidos aqui em vez dos seus defaults.
- **`/wiz-retro` e `wiz-retro-analyst`** — o wiz-cursor upstream não tem um comando de retrospectiva de fase. Esta é uma extensão real feita neste fork (não apenas uma adaptação de algo que já existia): um comando e um agente novos que agrupam os achados das revisões de uma fase encerrada e decidem, para cada grupo, se vira débito aceito, atualização de guideline ou ADR. Ver `.claude/commands/wiz-retro.md` e `.claude/agents/wiz-retro-analyst.md`.

A mecânica de planejamento — geração de PRD por Q&A, decomposição em fases e milestones, gates de qualidade, revisão por especialista de linguagem — é do wiz-cursor.

## Licença original

Distribuído sob licença MIT, copyright NSXBet. O aviso abaixo é reproduzido conforme exigido pelos termos da licença:

```
MIT License

Copyright (c) NSXBet

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
```

Ver o repositório original para o texto completo e atualizado da licença.
