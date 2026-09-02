# Alfredo

[English](README.md) · [Español](README.es.md)

O Alfredo é uma infraestrutura local-first para engenharia assistida por IA de forma durável e portável.

Agentes e chats são temporários. Memória de projeto, estado de tarefas, skills, regras, templates e contexto não deveriam ser. O Alfredo mantém essa camada durável em arquivos controlados pelo desenvolvedor e renderiza as partes certas para o target de agente que você escolher explicitamente.

## O Que O Alfredo Entrega

- Setup portável para Codex, Claude Code, Cursor, Antigravity/GCA, Devin, Gemini CLI, Via e targets genéricos baseados em diretório.
- Memória durável para conhecimento de usuário e projeto fora do chat atual.
- Pacotes de contexto determinísticos para uma tarefa específica.
- Skills, regras, personas, sub-agentes, templates, scripts, assets e referências portáveis.
- Runtime durável de tarefas com tarefas, dependências, donos, sessões, checkpoints, bloqueios, validações e próximas ações.
- Fontes de pacote somente leitura, resolução de dependências, lockfiles, instalação transacional, status, diff, update e uninstall seguro.
- Operação local-first: o estado permanece legível, versionável, recuperável e inspecionável na máquina do desenvolvedor.

## Como Funciona

```text
estado canônico do Alfredo
        |
        v
fontes, pacotes, memória, tarefas, contexto
        |
        v
adaptadores de target
        |
        v
Codex / Claude Code / Cursor / Antigravity / Devin / Gemini CLI / Via / genérico
```

Diretórios de provider como `.codex/`, `.claude/`, `.cursor/`, `.gemini/`, `.devin/`, `.via/`, `.agents/` e `.alfredo/` são saídas dos adaptadores. Eles não são o quadro canônico, a memória ou a fonte da verdade.

## Conceitos Centrais

### Memória

Memória responde: "o que sabemos?"

Ela guarda decisões duráveis, fatos, convenções, aprendizados e histórico relevante em dois escopos:

- `~/.alfredo/memory/` para conhecimento que vale entre projetos.
- `<repo>/.alfredo/memory/` para conhecimento que só faz sentido em um repositório.

A memória é append-only por desenho. Journals crescem com o tempo, notas são escritas uma vez e índices derivados podem ser regenerados. A busca funciona offline por palavras-chave. Embeddings locais opcionais via Ollama melhoram o ranking quando disponíveis e voltam para palavras-chave quando indisponíveis.

### Contexto

Contexto responde: "o que esta tarefa deve carregar agora?"

Projetos podem declarar tópicos de contexto em `.alfredo/config.yaml`. Uma tarefa pode referenciar tópicos e arquivos. `alfredo context build ALF-...` retorna um pacote determinístico `alfredo.context/v1` com fontes agrupadas e estimativa aproximada de tokens, para que agentes carreguem material relevante em vez de redescobrir o projeto a cada sessão.

### Skills

Skills são guias portáveis de capacidade. Cada skill vive em `skills/<nome>/SKILL.md`, com referências, scripts e assets opcionais carregados apenas quando necessário. Skills tornam o comportamento do agente ensinável sem despejar todos os detalhes em todo prompt.

### Regras

Regras são restrições e padrões sempre ativos. Elas vivem em `rules/` e são renderizadas pelos adaptadores para cada target selecionado. Use regras para comportamentos que devem valer amplamente; use skills para procedimentos específicos de tarefa.

### Personas

Personas são arquivos leves de voz e preferências. Elas vivem em `personas/` e podem ser semeadas nos targets sem sobrescrever edições locais do usuário em updates futuros.

### Templates

Templates descrevem a forma desejada de um artefato de saída: voz, estrutura, tamanho, formato e restrições. O Alfredo fornece o schema e os comandos; equipes criam e empacotam seus próprios templates.

Ao criar um template, pergunte ou informe o tipo, para que ele serve e o formato
de saída. O formato é aberto: targets conhecidos são sugestões, e um projeto
pode definir um target de texto puro, arquivo customizado ou renderer
específico. Templates em branco são gravados no repositório em
`templates/<name>/TEMPLATE.md`, não no perfil do usuário, para poderem ser
empacotados ou exportados depois.

### Pacotes E Fontes

Pacotes agrupam conteúdo canônico em unidades instaláveis versionadas. Um pacote declara seus targets suportados, dependências, conflitos e caminhos de conteúdo. Fontes são catálogos somente leitura, locais, Git ou archives. Instalar pacotes escreve nos adaptadores de target, nunca na fonte.

### Targets E Adaptadores

Um target é um ambiente explícito de agente, como `codex`, `claude-code`, `cursor`, `antigravity`, `devin`, `gemini-cli`, `via` ou `generic`. Um adaptador mapeia conteúdo canônico do Alfredo para o layout de diretórios daquele target.

