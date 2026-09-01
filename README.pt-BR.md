# Alfredo

[English](README.md) · [Español](README.es.md)

O Alfredo é um ecossistema local-first para distribuir conhecimento reutilizável entre agentes de IA e construir fluxos reproduzíveis de engenharia Android. O projeto é organizado como monorepo para que o instalador de linha de comando, as skills portáveis, os adaptadores específicos de cada agente e o HUD local existente possam evoluir de forma independente sobre uma base única e versionada.

## Objetivos

- Manter as mesmas skills, regras e rotinas nos ambientes pessoal e de trabalho.
- Instalar capacidades selecionadas no Codex, Claude Code, Cursor, Antigravity e agentes futuros sem depender de MCP.
- Tratar repositórios externos de skills como fontes somente leitura e instalar snapshots imutáveis.
- Fornecer uma CLI Dart multiplataforma distribuída como binário nativo para macOS, Windows e Linux.
- Construir uma camada segura de automação Android e ADB capaz de coordenar vários dispositivos pelo serial.
- Manter dados privados e execução local sob controle explícito do usuário.

## Estado atual

O repositório contém atualmente:

- A CLI Dart inicial, gerada com o template Dart CLI da Very Good Ventures.
- O ponto de entrada nativo `alfredo`, com ajuda, versão e suporte a completion do shell.
- Contratos v1 versionados para manifestos de fonte, pacote e perfil.
- Fontes locais, Git e archives com checksum, validadas e armazenadas como snapshots imutáveis.
- Descoberta determinística, resolução de dependências, lockfiles e controle do estado instalado.
- Instalação transacional, status, diff e desinstalação segura nos escopos de usuário e projeto.
- Adaptadores para Codex, Claude Code, Cursor, Antigravity e destino genérico.
- O pacote `android-core` com cinco skills Android validadas.
- O subsistema `alfredo memory`, append-only, com busca por palavra-chave, embeddings locais opcionais e o pacote `memory-core`.
- O HUD FastAPI existente, isolado em `apps/hud/`.
- Raízes versionadas para skills, pacotes, regras, adaptadores, schemas e perfis.
- CI da CLI Dart em macOS, Linux e Windows, além da suíte de testes Python do HUD.

Perfis, releases assinados e comandos Android que atuam nos dispositivos permanecem como próximas etapas.

## Instalar a CLI

macOS e Linux (x64 ou ARM64):

```sh
curl -fsSL https://raw.githubusercontent.com/faustobdls/alfredo/main/scripts/install.sh | sh
```

Windows PowerShell (x64):

```powershell
irm https://raw.githubusercontent.com/faustobdls/alfredo/main/scripts/install.ps1 | iex
```

O instalador baixa o binário correto da release mais recente no GitHub, valida
seu checksum SHA-256, instala em `~/.alfredo/bin` e inclui esse diretório no PATH
do usuário para o shell atual. Defina `ALFREDO_INSTALL_DIR` para escolher outro
destino.

Instale os pacotes oficiais em todos os agentes suportados:

```sh
alfredo setup --all
```

Ou selecione um ou mais agentes:

```sh
alfredo setup --cursor
alfredo setup --codex --claude
alfredo setup --antigravity
```

O comando `setup` configura automaticamente a fonte oficial correspondente à
release da CLI instalada e usa o escopo do usuário por padrão. Passe
`--scope project` para instalar no projeto atual.

Para criar uma release, o mantenedor atualiza `cli/pubspec.yaml`, executa
`dart run build_runner build` dentro de `cli/`,
atualiza este changelog e faz o merge em `main`. O workflow valida a versão,
executa as verificações da CLI, compila todos os artefatos suportados, cria a tag
anotada `vX.Y.Z`, gera as notas com Conventional Commits e publica binários e
checksums no GitHub Releases. O envio manual de uma tag correspondente continua
suportado.

## Estrutura do repositório

```text
alfredo/
├── .github/             # CI, atualização de dependências e templates do repositório
├── adapters/            # Adaptadores de instalação e renderização por agente
├── agents/              # Sub-agentes canônicos, respondendo como Alfredo
├── apps/
│   └── hud/             # HUD FastAPI local e frontend do navegador
├── cli/                 # CLI Dart multiplataforma e entrada do binário nativo
├── docs/                # Decisões arquiteturais e documentação transversal
├── packages/            # Conjuntos instaláveis de skills, regras, agentes e assets
├── profiles/            # Configurações reproduzíveis pessoais, de trabalho e projeto
├── rules/               # Regras canônicas de comportamento e engenharia
├── schemas/             # Contratos versionados de fontes, pacotes, perfis e lockfiles
└── skills/              # Skills portáveis canônicas dos agentes de IA
```

### `.github/`

Contém as automações do repositório. `alfredo_cli.yaml` formata, analisa, testa e compila a CLI Dart nas três famílias de sistemas operacionais. `alfredo_hud.yaml` instala e testa o HUD Python. O Dependabot consulta os pacotes Dart em `cli/`.

