# ADR-0002: Backoffice API mantém read model próprio, alimentado por eventos

**Status**: Aceito

## Contexto

O time de operação precisa consultar transações com filtros, busca e paginação eficientes, sem impactar a performance dos serviços transacionais (cash-in/cash-out), que são otimizados para escrita de alto throughput, não para consulta ad-hoc.

## Alternativas consideradas

1. **Backoffice consulta diretamente o banco de cash-in/cash-out**: acopla o schema interno desses serviços à necessidade de consulta do backoffice, e qualquer mudança de schema vira uma mudança coordenada entre times.
2. **Backoffice expõe um proxy que chama a API de cash-in/cash-out em tempo real**: evita acoplamento de schema, mas gera carga de leitura sobre serviços críticos de escrita e gera indisponibilidade em cascata.
3. **Backoffice mantém seu próprio read model, populado de forma assíncrona a partir dos eventos de domínio publicados via Kafka**: desacopla schemas, isola carga de leitura, e o backoffice pode modelar os dados especificamente para os padrões de consulta operacional (ex: índices por período, por status, por integrador).

## Decisão

Adotar a opção 3. `payflow-backoffice-api` consome eventos de domínio (`transaction.created`, `transaction.confirmed`, `transaction.failed`, etc.) e mantém uma tabela de leitura desnormalizada, otimizada para os casos de uso de consulta e conciliação do time de operação.

## Consequências

- Prós: nenhuma pressão de leitura sobre os serviços transacionais; modelagem de dados livre para otimizar consulta; falha temporária no backoffice não afeta o fluxo de pagamento.
- Contras: introduz *eventual consistency* — é necessário comunicar claramente na UI quando um dado pode estar alguns segundos desatualizado. Também exige lógica de reconciliação para lidar com eventos fora de ordem ou reprocessados (idempotência no consumidor).
