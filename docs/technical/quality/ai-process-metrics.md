# Métricas do processo de IA

`ai-augmented-sdlc.md` e as notas de review descrevem o processo. Este documento define o que medir para saber se ele está funcionando. Este repositório ainda não tem execução suficiente (milestones implementadas, histórico de commits) para apurar números reais — as métricas abaixo são a definição de processo a ser coletada conforme o trabalho avança, não um retrato do que já aconteceu.

## Métricas definidas

### 1. Taxa de achado em review
% de milestones cuja nota de review (`.wiz/<slug>/reviews/`, produzida pelo `wiz-reviewer` via `/wiz-review-milestone` ou `/wiz-review-phase`) registrou algum achado — não necessariamente bloqueante. Taxa alta não é ruim por si só: indica que a revisão está de fato acontecendo. Taxa **zero** ao longo de muitas milestones é sinal de alerta — revisão superficial, ou achados sendo omitidos.

### 2. Cobertura de teste do domínio de negócio (não cobertura agregada)
% de cobertura das classes que carregam regra de negócio (`*.service.ts` em Node, `internal/domain`+`internal/usecase` em Go) — não da cobertura agregada do serviço, que mistura regra de negócio com boilerplate de framework (controller, DTO, módulo) que teste unitário não deveria precisar cobrir (ver `docs/technical/quality/qa-guidelines.md`, pirâmide de teste).

### 3. Taxa de retrabalho pós-commit
% de commits que precisaram de um commit de correção subsequente por causa de algo que já deveria ter sido pego em review (não conta correção por mudança de requisito). Distingue-se de "achado em review": achado pré-commit é o processo funcionando; correção pós-commit é o processo falhando.

### 4. Lead time por milestone
Tempo entre uma milestone atingir a Definition of Ready (`qa-guidelines.md`) e o commit que a fecha. Ainda não coletado — depende da instrumentação descrita em Limitações.

### 5. Origem do código (IA vs. humano)
Não tratado como percentual de linhas — isso é fácil de medir e fácil de enganar (ex: um humano que só aceita 100% do que a IA sugere sem ler gera o mesmo "% humano" de um humano que reescreve tudo). Tratado qualitativamente: o que a IA gerou como rascunho, o que o humano decidiu/corrigiu/rejeitou, registrado na nota de review de cada milestone (`.wiz/<slug>/reviews/`).

## Limitações da coleta atual

- **Lead time ainda não é coletado.** Exige os timestamps de dois eventos: quando a milestone atinge a Definition of Ready (`.wiz/<slug>/phases/`) e quando o commit que a fecha é criado. A fonte é o próprio estado em `.wiz/<slug>/` (fase → milestone), não um board externo.
- **Sem dashboard.** A coleta é manual: ler as notas de review (`.wiz/<slug>/reviews/`) e o histórico de commits. Automatizar exige um job que faça essa leitura periodicamente e publique o resultado na mesma infraestrutura de métricas do produto (`docs/technical/architecture/observability.md`), não em ferramenta separada.
- **Sem execução suficiente para inferência.** Com poucas milestones implementadas, qualquer percentual calculado descreveria uma amostra pequena demais para virar meta de processo — a leitura correta desses números, quando existirem, é "o que aconteceu nesta fase", não um benchmark.
