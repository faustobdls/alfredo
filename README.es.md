# Alfredo

[English](README.md) · [Português do Brasil](README.pt-BR.md)

Alfredo es un ecosistema local-first para distribuir conocimiento reutilizable entre agentes de IA y construir flujos reproducibles de ingeniería Android. El proyecto está organizado como monorepo para que el instalador de línea de comandos, las skills portables, los adaptadores específicos de cada agente y el HUD local existente puedan evolucionar de forma independiente sobre una única base versionada.

## Objetivos

- Mantener las mismas skills, reglas y rutinas en los entornos personal y laboral.
- Instalar capacidades seleccionadas en Codex, Claude Code, Cursor, Antigravity y futuros agentes sin depender de MCP.
- Tratar los repositorios externos de skills como fuentes de solo lectura e instalar snapshots inmutables.
- Proporcionar una CLI Dart multiplataforma distribuida como binario nativo para macOS, Windows y Linux.
- Construir una capa segura de automatización Android y ADB capaz de coordinar varios dispositivos por número de serie.
- Mantener los datos privados y la ejecución local bajo control explícito del usuario.

## Estado actual

El repositorio contiene actualmente:

- La CLI Dart inicial, generada con la plantilla Dart CLI de Very Good Ventures.
- El punto de entrada nativo `alfredo`, con ayuda, versión y soporte de autocompletado del shell.
- Contratos v1 versionados para manifiestos de fuente, paquete y perfil.
- Fuentes locales, Git y archivos con checksum, validadas como snapshots inmutables.
- Descubrimiento determinista, resolución de dependencias, lockfiles y control del estado instalado.
- Instalación transaccional, status, diff y desinstalación segura en ámbitos de usuario y proyecto.
- Adaptadores para Codex, Claude Code, Cursor, Antigravity y un destino genérico.
- El paquete `android-core` con cinco skills Android validadas.
- El subsistema `alfredo memory`, append-only, con búsqueda por palabra clave, embeddings locales opcionales y el paquete `memory-core`.
- El HUD FastAPI existente, aislado en `apps/hud/`.
- Runtime de tareas con tareas, sesiones, runs, checkpoints y paquetes de
  contexto deterministas.
- Personas versionadas para la voz de Alfredo y preferencias duraderas del
  usuario, instaladas como seeds preservables.
- Raíces versionadas para skills, paquetes, reglas, personas, adaptadores,
  schemas y perfiles.
- CI de la CLI Dart en macOS, Linux y Windows, además de la suite de pruebas Python del HUD.

Los perfiles, releases firmados y comandos Android que operan dispositivos siguen como próximas etapas.

## Instalar la CLI

macOS y Linux (x64 o ARM64):

```sh
curl -fsSL https://raw.githubusercontent.com/faustobdls/alfredo/main/scripts/install.sh | sh
```

Windows PowerShell (x64):

```powershell
irm https://raw.githubusercontent.com/faustobdls/alfredo/main/scripts/install.ps1 | iex
```

El instalador descarga el binario correcto desde la release más reciente de
GitHub, valida su checksum SHA-256, instala en `~/.alfredo/bin` y agrega ese
directorio al PATH del shell actual. Define `ALFREDO_INSTALL_DIR` para elegir
otro destino.

Instala los paquetes oficiales en todos los agentes soportados:

```sh
alfredo setup --all
```

O selecciona uno o más agentes:

```sh
alfredo setup --cursor
alfredo setup --codex --claude
alfredo setup --antigravity
```

El comando `setup` configura automáticamente la fuente oficial correspondiente
a la release de la CLI instalada y usa el ámbito de usuario por defecto. Pasa
`--scope project` para instalar en el proyecto actual.

## Estructura del repositorio