`alfredo setup --all` instala apenas os targets que foram declarados pelos pacotes oficiais descobertos e já estão configurados no escopo local selecionado. Ele não instala em todo adapter embutido só porque o Alfredo sabe que ele existe.

### Runtime De Tarefas

Runtime de Tarefas responde: "o que estamos fazendo agora?"

Projetos mantêm estado durável de trabalho em `.alfredo/` e estado local de máquina em `.alfredo/runtime/`. As entidades centrais são:

- Run: um objetivo maior ou unidade de orquestração.
- Task: uma unidade durável de trabalho com critérios de aceite e dependências.
- Session: uma instância temporária de worker usando um adapter/provider suportado.

`READY` é derivado, não persistido. Uma tarefa está pronta quando está em `BACKLOG`, não tem dono, não está bloqueada ou terminal, e todas as dependências estão `DONE`.

Fluxos de desenvolvimento maiores terminam com uma checagem de fechamento:
revisar o conjunto de READMEs em busca de comportamento ou notas de setup
desatualizados e revisar os itens alterados para ver se algo precisa ir para a
memória antes de reportar a tarefa master como completa.

## Instalação

macOS e Linux:

```sh
curl -fsSL https://raw.githubusercontent.com/faustobdls/alfredo/main/scripts/install.sh | sh
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/faustobdls/alfredo/main/scripts/install.ps1 | iex
```

O instalador baixa a release mais recente do GitHub para a plataforma atual, valida o checksum SHA-256, instala em `~/.alfredo/bin` e atualiza o PATH do shell atual. Defina `ALFREDO_INSTALL_DIR` para escolher outro destino.

## Setup De Targets

Instale pacotes oficiais em todos os targets configurados e declarados por esses pacotes:

```sh
alfredo setup --all
```

Instale apenas targets selecionados:

```sh
alfredo setup --codex
alfredo setup --cursor --gemini-cli
alfredo setup --devin --via
alfredo setup --claude-code
alfredo setup --antigravity
alfredo setup --generic
```

Use `--scope project` para instalar no projeto atual em vez do escopo de usuário, e `--force` para sobrescrever arquivos gerenciados modificados localmente.

## Comandos Comuns

```sh
alfredo init source ./minha-fonte
alfredo source add canonical --local ./minha-fonte
alfredo package list
alfredo package install android-core --target codex --scope user
alfredo package status --target codex
alfredo update --dry-run
alfredo upgrade --check
alfredo template new email-cliente --kind email --description "Use para email de cliente. Nao para chat interno." --format-target email
alfredo template validate email-cliente
```

```sh
alfredo memory setup --target codex
alfredo memory add "documentei o runtime de tarefas"
alfredo memory add --kind note --title "Decisao de runtime" "tarefas sao canonicas"
alfredo memory list --since 30d
alfredo memory search "handoff de tarefa"
alfredo memory digest --since 14d
alfredo memory capture
```

```sh
alfredo task create --title "Implementar suporte a reconnect"
alfredo task ready
alfredo session start --adapter codex
alfredo task claim ALF-... --adapter codex --session SES-...
alfredo task start ALF-...
alfredo task checkpoint ALF-... --completed "protocolo" --current "testes"
alfredo task verify ALF-...
alfredo task done ALF-...
alfredo task resume ALF-...
alfredo context build ALF-...
```

A maioria dos comandos de runtime suporta `--json` para agentes e ferramentas.

## Estrutura Do Repositório

```text
alfredo/
├── .github/             # CI, atualizacoes de dependencias e templates do repo
├── adapters/            # Adaptadores de instalacao e renderizacao por agente
├── agents/              # Sub-agentes canonicos
├── cli/                 # CLI Dart multiplataforma e entrada do executavel nativo
├── docs/                # Documentacao de arquitetura e migracoes
├── packages/            # Bundles instalaveis de conteudo canonico
├── personas/            # Seeds de voz e preferencias duraveis
├── profiles/            # Selecoes reproduziveis pessoais, trabalho e projeto
├── rules/               # Regras canonicas sempre ativas
├── schemas/             # Contratos JSON versionados
└── skills/              # Skills portaveis canonicas
```

## Notas De Arquitetura

- [Adaptadores De Agente](docs/architecture/agent-adapters.md)
- [Agentes](docs/architecture/agents.md)
- [Motor De Contexto](docs/architecture/context-engine.md)
- [Memória](docs/architecture/memory.md)
- [Personas](docs/architecture/personas.md)
- [Regras](docs/architecture/rules.md)
- [Skills](docs/architecture/skills.md)
- [Runtime De Tarefas](docs/architecture/task-runtime.md)
- [Templates](docs/architecture/templates.md)

## Desenvolvimento

```sh
cd cli
dart pub get
dart format .
dart analyze
dart test
```
