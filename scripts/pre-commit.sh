#!/usr/bin/env bash
# Quality gate executed before every commit.
# Required by /wiz-next. Runs the same checks as the CI pipeline
# (see docs/technical/ci-cd.md) so a commit can never introduce a failure
# that CI would catch afterwards.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

log()  { printf '\033[34m[pre-commit]\033[0m %s\n' "$*"; }
fail() { printf '\033[31m[pre-commit] FAIL:\033[0m %s\n' "$*"; FAILED=1; }

run_gate() {
  local label="$1"; shift
  log "$label"
  if ! "$@"; then
    fail "$label"
  fi
}

# --- Backoffice (Node.js / NestJS) -------------------------------------------
BACKOFFICE="$REPO_ROOT/services/payflow-backoffice-api"
if [[ -f "$BACKOFFICE/package.json" ]]; then
  if [[ ! -d "$BACKOFFICE/node_modules" ]]; then
    log "payflow-backoffice-api: node_modules ausente, pulando (rode 'npm install')"
  else
    pushd "$BACKOFFICE" >/dev/null
    run_gate "payflow-backoffice-api: lint"  npm run --silent lint
    run_gate "payflow-backoffice-api: build" npm run --silent build
    run_gate "payflow-backoffice-api: test"  npm run --silent test
    run_gate "payflow-backoffice-api: e2e"   npm run --silent test:e2e
    popd >/dev/null
  fi
fi

# --- CORE services (Go) ------------------------------------------------------
# Enabled per service as each one gains an implementation.
for svc in gateway cashin-service cashout-service webhook-service outbox-relay audit-service; do
  DIR="$REPO_ROOT/services/payflow-$svc"
  [[ -f "$DIR/go.mod" ]] || continue
  pushd "$DIR" >/dev/null
  run_gate "payflow-$svc: vet"  go vet ./...
  run_gate "payflow-$svc: test" go test ./...
  if command -v golangci-lint >/dev/null 2>&1; then
    run_gate "payflow-$svc: lint" golangci-lint run
  else
    log "payflow-$svc: golangci-lint não instalado, pulando lint"
  fi
  popd >/dev/null
done

if [[ "$FAILED" -ne 0 ]]; then
  printf '\033[31m[pre-commit] commit bloqueado — corrija as falhas acima.\033[0m\n'
  exit 1
fi

log "todos os gates passaram"