```text
alfredo/
├── .github/             # CI, actualización de dependencias y plantillas
├── adapters/            # Adaptadores de instalación y renderizado por agente
├── agents/              # Sub-agentes canónicos, respondiendo como Alfredo
├── apps/
│   └── hud/             # HUD FastAPI local y frontend del navegador
├── cli/                 # CLI Dart multiplataforma y entrada del binario nativo
├── docs/                # Decisiones arquitectónicas y documentación transversal
├── packages/            # Conjuntos instalables de skills, reglas, personas y agentes
├── personas/            # Seeds de voz y preferencias del usuario
├── profiles/            # Configuraciones reproducibles personales, laborales y de proyecto
├── rules/               # Reglas canónicas de comportamiento e ingeniería
├── schemas/             # Contratos versionados de fuentes, paquetes, perfiles y lockfiles
└── skills/              # Skills portables canónicas para agentes de IA
```

### `.github/`

Contiene las automatizaciones del repositorio. `alfredo_cli.yaml` formatea, analiza, prueba y compila la CLI Dart en las tres familias de sistemas operativos. `alfredo_hud.yaml` instala y prueba el HUD Python. Dependabot consulta los paquetes Dart en `cli/`.

### `cli/`

Contiene el paquete Dart puro `alfredo_cli` y el ejecutable `alfredo`. Implementa:

- Fuentes locales y Git/archive de solo lectura con snapshots inmutables.
- Búsqueda y resolución determinista de paquetes.
- Instalación transaccional, status, diff y eliminación segura.
- Alcances de usuario y proyecto.
- Selección explícita de adaptadores para cinco destinos.
- Futuros comandos multi-device en `alfredo android`.

La CLI no depende del runtime de Flutter. Los binarios nativos se compilarán en el sistema operativo de destino.

### `skills/`

La fuente canónica de las skills reutilizables — guías de capacidad bajo demanda, cada una un directorio con `SKILL.md` obligatorio. Dos familias: **skills de dominio** (`android-core`: kernel, internos de la plataforma, desarrollo nativo, seguridad de apps, flotas ADB) y **skills de flujo** (`skills-core`: `autopilot`, `ralph`, `ralplan`, `ultrawork`, `ultraqa`, `team`, `plan`, `deep-interview`, `trace`, `deslop`, `map-project` — métodos de orquestación por fases y verificados en la voz de Alfredo). Ver [docs/architecture/skills.md](docs/architecture/skills.md).

Las versiones específicas para cada agente deben generarse desde este contenido canónico y no mantenerse como copias independientes.

### `packages/`

Contiene paquetes instalables. Un paquete puede agrupar varias skills, reglas, personas, scripts, referencias y requisitos de adaptadores en una unidad versionada, como `android-core`, `rules-core`, `personas-core` o `memory-core`.

Los paquetes declararán dependencias, conflictos, targets compatibles y versiones semánticas. Una skill enseña una capacidad; un paquete distribuye un conjunto de capacidades.

### `rules/`

Restricciones y estándares siempre activos — un archivo Markdown por regla, pensados para estar en el contexto del agente en cada tarea. El paquete `rules-core` distribuye diez en la voz de Alfredo (cambio mínimo, verificar antes de afirmar, seguir el estilo de la casa, commits atómicos, límites de autorización, reporte fiel, preguntar solo cuando se está bloqueado, secretos y exfiltración, separar autoría de revisión, procedencia de contenido externo); `memory-core` añade dos del subsistema de memoria. Los adaptadores las convierten al formato nativo de cada agente. Ver [docs/architecture/rules.md](docs/architecture/rules.md).

### `personas/`

Archivos breves de tono de voz y preferencias de comunicación. `personas-core`
instala `personas/alfredo.md` y `personas/user.md` como seeds: si el archivo ya
existe en el destino, Alfredo no lo sobrescribe en futuras actualizaciones. El
contexto de tarea incluye `.alfredo/personas/*.md` en el grupo `personas`,
separado de reglas, skills y memoria. Ver
[docs/architecture/personas.md](docs/architecture/personas.md).

### `adapters/`

Contiene lógica y plantillas de instalación para Codex, Claude Code, Cursor, Antigravity y destinos genéricos basados en directorios. Los adaptadores conocen las rutas y formatos de cada agente, pero no son propietarios del conocimiento canónico.

### `agents/`