### `cli/`

Contém o pacote Dart puro `alfredo_cli` e o executável `alfredo`. Ele implementa:

- Fontes locais, Git/archive somente leitura e snapshots imutáveis.
- Busca no catálogo e resolução determinística de pacotes.
- Instalação transacional, status, diff e remoção segura.
- Escopos de usuário e projeto.
- Seleção explícita de adaptadores para cinco destinos.
- Futuros comandos multi-device em `alfredo android`.

A CLI não depende do runtime Flutter. Os binários nativos serão compilados no próprio sistema operacional de destino.

### `skills/`

A fonte canônica das skills reutilizáveis — guias de capacidade sob demanda, cada uma um diretório com `SKILL.md` obrigatório. Duas famílias: **skills de domínio** (`android-core`: kernel, internos da plataforma, desenvolvimento nativo, segurança de apps, frotas ADB) e **skills de workflow** (`skills-core`: `autopilot`, `ralph`, `ralplan`, `ultrawork`, `ultraqa`, `team`, `plan`, `deep-interview`, `trace`, `deslop`, `map-project` — métodos de orquestração faseados e verificados na voz do Alfredo). Veja [docs/architecture/skills.md](docs/architecture/skills.md).

As versões específicas para cada agente devem ser geradas desse conteúdo canônico, e não mantidas como cópias independentes.

### `agents/`

O catálogo canônico de sub-agentes. Um arquivo Markdown por agente, no formato de sub-agente do Claude Code, todos respondendo **como Alfredo** — o mordomo-engenheiro da casa: preciso, imperturbável e exigente com padrões. O pacote `agents-core` os distribui; o `alfredo setup` os instala no diretório de agentes de cada destino. Veja [docs/architecture/agents.md](docs/architecture/agents.md).

### `packages/`

Contém pacotes instaláveis. Um pacote pode agrupar várias skills, regras, scripts, referências e requisitos de adaptadores em uma unidade versionada, como `android-core`, `adb-device-fleet` ou `android-security`.

Pacotes declararão dependências, conflitos, targets suportados e versões semânticas. Uma skill ensina uma capacidade; um pacote distribui um conjunto de capacidades.

### `rules/`

Restrições e padrões sempre-ativos — um arquivo Markdown por regra, para ficar no contexto do agente em toda tarefa. O pacote `rules-core` distribui nove na voz do Alfredo (menor mudança, verificar antes de afirmar, seguir o estilo da casa, commits atômicos, limites de autorização, relato fiel, perguntar só quando travado, segredos e exfiltração, separar autoria de revisão); o `memory-core` adiciona duas do subsistema de memória. Os adaptadores as convertem para o formato nativo de cada agente. Veja [docs/architecture/rules.md](docs/architecture/rules.md).

### `adapters/`

Contém lógica e templates de instalação para Codex, Claude Code, Cursor, Antigravity e destinos genéricos baseados em diretório. Os adaptadores conhecem os caminhos e formatos de cada agente, mas não são donos do conhecimento canônico.

### `schemas/`

Contém contratos v1 legíveis por máquina para fontes, pacotes, perfis, estado instalado e lockfiles. A validação acontece antes de persistir uma fonte ou escrever no ambiente de um agente.

### `profiles/`

Conterá definições declarativas como `personal`, `work` ou perfis específicos de projeto. Um perfil seleciona fontes, pacotes, versões, escopos e targets. Junto com um lockfile, permitirá reproduzir a mesma instalação em máquinas diferentes.

### `apps/hud/`

Contém o HUD local-first existente:

- `app/`: backend FastAPI, providers, roteamento, memória, ferramentas e voz.
- `web/`: interface estática servida pelo FastAPI.
- `tests/`: suíte de regressão Python.
- `docs/`: notas de implementação específicas do HUD.
- `pyproject.toml`: pacote e dependências Python.

O HUD pode chamar providers locais ou remotos controlados. Ele permanece separado da CLI Dart para que os dois produtos possam executar, testar e ser distribuídos de forma independente. Consulte [apps/hud/README.md](apps/hud/README.md) para API, privacidade e configuração.

### `docs/`

Contém documentação aplicável a todo o ecossistema, incluindo registros de migração e futuras decisões arquiteturais. Documentação específica de uma aplicação permanece junto dela.

## Modelo de fontes

As fontes do Alfredo são somente leitura do ponto de vista da CLI:

- O CRUD de fontes altera apenas o cadastro local.
- Uma fonte Git é baixada como snapshot associado a um commit.
- Um archive exige metadados de integridade, como SHA-256.
- Instalar ou atualizar pacotes nunca executa commit, push, merge, tag nem edita a origem.
- As versões instaladas serão registradas em lockfile determinístico.

Os repositórios de origem são mantidos e publicados por seus próprios fluxos. O Alfredo apenas os consome.

Para começar um novo:

```sh
alfredo init source ./minha-origem
```

