# Parecer Técnico e Plano de Melhoria/Evolução do Alfredo

## 1. Sumário Executivo e Opinião Crítica

O **Alfredo** é uma solução elegante e altamente necessária no ecossistema atual de desenvolvimento assistido por Inteligência Artificial (AI-assisted engineering). Seu propósito fundamental — fornecer uma camada local, durável, auditável e portátil de memória, contexto, tarefas, regras, capacidades (skills) e instâncias de agentes — ataca diretamente a principal fraqueza dos assistentes de IA contemporâneos: a efemeridade das sessões de chat e a fragmentação de instruções entre diferentes ferramentas (Codex, Claude Code, Cursor, Gemini CLI, Devin, etc.).

### Principais Qualidades Identificadas:
1. **Arquitetura Sólida e Limpa (Clean Architecture):** A transição recente do projeto para uma CLI escrita em Dart (estruturada em `cli/lib/src/`) demonstra um excelente padrão de modularização (`command_runner`, subgrupos de comandos, repositórios/stores isolados e suporte nativo a JSON com `--json`).
2. **Qualidade do Código e Testes:** A suíte de testes em Dart cobre contratos de pacotes, esquemas JSON, gerenciadores de memória, tarefas, atualizações e sincronização de pacotes (`265` testes executados com 100% de aprovação e zero alertas no `dart analyze`).
3. **Padrão Local-First e Durabilidade:** Armazenamento em repositório (`.alfredo/`) e no ambiente do usuário (`~/.alfredo/`), utilizando YAML/JSON com esquemas rígidos e versionamento previsível.
4. **Respeito aos Limites e Adaptação Multi-Engine:** O conceito de *adapters* e a separação clara entre a verdade canônica e os artefatos gerados para cada ferramenta de IA.

### Oportunidades de Evolução e Gaps Relevantes:
1. **Developer Experience (DX) & Sandbox/Telemetry:** Durante a execução de rotinas padrão da CLI (como `dart test`), a telemetria nativa do Dart tenta escrever no diretório global do usuário (`~/.dart-tool`), causando exceções de permissão em ambientes de sandbox controlados ou restritos. O script de inicialização do engine fvm/dart também esbarra em permissões locais sem um tratamento gracioso.
2. **Rastreabilidade e Telemetria Integrada do Task Runtime:** O modelo de tarefas registra eventos (`task-events/`), porém falta uma visualização agregada de métricas de execução (ex: tempo em `IN_PROGRESS`, taxa de bloqueio, esforço gasto por agente/adaptador).
3. **Integração e Automação de Adaptações Local-First:** Embora existam adaptadores para diversos targets (Codex, Claude Code, Cursor, Gemini CLI, Devin, Via), o diretório `adapters/` na raiz contém apenas um `.gitkeep`, e a lógica de renderização/instalação fica espalhada ou delegada. Uma padronização declarativa mais forte para novos adaptadores facilitaria a contribuição da comunidade.
4. **Indexação e Busca Semântica Híbrida em Memória:** A recuperação em memória (`memory`) conta com busca por palavras-chave e embeddings via Ollama local. Há espaço para otimizar o algoritmo de ranking híbrido (BM25 + Cosine Similarity) e tolerância a falhas na ausência do servidor Ollama local.
5. **Automação de Validação Contínua (CI/CD Hooks):** Integração dos testes de contrato de esquemas (`schemas/*.json`) diretamente como git hooks locais (`pre-commit`) via CLI do Alfredo.

---

## 2. Diagnóstico Detalhado por Camada

### A. CLI & Engenharia de Software (Dart CLI)
- **Status:** Excelente organização de pastas em `cli/lib/src/` (`memory`, `package`, `source`, `task_runtime`, `template`, `upgrade`).
- **Pontos Fracos:** Dependência de variáveis de ambiente globais sem fallback para caminhos de telemetria/cache temporários quando em ambientes isolados; mensagens de erro de I/O em permissões de diretório podem ser tratadas com mitigação automática (`catch` defensivo em chamadas de I/O).

### B. Sistema de Memória e Vetores (Memory Engine)
- **Status:** Suporta diários (`journal`), notas (`notes`) e índice de vetores.
- **Pontos Fracos:** Dependência do Ollama para embeddings locais sem alternativa lightweight embarcada em C/Dart nativo ou WASM; suporte a limite de contextos grandes pode se beneficiar de sumarização automática incremental (roll-up de diários).