El catálogo canónico de sub-agentes. Un archivo Markdown por agente, en formato de sub-agente de Claude Code, todos respondiendo **como Alfredo** — el mayordomo-ingeniero de la casa: preciso, imperturbable y exigente con los estándares. El paquete `agents-core` los distribuye; `alfredo setup` los instala en el directorio de agentes de cada destino. Ver [docs/architecture/agents.md](docs/architecture/agents.md).

### `templates/`

La fuente canónica de las plantillas de salida — contratos de cómo debe quedar un artefacto: la voz, la estructura, la extensión, el formato y las restricciones de un correo, una presentación, un memorando. Un directorio por plantilla, cada uno con un `TEMPLATE.md` obligatorio (frontmatter validado por `schemas/template.schema.json` más un cuerpo en prosa). Alfredo **no distribuye ninguna plantilla**: solo la maquinaria (el esquema, el grupo de comandos `alfredo template`, la regla `use-templates`, la skill `compose-from-template`). Los equipos crean las suyas y las distribuyen en un paquete mediante `contents.templates`. Ver [docs/architecture/templates.md](docs/architecture/templates.md).

### `schemas/`

Contiene contratos v1 legibles por máquina para fuentes, paquetes, perfiles, estado instalado, lockfiles y contexto. La validación ocurre antes de persistir una fuente o escribir en el entorno de un agente.

### `profiles/`

Contendrá definiciones declarativas como `personal`, `work` o perfiles específicos del proyecto. Un perfil selecciona fuentes, paquetes, versiones, alcances y targets. Junto con un lockfile, permitirá reproducir la misma instalación en máquinas diferentes.

### `apps/hud/`

Contiene el HUD local-first existente:

- `app/`: backend FastAPI, providers, enrutamiento, memoria, herramientas y voz.
- `web/`: interfaz estática servida por FastAPI.
- `tests/`: suite de regresión Python.
- `docs/`: notas de implementación específicas del HUD.
- `pyproject.toml`: paquete y dependencias Python.

El HUD puede llamar a providers locales o remotos controlados. Permanece separado de la CLI Dart para que ambos productos puedan ejecutarse, probarse y distribuirse de forma independiente. Consulta [apps/hud/README.md](apps/hud/README.md) para API, privacidad y configuración.

### `docs/`

Contiene documentación aplicable a todo el ecosistema, incluidos registros de migración y futuras decisiones arquitectónicas. La documentación específica de una aplicación permanece junto a ella.

## Modelo de fuentes

Las fuentes de Alfredo son de solo lectura desde la perspectiva de la CLI:

- El CRUD de fuentes modifica únicamente el registro local.
- Una fuente Git se descarga como snapshot asociado a un commit.
- Un archivo descargable exige metadatos de integridad, como SHA-256.
- Instalar o actualizar paquetes nunca ejecuta commit, push, merge o tag ni edita el origen.
- Las versiones instaladas se registrarán en un lockfile determinista.

Los repositorios de origen se mantienen y publican mediante sus propios flujos. Alfredo solamente los consume.

Una skill escrita para otro agente — por ejemplo la skill de Claude `nidhinjs/prompt-master` — se consume como fuente, no se copia dentro de este repositorio. Si el repositorio de origen no expone un `alfredo-source.yaml` y un paquete, mantén una fuente-wrapper mínima que empaquete su directorio `skills/<nombre>`. El origen Git queda fijado al commit registrado hasta que ejecutes `alfredo update`.

Para empezar uno nuevo:

```sh
alfredo init source ./mi-fuente
```

Esto genera el manifiesto, las raíces de contenido (`skills/`, `rules/`, `agents/`, `profiles/`), un paquete de ejemplo y un README. `--id` y `--name` sobrescriben los valores por defecto; `--force` permite un directorio no vacío.

## Memoria

Alfredo mantiene un registro local y duradero de lo que se decidió y de lo que se hizo, para que el agente recupere el contexto en una sesión posterior en lugar de deducirlo otra vez.

