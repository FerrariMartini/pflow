# QA — diretrizes e definições

## Pirâmide de teste esperada por serviço

```
        /  e2e (poucos, caminhos críticos)  \
       /------------------------------------\
      /   integração (contrato, banco real)  \
     /----------------------------------------\
    /   unitário (regra de negócio, maioria)   \
```

- **Unitário**: cobre regra de negócio isolada (máquina de estados, cálculo, validação). Maioria dos testes vive aqui — são os mais rápidos e os que dão feedback mais cedo. Ver critério de cobertura em `docs/technical/ci-cd.md`.
- **Integração/contrato**: valida que o serviço conversa corretamente com suas dependências reais (banco, broker) e que o schema de evento publicado/consumido bate com `docs/contract/contract.md`. Roda contra dependências containerizadas em CI, nunca mockadas nesse nível.
- **E2E**: poucos cenários, só os caminhos que importam de ponta a ponta (ex: "cash-in criado → confirmado → webhook entregue → visível no backoffice"). Não é para cobrir variação de regra de negócio (isso é papel do unitário).

## Definition of Ready (para QA aceitar uma milestone)

Uma milestone (ver `.wiz/<slug>/phases/`) está pronta para ser testada quando:
1. Critério de aceite está escrito de forma testável (não "deve funcionar bem", e sim uma condição verificável).
2. Casos de borda relevantes estão listados (não só o caminho feliz).
3. Contrato de API/evento (se aplicável) está definido em `docs/contract/contract.md` antes da implementação, não descoberto durante o teste.

## Definition of Done (do ponto de vista de QA)

1. Todos os gates de `docs/technical/ci-cd.md` verdes.
2. Caso de borda dos critérios de aceite tem teste automatizado — QA não deve depender de teste manual repetido para regra que já é conhecida.
3. Para serviços que movimentam valor (`cashin`, `cashout`): teste de idempotência (requisição duplicada) e teste de transição de estado inválida são obrigatórios, não opcionais.
4. Teste exploratório manual (sessão curta, roteirizada por risco) feito antes de promoção para produção, focado no que automação tende a não cobrir bem: comportamento sob erro de integrador (payload malformado, integrador mal-comportado), UX de erro no backoffice.

## Dados de teste

- Ambientes `dev`/`staging` usam dados sintéticos/anonimizados (ver `docs/technical/infrastructure/aws-architecture.md`) — nunca dado real de produção replicado para teste.
- Massa de teste para cenários de conciliação inclui deliberadamente casos de divergência (transação confirmada no hub mas não no provedor simulado) — testar só o caminho onde tudo bate esconde exatamente o cenário que `payflow-backoffice-api` existe para tratar.

## Quando QA bloqueia um release

- Qualquer regressão em teste de idempotência ou de máquina de estados nos serviços de cash-in/cash-out é bloqueio automático, sem exceção por prazo.
- Ausência de teste automatizado para um novo `DomainError` (ver `docs/technical/guidelines/error-handling.md`) é bloqueio de review, não é aceito como débito técnico "para depois".