Isso cria o manifesto, as raízes de conteúdo (`skills/`, `rules/`, `agents/`, `profiles/`), um pacote de exemplo e um README. `--id` e `--name` sobrescrevem os padrões; `--force` permite um diretório não vazio.

## Memória

O Alfredo mantém um registro local e durável do que foi decidido e do que foi feito, para que o agente recarregue contexto em uma sessão futura em vez de deduzi-lo novamente.

A memória fica em `.alfredo/memory/` e existe em dois escopos independentes: `~/.alfredo/memory/` para práticas que valem em qualquer projeto e `<repo>/.alfredo/memory/` para fatos que só fazem sentido dentro de um repositório. Cada store contém um `journal/` append-only com arquivos diários, um diretório `notes/` com um fato durável por arquivo, um `index/` gerado e um `MEMORY.md` derivado. Apenas o `MEMORY.md` é regerado; os journals crescem por concatenação e as notas nunca são sobrescritas.

A recuperação funciona sem rede. A busca por palavra-chave está sempre disponível. Quando um Ollama local está acessível, o `alfredo memory setup` pode habilitar a busca por embeddings, e a busca volta silenciosamente para palavras-chave sempre que o provedor estiver indisponível. O setup reaproveita qualquer modelo de embedding conhecido que você já tenha baixado (`nomic-embed-text`, `mxbai-embed-large`, `bge-m3`, `snowflake-arctic-embed2`, `embeddinggemma`, entre outros); um modelo só é baixado com confirmação explícita do operador.

| Comando | Efeito |
| --- | --- |
| `alfredo memory setup` | Cria o store, configura a recuperação e instala o `memory-core` |
| `alfredo memory add <mensagem>` | Registra uma entrada no journal, ou uma nota com `--kind note --title` |
| `alfredo memory search <consulta>` | Ordena os documentos da memória, com fallback para palavra-chave |
| `alfredo memory list --since 7d` | Exibe as entradas recentes do journal, das mais novas para as mais antigas |
| `alfredo memory digest --since 14d` | Gera um resumo compacto agrupado por dia |
| `alfredo memory index` | Gera embeddings dos documentos novos e alterados e remove os excluídos |
| `alfredo memory capture` | Registra o encerramento de uma sessão de trabalho |

Defina `ALFREDO_MEMORY_HOME` para mover o store do usuário. Veja [docs/architecture/memory.md](docs/architecture/memory.md) para o contrato em disco e as invariantes de segurança.

## Desenvolvimento

### Requisitos

- Dart 3.12 ou mais recente para desenvolver a CLI.
- Python 3.13 para desenvolver o HUD.
- Git.
- Ferramentas específicas da plataforma para gerar releases nativas.

### CLI Dart

```bash
cd cli
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos --fatal-warnings
dart test
dart run bin/alfredo.dart --help
dart run bin/alfredo.dart source add canonical --local ..
dart run bin/alfredo.dart package install android-core --target codex --scope user
dart run bin/alfredo.dart update --dry-run
dart run bin/alfredo.dart update
dart run bin/alfredo.dart upgrade --check
dart run bin/alfredo.dart memory setup --all --source canonical
dart run bin/alfredo.dart memory add "explorei o cadastro de fontes"
dart run bin/alfredo.dart memory digest --since 14d
```

Compile um executável nativo no sistema atual:

```bash
cd cli
mkdir -p build
dart compile exe bin/alfredo.dart -o build/alfredo
./build/alfredo --version
```

### HUD Python

Crie o ambiente compartilhado a partir da raiz:

```bash
python3.13 -m venv .venv
source .venv/bin/activate
python -m pip install -e "apps/hud[dev]"
cp apps/hud/.env.example apps/hud/.env
```

Execute os testes e o servidor:

```bash
cd apps/hud
../../.venv/bin/python -m pytest -q
../../.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8765 --reload
```

Abra `http://127.0.0.1:8765` depois que o servidor iniciar.

## Princípios de segurança

- Nunca versionar `.env`, credenciais, caches ou binários gerados.
- Não expor um shell genérico a um modelo de IA.
- Endereçar dispositivos Android explicitamente pelo serial.
- Separar observação, mudanças de aplicação, ações privilegiadas e operações autorizadas de laboratório de segurança.
- Validar conteúdo e caminhos antes da instalação.
- Usar staging, backup e atualização atômica do estado instalado.
- Manter execução remota e fallback explícitos para o usuário.

## Roadmap

1. Adicionar perfis declarativos, atualização, rollback e bundles offline.
2. Publicar binários assinados para macOS, Windows e Linux.
3. Construir comandos Android e ADB multi-device que atuem nos dispositivos.
4. Expandir as skills Android com referências, scripts e laboratórios versionados.

## Idiomas da documentação

- English: [README.md](README.md)
- Português do Brasil: [README.pt-BR.md](README.pt-BR.md)
- Español: [README.es.md](README.es.md)