La memoria vive en `.alfredo/memory/` y existe en dos ámbitos independientes: `~/.alfredo/memory/` para prácticas que valen en cualquier proyecto y `<repo>/.alfredo/memory/` para hechos que solo tienen sentido dentro de un repositorio. Cada store contiene un `journal/` append-only con archivos diarios, un directorio `notes/` con un hecho duradero por archivo, un `index/` generado y un `MEMORY.md` derivado. Solo `MEMORY.md` se regenera; los journals crecen por concatenación y las notas nunca se sobrescriben.

La recuperación funciona sin red. La búsqueda por palabra clave siempre está disponible. Cuando hay un Ollama local accesible, `alfredo memory setup` puede habilitar la búsqueda por embeddings, y la búsqueda vuelve silenciosamente a palabras clave siempre que el proveedor no esté disponible. El setup reutiliza cualquier modelo de embedding conocido que ya hayas descargado (`nomic-embed-text`, `mxbai-embed-large`, `bge-m3`, `snowflake-arctic-embed2`, `embeddinggemma`, entre otros); un modelo solo se descarga con confirmación explícita del operador.

| Comando | Efecto |
| --- | --- |
| `alfredo memory setup` | Crea el store, configura la recuperación e instala `memory-core` |
| `alfredo memory add <mensaje>` | Registra una entrada en el journal, o una nota con `--kind note --title` |
| `alfredo memory search <consulta>` | Ordena los documentos de memoria, con reserva por palabra clave |
| `alfredo memory list --since 7d` | Muestra las entradas recientes del journal, de la más nueva a la más antigua |
| `alfredo memory digest --since 14d` | Genera un resumen compacto agrupado por día |
| `alfredo memory index` | Genera embeddings de los documentos nuevos y modificados y elimina los borrados |
| `alfredo memory capture` | Registra el final de una sesión de trabajo |

Define `ALFREDO_MEMORY_HOME` para mover el store del usuario. Consulta [docs/architecture/memory.md](docs/architecture/memory.md) para el contrato en disco y las invariantes de seguridad.

## Desarrollo

### Requisitos

- Dart 3.12 o posterior para desarrollar la CLI.
- Python 3.13 para desarrollar el HUD.
- Git.
- Herramientas específicas de la plataforma para producir releases nativas.

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
dart run bin/alfredo.dart memory add "exploré el registro de fuentes"
dart run bin/alfredo.dart memory digest --since 14d
```

Compila un ejecutable nativo en el sistema actual:

```bash
cd cli
mkdir -p build
dart compile exe bin/alfredo.dart -o build/alfredo
./build/alfredo --version
```

### HUD Python

Crea el entorno compartido desde la raíz:

```bash
python3.13 -m venv .venv
source .venv/bin/activate
python -m pip install -e "apps/hud[dev]"
cp apps/hud/.env.example apps/hud/.env
```

Ejecuta las pruebas y el servidor:

```bash
cd apps/hud
../../.venv/bin/python -m pytest -q
../../.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8765 --reload
```

Abre `http://127.0.0.1:8765` después de iniciar el servidor.

## Principios de seguridad

- Nunca versionar archivos `.env`, credenciales, caches ni binarios generados.
- No exponer un shell genérico a un modelo de IA.
- Direccionar dispositivos Android explícitamente por número de serie.
- Separar observación, cambios de aplicación, acciones privilegiadas y operaciones autorizadas de laboratorio de seguridad.
- Validar contenido y rutas antes de la instalación.
- Usar staging, backups y actualización atómica del estado instalado.
- Mantener la ejecución remota y el fallback explícitos para el usuario.

## Roadmap

1. Añadir perfiles declarativos, actualización, rollback y bundles offline.
2. Publicar binarios firmados para macOS, Windows y Linux.
3. Construir comandos Android y ADB multi-device que operen dispositivos.
4. Ampliar las skills Android con referencias, scripts y laboratorios versionados.

## Idiomas de la documentación

- English: [README.md](README.md)
- Português do Brasil: [README.pt-BR.md](README.pt-BR.md)
- Español: [README.es.md](README.es.md)
