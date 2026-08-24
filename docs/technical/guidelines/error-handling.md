# Guideline — Tratamento de erros

## Princípio geral

Erro de negócio (regra violada) e erro técnico (infraestrutura indisponível) são coisas diferentes e devem ser tratados de forma diferente. Nunca usar exceção genérica para os dois casos — quem lê o log ou a resposta HTTP precisa saber, sem investigar código, se foi uma regra de negócio rejeitando a operação ou uma falha de sistema.

## Backoffice (Node.js/NestJS — `payflow-backoffice-api`)

- Erros de negócio são subclasses tipadas de `DomainError` (`src/common/errors/domain-error.ts`), cada uma com um `code` estável (`TRANSACTION_NOT_FOUND`, `INVALID_RECONCILIATION_TRANSITION`) — esse `code` é contrato público (ver `docs/contract/contract.md`), não pode mudar sem versionar a API.
- A tradução de `DomainError` para status HTTP acontece em um único lugar (`DomainExceptionFilter`), nunca espalhada em cada controller — evita inconsistência (o mesmo tipo de erro retornando status diferente dependendo de quem escreveu o endpoint).
- Erro técnico (banco indisponível, timeout de rede) não vira `DomainError` — propaga como exceção não tratada, que o NestJS converte em 500 genérico; não escondemos falha de infraestrutura atrás de uma mensagem de negócio.
- Nunca `throw new Error("string qualquer")` em código de regra de negócio — se não é um `DomainError` tipado, não é um erro esperado, e deve estourar como 500 mesmo (sinal de bug, não de regra).

## CORE (serviços de domínio em Go)

- Erros de negócio como variáveis sentinela por pacote (`var ErrTransactionNotFound = errors.New(...)`) ou tipos de erro customizados quando precisam carregar contexto adicional, comparados com `errors.Is`/`errors.As` — nunca comparação de string de mensagem de erro.
- `panic` é reservado para erro de programação irrecuperável (ex: configuração obrigatória ausente no boot); nunca usado em fluxo de regra de negócio ou request handler.
- Toda função que pode falhar retorna `error` como último valor — sem exceção ao padrão idiomático da linguagem, mesmo sob pressão de prazo.

## O que nunca fazer (nos dois casos)

- Engolir erro silenciosamente (`catch {}` vazio / `if err != nil { }` sem ação).
- Logar e relançar o mesmo erro no mesmo nível de chamada (duplica ruído no log sem agregar informação).
- Expor stack trace ou mensagem de erro de infraestrutura (ex: string de conexão) na resposta HTTP para o cliente externo.