### C. Task Runtime & Workflow Sync
- **Status:** Fluxo estruturado de estados (`BACKLOG` -> `READY` -> `IN_PROGRESS` -> `VERIFY` -> `DONE`).
- **Pontos Fracos:** Falta comando nativo de *dashboard* ou *summary* visual na CLI para ver progresso dos pacotes de trabalho e tarefas em pipelines concorrentes.

---

## 3. Plano Estruturado de Melhoria e Evolução

O plano a seguir está organizado em 4 fases incrementais, priorizando estabilidade, DX, expansão de recursos e ecossistema.

```text
+-------------------------------------------------------------------------+
|                    PLANO DE EVOLUÇÃO DO ALFREDO                         |
+-------------------------------------------------------------------------+
|  FASE 1: Fortalecimento de DX, Resiliência & Ambientes Isolados          |
|  FASE 2: Evolução do Memory Engine & Busca Híbrida Avançada            |
|  FASE 3: Expansão do Task Runtime (Métricas, Visualização e Hooks)      |
|  FASE 4: Arquitetura Plugável de Adaptações e Comunidade               |
+-------------------------------------------------------------------------+
```

### Fase 1: Fortalecimento de DX, Resiliência & Ambientes Isolados
*Meta: Garantir execução perfeita em sandboxes, CI/CD e ambientes restritos sem falhas de I/O de telemetria ou caminhos padrão.*

- [x] **1.1. Resiliência de I/O na CLI:** ✅ Concluído (`ALF-01M2H033V2M8FHENBRT8`)
  - Implementado `scripts/dart-sandbox.sh`: resolve o binário real do Dart SDK (bypass do wrapper `fvm`, que falha com `Operation not permitted` ao tentar gravar em seu próprio cache de instalação) e isola `$HOME` em `.alfredo/runtime/dart-sandbox-home` (git-ignored), preservando `PUB_CACHE` real para não perder pacotes já baixados.
  - Documentado o uso do wrapper em `README.md` (raiz) e `cli/README.md`.
  - Validado: `pub get`, `dart analyze --fatal-infos --fatal-warnings`, `dart format --set-exit-if-changed .` e `dart test` (265 testes) passam com exit 0 via o wrapper, neste mesmo ambiente que antes falhava.
- [ ] **1.2. Automação de Scripts de Inicialização:**
  - Refatorar `scripts/install.sh` e `scripts/install.ps1` para validar automaticamente permissões de pastas de cache e binários instalados.

### Fase 2: Evolução do Memory Engine & Busca Híbrida Avançada
*Meta: Aumentar a precisão e velocidade na recuperação de conhecimento do projeto.*

- [x] **2.1. Algoritmo de Ranking Híbrido Ajustável:** ✅ Concluído (`ALF-01M2H2FDGR1B27APQCMP`, addendum `ALF-01M2H3BXCQ6DJE67GK82`)
  - Substituída a contagem bruta de termos por um BM25 real em `cli/lib/src/memory/keyword_search.dart` (IDF por frequência de documento no corpus, saturação de frequência de termo com `k1=1.5`, normalização por tamanho de documento com `b=0.75`).
  - Criado `cli/lib/src/memory/hybrid_search.dart` com `combineHybridHits`, que normaliza cada ranking (léxico e vetorial) ao seu próprio máximo antes de combiná-los, evitando misturar escalas incompatíveis (BM25 vs. cosseno).
  - Adicionado o parâmetro `vectorWeight` em `MemoryStore.search` (0 = somente léxico, 1 = somente vetorial, padrão 1 para preservar compatibilidade) e a flag `--weight` em `alfredo memory search`.
  - Validado com 13 novos testes (`hybrid_search_test.dart`, extensões em `vector_index_test.dart` e `memory_command_test.dart`, incluindo um teste de saturação BM25) e reescrita das asserções de `keyword_search_test.dart` que assumiam contagem bruta. Suíte completa: 282/282 testes passando via `scripts/dart-sandbox.sh test`; `dart analyze --fatal-infos --fatal-warnings` e `dart format --set-exit-if-changed` limpos.
- [ ] **2.2. Sumarização Incremental de Diários (Memory Roll-up):**
  - Adicionar o comando `alfredo memory compact` para consolidar diários antigos (`journal/YYYY/MM/`) em notas de histórico de longo prazo, mantendo o consumo de tokens sob controle.

