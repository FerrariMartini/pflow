# Prompt estruturado — trabalho fora do fluxo de milestone

O trabalho planejado é conduzido pelo PayFlow SDLC Kit (`/wiz-prd`, `/wiz-phases`, `/wiz-milestones`, `/wiz-next`, `/wiz-retro` — ver `.claude/NOTICE.md` e `/wiz-help`), que já encapsula papel, regras e critério de aceite em agentes e comandos.

Este documento cobre o outro regime: o trabalho que **não** cabe em uma milestone planejada — correção de bug, investigação técnica pontual, decisão de arquitetura isolada, ajuste de documentação. Aqui o prompt é montado na hora, e a estrutura abaixo é o que mantém a qualidade previsível.

## Estrutura de um prompt

| Elemento | O que é | Onde se apoia neste projeto |
|---|---|---|
| **System / Role** | Papel que o modelo adota. Funciona como lente de julgamento e priorização. | `CLAUDE.md` (raiz e por serviço) — camada persistente do repositório. |
| **Context** | Documentação, dados de entrada, estado atual do sistema. | `docs/product/PRD.md`, `docs/technical/architecture/`, `.wiz/<slug>/` (PRD, fases e milestones do trabalho planejado). |
| **Rules** | Padrões e convenções que a saída deve seguir. | `docs/technical/guidelines/` — coding-standards, dependency-injection, error-handling, logging. |
| **Tools** | O que o modelo pode executar, não só descrever. | Bash, Read/Edit/Write, busca no repositório, MCP quando aplicável. |
| **Output** | O que entregar, onde, e como se prova que está certo. | Condição verificável explícita: teste passando, gate de CI limpo, arquivo específico atualizado. |
| **Exemplos (few-shot)** | 1-2 exemplos concretos quando o resultado é sensível a formato. | Formato de commit, shape de DTO — reduz variância mais que instrução em prosa. |
| **Restrições negativas** | O que **não** fazer, explicitamente. | `CLAUDE.md`, seção "Regras de escopo". |
| **Modos** | Plan / Debug / Ask — separar alinhamento de execução. | Plan mode para decisão estrutural; execução direta quando o caminho já está acordado. |

A ordem importa: **contexto e verificação antes do output**. Editar primeiro e verificar depois é o erro mais caro desse regime, porque produz mudança confiante em cima de premissa errada.

## Contexto não é automático

O Claude Code não mantém índice vetorial da codebase. A busca é **agentic**: a cada turno o modelo decide o que procurar e aciona `grep`/`glob`/`Read`/subagentes sob demanda — recuperação guiada por raciocínio, não por similaridade pré-indexada.

A consequência prática: o contexto relevante só entra se for referenciado explicitamente, ou se a busca que o modelo decidir fazer alcançá-lo. Não há garantia de que ele encontre sozinho a convenção certa. É por isso que este repositório mantém `.wiz/context/authoritative-sources.md` apontando cada milestone para as guidelines em `docs/technical/guidelines/` que a regem, e `docs/` como fonte única — os dois existem para tornar a regra encontrável, não para documentar por documentar.

## Gestão de janela de contexto

Contexto longo não é gratuito. A qualidade de resposta degrada conforme o input cresce — o fenômeno conhecido como **context rot** — mesmo antes de a janela encher. A causa é distribuição de atenção: informação no meio de um contexto longo recebe menos peso que informação no início ou no fim (padrão em U; acurácia cai mais de 30% quando o dado relevante está enterrado no meio). Em sessões longas isso é causa direta de alucinação: o modelo não localiza a informação certa no ruído acumulado e preenche a lacuna.

Prática adotada:

1. **Monitorar o tamanho da janela** ao longo da sessão (`/context`), sem deixar acumular até a compactação forçada.
2. **Uma sessão por tarefa** — contexto de uma tarefa anterior é ruído para a próxima.
3. **Re-referenciar os artefatos ao abrir sessão nova** (`CLAUDE.md`, `.wiz/<slug>/phases/`, guidelines) em vez de confiar em memória de conversa. Se a decisão não está em arquivo, ela não existe para a sessão seguinte — é por isso que decisão arquitetural vira ADR, e não fica combinada no chat.
4. **Delegar trabalho de alto volume e baixa retenção a subagentes** — o subagente roda em janela própria, faz a leitura pesada e devolve só a conclusão; o volume não contamina a sessão principal.

## Fontes

- [Context Rot: Why LLMs Degrade as Context Grows](https://www.morphllm.com/context-rot)
- [Context rot explained (& how to prevent it) — Redis](https://redis.io/blog/context-rot/)
- [P6: Context Rot — Hamel's Blog](https://hamel.dev/notes/llm/rag/p6-context_rot.html)
- [Using Claude Code: session management and 1M context — Anthropic](https://claude.com/blog/using-claude-code-session-management-and-1m-context)
- [Explore the context window — Claude Code Docs](https://code.claude.com/docs/en/context-window)
