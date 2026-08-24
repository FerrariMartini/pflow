# Guideline — Error handling

## General principle

Business error (rule violated) and technical error (infrastructure unavailable) are different things and must be handled differently. Never use a generic exception for both cases — whoever reads the log or HTTP response needs to know, without investigating code, whether a business rule rejected the operation or a system failure occurred.

## Backoffice (Node.js/NestJS — `payflow-backoffice-api`)

- Business errors are typed subclasses of `DomainError` (`src/common/errors/domain-error.ts`), each with a stable `code` (`TRANSACTION_NOT_FOUND`, `INVALID_RECONCILIATION_TRANSITION`) — that `code` is public contract (see `docs/contract/contract.md`), it cannot change without versioning the API.
- Translation of `DomainError` to HTTP status happens in a single place (`DomainExceptionFilter`), never scattered in each controller — avoids inconsistency (the same error type returning different status depending on who wrote the endpoint).
- Technical error (database unavailable, network timeout) does not become `DomainError` — propagates as unhandled exception, which NestJS converts to generic 500; we do not hide infrastructure failure behind a business message.
- Never `throw new Error("string qualquer")` in business rule code — if it is not a typed `DomainError`, it is not an expected error, and should surface as 500 (signal of bug, not rule).

## CORE (domain services in Go)

- Business errors as sentinel variables per package (`var ErrTransactionNotFound = errors.New(...)`) or custom error types when they need to carry additional context, compared with `errors.Is`/`errors.As` — never error message string comparison.
- `panic` is reserved for unrecoverable programming error (e.g., mandatory configuration missing at boot); never used in business rule flow or request handler.
- Every function that can fail returns `error` as the last value — no exception to the idiomatic language pattern, even under deadline pressure.

## What never to do (in both cases)

- Swallow error silently (`catch {}` empty / `if err != nil { }` without action).
- Log and rethrow the same error at the same call level (duplicates log noise without adding information).
- Expose stack trace or infrastructure error message (e.g., connection string) in HTTP response to external client.