### Fase 3: Expansão do Task Runtime (Métricas, Visualização e Hooks)
*Meta: Transformar o Task Runtime em um centro de comando visual e auditável para múltiplos agentes.*

- [x] **3.1. Relatórios e Métricas de Tarefas (`alfredo task report`):** ✅ Concluído (ALF-01M2H1DSNZZY7GZDXMH7)
  - Criado `cli/lib/src/task_runtime/task_runtime_report.dart` com `TaskRuntimeReport.build`, que reconstrói o histórico de status por tarefa a partir de `.alfredo/task-events/` (`created/claimed/started/blocked/unblocked/verifying/done/cancelled/released`) e calcula tempo-em-status, contagem de ciclos `BLOCKED`, duração `VERIFYING → DONE` e tempo total em `DOING` por adaptador dono.
  - Adicionado o subcomando `alfredo task report` (texto legível e `--json`) em `cli/lib/src/commands/task_command.dart`, seguindo o padrão de formatação já usado por `task resume`/`task show`.
  - Validado com `alfredo task report`/`--json` rodando contra o `.alfredo/` real do próprio repositório (11 tarefas, nenhuma bloqueada, ~1h20m de tempo total em `DOING` do adapter `codex`) e com testes unitários novos (`task_runtime_report_test.dart`: lifecycle completo, ciclos `blocked/unblocked` repetidos, tarefa sem eventos, serialização JSON) mais um teste de comando ponta a ponta em `task_runtime_command_test.dart`. Suíte completa: 269/269 testes passando via `scripts/dart-sandbox.sh test`; `dart analyze --fatal-infos --fatal-warnings` e `dart format --set-exit-if-changed` limpos.
- [x] **3.2. Visualizador Terminal Rich Text (TUI / Board):** ✅ Concluído (`ALF-01M2H51SX7SE2T8QKQDN`)
  - Criado `cli/lib/src/task_runtime/task_runtime_board.dart` com `TaskBoard.build`, que agrupa tarefas em colunas `READY` (backlog já desbloqueado), `IN_PROGRESS` (`CLAIMED`+`DOING`), `VERIFYING` e `BLOCKED`, ordenadas por prioridade e idade, além de contadores agregados de tarefas aguardando dependências, `DONE` e `CANCELLED`.
  - Adicionado o subcomando `alfredo task board` em `cli/lib/src/commands/task_command.dart`, com saída texto colorida por status via ANSI (`mason_logger`/`package:io`), `--json` para consumo programático, e `--watch --interval N` para redesenho periódico (com `--max-iterations` oculta, usada apenas em testes).
  - **Decisão de escopo registrada:** o plano pede um "modo interativo"; como o `pubspec.yaml` não traz nenhuma biblioteca de TUI (apenas `mason_logger`/`io` para ANSI), a entrega é um snapshot textual colorido com redesenho por polling (`--watch`), não uma TUI com captura de teclado/navegação. Adicionar uma lib de TUI completa (ex.: `dart_console`) ficaria fora do escopo atual sem justificativa de dependência nova.
  - Validado com 9 testes novos em `task_runtime_board_test.dart` (agrupamento por status, dependências pendentes, ordenação por prioridade, cálculo de idade, serialização JSON) e 3 testes de comando em `task_runtime_command_test.dart` (renderização texto/JSON, `--watch` com `--max-iterations`, validação de `--interval` inválido). Suíte completa: 293/293 testes passando (1 skip pré-existente não relacionado) via `scripts/dart-sandbox.sh test`; `dart analyze --fatal-infos --fatal-warnings` e `dart format --set-exit-if-changed` limpos.
- [ ] **3.3. Git Hooks Nativos (`alfredo hooks install`):**
  - Permitir a verificação automática de contratos de esquemas JSON e validação de tarefas em progresso antes de autorizar commits Git.

### Fase 4: Arquitetura Plugável de Adaptações e Comunidade
*Meta: Facilitar a criação de adaptadores customizados para novas ferramentas de IA.*

- [ ] **4.1. Framework de Adaptadores Declarativos:**
  - Padronizar o diretório `adapters/` com especificações declarativas (`adapter.yaml`) para mapear regras, personas e skills em qualquer target desconhecido sem necessidade de alterar o código-fonte em Dart da CLI.
- [ ] **4.2. Sistema de Publicação e Registro de Pacotes Terceiros:**
  - Expandir o comando `alfredo source` para permitir busca e sincronização de registros remotos públicos/privados de pacotes Alfredo.

