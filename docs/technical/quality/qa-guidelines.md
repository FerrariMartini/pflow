# QA — guidelines and definitions

## Expected test pyramid per service

```
        /  e2e (few, critical paths)  \
       /------------------------------------\
      /   integration (contract, real DB)  \
     /----------------------------------------\
    /   unit (business rules, majority)   \
```

- **Unit**: covers isolated business rule (state machine, calculation, validation). Most tests live here — they are the fastest and give earliest feedback. See coverage criterion in `docs/technical/ci-cd.md`.
- **Integration/contract**: validates that the service talks correctly to its real dependencies (database, broker) and that published/consumed event schema matches `docs/contract/contract.md`. Runs against containerized dependencies in CI, never mocked at this level.
- **E2E**: few scenarios, only paths that matter end to end (e.g., "cash-in created → confirmed → webhook delivered → visible in backoffice"). Not for covering business rule variation (that is the unit test's role).

## Definition of Ready (for QA to accept a milestone)

A milestone (see `.wiz/<slug>/phases/`) is ready to be tested when:
1. Acceptance criteria are written in testable form (not "should work well", but a verifiable condition).
2. Relevant edge cases are listed (not only the happy path).
3. API/event contract (if applicable) is defined in `docs/contract/contract.md` before implementation, not discovered during testing.

## Definition of Done (from QA perspective)

1. All gates from `docs/technical/ci-cd.md` green.
2. Edge case from acceptance criteria has automated test — QA should not depend on repeated manual testing for a rule that is already known.
3. For services that move value (`cashin`, `cashout`): idempotency test (duplicate request) and invalid state transition test are mandatory, not optional.
4. Manual exploratory testing (short session, risk-driven) done before promotion to production, focused on what automation tends not to cover well: behavior under integrator error (malformed payload, misbehaving integrator), error UX in backoffice.

## Test data

- `dev`/`staging` environments use synthetic/anonymized data (see `docs/technical/infrastructure/aws-architecture.md`) — never real production data replicated for testing.
- Test data mass for reconciliation scenarios deliberately includes divergence cases (transaction confirmed in hub but not in simulated provider) — testing only the path where everything matches hides exactly the scenario `payflow-backoffice-api` exists to handle.

## When QA blocks a release

- Any regression in idempotency or state machine tests in cash-in/cash-out services is automatic block, no deadline exception.
- Absence of automated test for a new `DomainError` (see `docs/technical/guidelines/error-handling.md`) is a review block, not accepted as technical debt "for later".
