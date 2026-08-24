# Guideline — Injeção de dependência

## Backoffice (Node.js/NestJS — `payflow-backoffice-api`)

- Usar o container de DI nativo do NestJS (`@Injectable`, construtor injection) — nunca instanciar dependência manualmente dentro de um service (`new SomeService()`), pois quebra a substituição por mock em teste e o ciclo de vida gerenciado pelo framework.
- Dependências de infraestrutura (repositório, cliente HTTP, cliente de fila) são injetadas por **interface/token**, não pela implementação concreta — o módulo decide qual implementação real é usada; o service depende apenas do contrato. Isso é o que permite `TransactionsService` ser testado com um repositório em memória sem qualquer mock framework (ver `transactions.service.spec.ts`).
- Escopo padrão é singleton (`DEFAULT`); usar escopo `REQUEST` apenas quando houver estado por requisição que realmente não pode ser singleton (ex: contexto de usuário autenticado) — escopo `REQUEST` tem custo de performance (nova instância por requisição) e deve ser exceção, não padrão.

## CORE (serviços de domínio em Go)

- Sem framework de DI mágico (sem reflection-based container) — injeção manual via construtor (`func NewService(repo Repository, publisher EventPublisher) *Service`), seguindo o padrão de arquitetura hexagonal já adotado (`internal/domain`, `internal/usecase`, `internal/adapter`).
- `main.go` (ou `cmd/`) é o único lugar que conhece as implementações concretas (adapters); tudo abaixo disso depende de interface definida no próprio pacote de domínio/usecase que a consome (Dependency Inversion — quem define a interface é quem consome, não quem implementa).
- Isso mantém `internal/domain` sem nenhum import de infraestrutura (nem driver de banco, nem SDK de Kafka), o que é validado por lint de arquitetura no CI (ver `docs/technical/ci-cd.md`).
