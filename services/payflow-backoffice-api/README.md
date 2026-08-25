# payflow-backoffice-api

Operational backoffice API for PayFlow Hub (NestJS 11, TypeScript 5.6, Node.js 24).

## Prerequisites

- Node.js 24.x
- npm 10+

## Setup

```bash
npm install
```

`npm install` runs the `prepare` script, which configures [Husky](https://typicode.github.io/husky/) git hooks for this repository.

### Git hooks (Husky)

Hooks live under `.husky/` in this service directory. After `npm install`, Git uses them automatically via `core.hooksPath`.

If hooks are not running (e.g. after a fresh clone), re-run from this directory:

```bash
npm install
# or explicitly:
npm run prepare
```

**Hooks enabled:**

| Hook | Action |
|---|---|
| `pre-commit` | `lint-staged` — ESLint `--fix` and Prettier on staged `*.ts` files |
| `commit-msg` | `commitlint` — Conventional Commits with required scope `backoffice-api` |

**Commit message format:**

```
<type>(backoffice-api): <description>
```

Examples:

- `feat(backoffice-api): add tenant list endpoint`
- `fix(backoffice-api): handle missing correlation id`

## Scripts

| Script | Description |
|---|---|
| `npm run build` | Production build |
| `npm run start:dev` | Dev server with watch (port 3001) |
| `npm run lint` | ESLint on `src/` and `test/` |
| `npm run format` | Prettier write |
| `npm run format:check` | Prettier check |
| `npm test` | Unit tests (Jest) |
| `npm run test:e2e` | E2E tests (supertest) |

## Quality gates

Repository-wide checks run via `scripts/pre-commit.sh` at the monorepo root. Service-local hooks enforce lint/format on staged TypeScript and commit message conventions before each commit.