---

## 4. Matriz de Impacto vs. Esforço

| Ação de Melhoria | Impacto | Esforço | Prioridade |
| :--- | :---: | :---: | :---: |
| Resiliência de I/O e DX em Sandboxes | **Alto** | Baixo | **P1 (Imediata)** |
| Relatórios e Métricas no Task Runtime (`task report`) | **Alto** | Médio | **P1 (Imediata)** |
| Algoritmo de Ranking Híbrido no Memory Engine | Médio | Médio | P2 |
| TUI Interativa para visualização de Tarefas (`task board`) | Médio | Alto | P2 |
| Framework Declarativo de Adaptações em `adapters/` | **Alto** | Alto | P3 |
| Sumarização Incremental de Diários (`memory compact`) | Baixo | Médio | P3 |

---

## 5. Conclusão e Próximos Passos

O **Alfredo** possui uma base arquitetural excepcionalmente bem projetada e madura para seu estágio. Executar as Fases 1 e 3 consolidará a CLI como a ferramenta definitiva para gerenciamento de estado de engenharia auxiliada por IA, eliminando atritos de ambiente e maximizando a visibilidade do progresso do projeto.

---

## 6. Evidências de Verificação Empírica

Cada gap listado acima foi confirmado diretamente no repositório antes da publicação deste plano, para evitar afirmações especulativas:

- **Gap de I/O em sandbox (Fase 1.1) — ✅ corrigido:** reproduzido inicialmente ao executar `dart --version`/`dart analyze` neste ambiente — o wrapper do fvm chamava `upgrade_flutter`/`update_engine_version.sh`, que tenta gravar em `.../bin/cache/engine.stamp.tmp.*` e `.../bin/cache/engine.realm` fora do workspace e falha com `Operation not permitted`, mesmo definindo `HOME`/`PUB_CACHE` locais. Corrigido com `scripts/dart-sandbox.sh` (bypassa o wrapper invocando `<version_root>/bin/cache/dart-sdk/bin/dart` diretamente e isola `$HOME` para evitar a escrita de telemetria em `~/.dart-tool`, preservando `$PUB_CACHE` real). Validado com `pub get`, `analyze --fatal-infos --fatal-warnings`, `format --set-exit-if-changed .` e `test` (269/269) passando de ponta a ponta neste sandbox. Documentado em `README.md` e `cli/README.md`.
- **Ausência de `task report`/`task board` (Fase 3.1/3.2) — ambos ✅ implementados:** `alfredo task --help` listava apenas `create, list, ready, show, depend, claim, start, checkpoint, block, unblock, verify, done, release, cancel, resume`. Implementado `alfredo task report` (`cli/lib/src/task_runtime/task_runtime_report.dart` + subcomando em `task_command.dart`), consolidando `.alfredo/task-events/` em métricas de tempo-em-status, taxa de bloqueio e velocidade de verificação; validado contra os dados reais do próprio repositório e com 5 testes automatizados novos. Implementado `alfredo task board` (`cli/lib/src/task_runtime/task_runtime_board.dart`), um snapshot textual colorido por status com `--json` e `--watch`; ver nota de escopo no item 3.2 sobre a ausência de biblioteca de TUI no projeto.
- **`adapters/` sem framework declarativo (Fase 4.1):** o diretório raiz `adapters/` contém somente `.gitkeep`; nenhuma especificação `adapter.yaml` ou similar existe hoje.
- **Sem peso ajustável na busca híbrida (Fase 2.1):** `cli/lib/src/memory/keyword_search.dart` implementa apenas contagem de termos (sem BM25 real nem parâmetro de mistura com o índice vetorial); `alfredo memory search --help`/código de `memory_command.dart` não expõem nenhum argumento de peso léxico/vetorial.
- **CI existente (`--fatal-infos --fatal-warnings`):** `.github/workflows/alfredo_cli.yaml` já roda `dart analyze` estrito, mas não há hook local de pre-commit nem validação de contratos de `schemas/*.json` antes do commit, confirmando a lacuna descrita em 5. da seção de oportunidades.
- **Fluxo de tarefas Alfredo aplicado a este próprio trabalho:** esta avaliação foi conduzida como tarefa durável (`alfredo task create/claim/start/checkpoint`), demonstrando na prática o Task Runtime descrito acima e servindo de dogfooding para o próprio plano.
