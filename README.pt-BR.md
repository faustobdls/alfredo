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
- Cadastro validado de fontes locais somente leitura por `source add`, `list`, `show`, `test` e `remove`.
- Um pacote mínimo `android-core` que exercita o contrato do catálogo.
- O HUD FastAPI existente, isolado em `apps/hud/`.
- Raízes versionadas para skills, pacotes, regras, adaptadores, schemas e perfis.
- CI da CLI Dart em macOS, Linux e Windows, além da suíte de testes Python do HUD.

Fontes Git/archive, instalação de pacotes, adaptadores de agentes e comandos Android são as próximas etapas de implementação.

## Estrutura do repositório

```text
alfredo/
├── .github/             # CI, atualização de dependências e templates do repositório
├── adapters/            # Adaptadores de instalação e renderização por agente
├── apps/
│   └── hud/             # HUD FastAPI local e frontend do navegador
├── cli/                 # CLI Dart multiplataforma e entrada do binário nativo
├── docs/                # Decisões arquiteturais e documentação transversal
├── packages/            # Conjuntos instaláveis de skills, regras, scripts e assets
├── profiles/            # Configurações reproduzíveis pessoais, de trabalho e projeto
├── rules/               # Regras canônicas de comportamento e engenharia
├── schemas/             # Contratos versionados de fontes, pacotes, perfis e lockfiles
└── skills/              # Skills portáveis canônicas dos agentes de IA
```

### `.github/`

Contém as automações do repositório. `alfredo_cli.yaml` formata, analisa, testa e compila a CLI Dart nas três famílias de sistemas operacionais. `alfredo_hud.yaml` instala e testa o HUD Python. O Dependabot consulta os pacotes Dart em `cli/`.

### `cli/`

Contém o pacote Dart puro `alfredo_cli` e o executável `alfredo`. Ele já implementa validação de fontes locais e CRUD do registro. Suas próximas responsabilidades são:

- Download somente leitura e snapshots imutáveis.
- Busca no catálogo e resolução de pacotes.
- Instalação, atualização, diff, rollback e remoção.
- Escopos de usuário e projeto.
- Detecção de agentes e escolha de adaptadores.
- Futuros comandos multi-device em `alfredo android`.

A CLI não depende do runtime Flutter. Os binários nativos serão compilados no próprio sistema operacional de destino.

### `skills/`

É a fonte canônica das skills reutilizáveis. Cada skill será um diretório com `SKILL.md` obrigatório e diretórios opcionais `scripts/`, `references/` e `assets/`. As skills descrevem conhecimento e procedimentos especializados, como kernel Android, desenvolvimento nativo, diagnóstico, segurança e operação de frotas ADB.

As versões específicas para cada agente devem ser geradas desse conteúdo canônico, e não mantidas como cópias independentes.

### `packages/`

Contém pacotes instaláveis. Um pacote pode agrupar várias skills, regras, scripts, referências e requisitos de adaptadores em uma unidade versionada, como `android-core`, `adb-device-fleet` ou `android-security`.

Pacotes declararão dependências, conflitos, targets suportados e versões semânticas. Uma skill ensina uma capacidade; um pacote distribui um conjunto de capacidades.

### `rules/`

Contém instruções canônicas sobre como o agente deve trabalhar: padrões de código, requisitos de segurança, limites de autorização, coleta de evidências e convenções do projeto. Os adaptadores convertem essas regras para o formato nativo de cada agente.

### `adapters/`

Contém lógica e templates de instalação para Codex, Claude Code, Cursor, Antigravity e destinos genéricos baseados em diretório. Os adaptadores conhecem os caminhos e formatos de cada agente, mas não são donos do conhecimento canônico.

### `schemas/`

Contém contratos v1 legíveis por máquina para manifestos de fontes, pacotes e perfis. Os contratos de estado instalado e lockfile virão em seguida. A validação acontece antes de persistir uma fonte ou escrever no ambiente de um agente.

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

1. Completar os schemas de lockfile e estado instalado.
2. Estender o registro local já implementado com downloads Git/archive e cache imutável.
3. Adicionar resolução determinística e instalação transacional.
4. Implementar adaptadores para Codex, Claude Code, Cursor e Antigravity.
5. Adicionar update, diff, rollback, perfis e bundles offline.
6. Publicar binários assinados para macOS, Windows e Linux.
7. Construir comandos Android e ADB multi-device.
8. Preencher as skills iniciais de Android internals, desenvolvimento nativo, diagnóstico e segurança.

## Idiomas da documentação

- English: [README.md](README.md)
- Português do Brasil: [README.pt-BR.md](README.pt-BR.md)
- Español: [README.es.md](README.es.md)
