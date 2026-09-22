# NOTICE

The **PayFlow SDLC Kit** — agents and commands in `.claude/agents/` and `.claude/commands/` — is a fork adapted from **[wiz-cursor](https://github.com/NSXBet/wiz-cursor)**, an open-source AI agent framework for SDLC created by NSXBet.

I did not write the tool. What I did was adapt it to run in this project:

- **Ported from Cursor to Claude Code** — agents gained frontmatter (`name`/`description`) to register as subagents, and delegation references moved from file paths (`.cursor/agents/*.md`) to agent names.
- **State per PRD, at repository root** — each PRD has its own `.wiz/<slug>/` directory (e.g. `.wiz/backoffice-api/`), with `prd.md`, `phases/`, `reviews/`, and `retros/`. It is not one `.wiz/` per service nor a single `.wiz/` shared by all PRDs — the PRD slug is what separates distinct planning states, even when several PRDs live in the same service.
- **Local context pointing at `docs/`** — repository guidelines, ADRs, and contracts enter as authoritative planning context so the tool follows standards already defined here instead of its defaults.
- **`/wiz-retro` and `wiz-retro-analyst`** — upstream wiz-cursor has no phase retrospective command. This is a real extension in this fork (not merely an adaptation of something that already existed): a new command and agent that group findings from reviews of a closed phase and decide, for each group, whether it becomes accepted debt, a guideline update, or an ADR. See `.claude/commands/wiz-retro.md` and `.claude/agents/wiz-retro-analyst.md`.
- **Jira visibility** — in the original process, a Cursor Skill read `.wiz/<slug>/` and created epic / task / subtask via the Jira REST API. This was **not ported** to this repository: it is not a `wiz-*` command, and there is no skill or credential here. The process is recorded in `.claude/jira-visibility.md`.

Planning mechanics — PRD generation via Q&A, decomposition into phases and milestones, quality gates, review by language specialist — come from wiz-cursor.

## Original license

Distributed under the MIT License, copyright NSXBet. The notice below is reproduced as required by the license terms:

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

See the original repository for the full and current license text.
