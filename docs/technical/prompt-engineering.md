# Structured prompt — work outside the milestone flow

Planned work is conducted by the PayFlow SDLC Kit (`/wiz-prd`, `/wiz-phases`, `/wiz-milestones`, `/wiz-next`, `/wiz-retro` — see `.claude/NOTICE.md` and `/wiz-help`), which already encapsulates role, rules, and acceptance criteria in agents and commands.

This document covers the other regime: work that **does not** fit a planned milestone — bug fix, point technical investigation, isolated architecture decision, documentation adjustment. Here the prompt is assembled on the fly, and the structure below is what keeps quality predictable.

## Prompt structure

| Element | What it is | Where it is supported in this project |
|---|---|---|
| **System / Role** | Role the model adopts. Works as a lens for judgment and prioritization. | `CLAUDE.md` (root and per service) — persistent repository layer. |
| **Context** | Documentation, input data, current system state. | `docs/product/PRD.md`, `docs/technical/architecture/`, `.wiz/<slug>/` (PRD, phases and milestones from planned work). |
| **Rules** | Patterns and conventions the output must follow. | `docs/technical/guidelines/` — coding-standards, dependency-injection, error-handling, logging. |
| **Tools** | What the model can execute, not just describe. | Bash, Read/Edit/Write, repository search, MCP when applicable. |
| **Output** | What to deliver, where, and how correctness is proven. | Explicit verifiable condition: passing test, clean CI gate, specific file updated. |
| **Examples (few-shot)** | 1-2 concrete examples when the result is format-sensitive. | Commit format, DTO shape — reduces variance more than prose instruction. |
| **Negative constraints** | What **not** to do, explicitly. | `CLAUDE.md`, "Scope rules" section. |
| **Modes** | Plan / Debug / Ask — separate alignment from execution. | Plan mode for structural decision; direct execution when the path is already agreed. |

Order matters: **context and verification before output**. Editing first and verifying later is the most costly mistake in this regime, because it produces confident change on top of a wrong premise.

## Context is not automatic

Claude Code does not maintain a vector index of the codebase. Search is **agentic**: on each turn the model decides what to look for and triggers `grep`/`glob`/`Read`/subagents on demand — retrieval guided by reasoning, not pre-indexed similarity.

The practical consequence: relevant context only enters if explicitly referenced, or if the search the model decides to run reaches it. There is no guarantee it will find the right convention on its own. That is why this repository maintains `.wiz/context/authoritative-sources.md` pointing each milestone to the guidelines in `docs/technical/guidelines/` that govern it, and `docs/` as the single source — both exist to make the rule findable, not to document for documentation's sake.

## Context window management

Long context is not free. Response quality degrades as input grows — the phenomenon known as **context rot** — even before the window fills. The cause is attention distribution: information in the middle of a long context receives less weight than information at the beginning or end (U-shaped pattern; accuracy drops more than 30% when relevant data is buried in the middle). In long sessions this is a direct cause of hallucination: the model does not locate the right information in accumulated noise and fills the gap.

Adopted practice:

1. **Monitor window size** throughout the session (`/context`), without letting it accumulate until forced compaction.
2. **One session per task** — context from a previous task is noise for the next.
3. **Re-reference artifacts when opening a new session** (`CLAUDE.md`, `.wiz/<slug>/phases/`, guidelines) instead of trusting conversation memory. If the decision is not in a file, it does not exist for the next session — that is why an architectural decision becomes an ADR, and is not left as an agreement in chat.
4. **Delegate high-volume, low-retention work to subagents** — the subagent runs in its own window, does the heavy reading and returns only the conclusion; the volume does not contaminate the main session.

## Sources

- [Context Rot: Why LLMs Degrade as Context Grows](https://www.morphllm.com/context-rot)
- [Context rot explained (& how to prevent it) — Redis](https://redis.io/blog/context-rot/)
- [P6: Context Rot — Hamel's Blog](https://hamel.dev/notes/llm/rag/p6-context_rot.html)
- [Using Claude Code: session management and 1M context — Anthropic](https://claude.com/blog/using-claude-code-session-management-and-1m-context)
- [Explore the context window — Claude Code Docs](https://code.claude.com/docs/en/context-window)
