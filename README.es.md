# Alfredo

[English](README.md) · [Português do Brasil](README.pt-BR.md)

Alfredo es una infraestructura local-first para ingeniería asistida por IA de forma durable y portable.

Los agentes y chats son temporales. La memoria del proyecto, el estado de tareas, las skills, reglas, templates y el contexto no deberían serlo. Alfredo mantiene esa capa durable en archivos controlados por el desarrollador y renderiza las piezas correctas hacia el target de agente que elijas explícitamente.

## Qué Entrega Alfredo

- Setup portable para Codex, Claude Code, Cursor, Antigravity/GCA, Devin, Gemini CLI, Via y targets genéricos basados en directorios.
- Memoria durable para conocimiento de usuario y proyecto fuera del chat actual.
- Paquetes de contexto determinísticos para una tarea específica.
- Skills, reglas, personas, sub-agentes, templates, scripts, assets y referencias portables.
- Runtime durable de tareas con tareas, dependencias, dueños, sesiones, checkpoints, bloqueos, validaciones y próximas acciones.
- Fuentes de paquetes de solo lectura, resolución de dependencias, lockfiles, instalación transaccional, status, diff, update y uninstall seguro.
- Operación local-first: el estado sigue siendo legible, versionable, recuperable e inspeccionable en la máquina del desarrollador.

## Cómo Funciona

```text
estado canónico de Alfredo
        |
        v
fuentes, paquetes, memoria, tareas, contexto
        |
        v
adaptadores de target
        |
        v
Codex / Claude Code / Cursor / Antigravity / Devin / Gemini CLI / Via / genérico
```

Directorios de provider como `.codex/`, `.claude/`, `.cursor/`, `.gemini/`, `.devin/`, `.via/`, `.agents/` y `.alfredo/` son salidas de adaptadores. No son el tablero canónico, la memoria ni la fuente de verdad.

## Conceptos Centrales

### Memoria

La memoria responde: "qué sabemos?"

Guarda decisiones durables, hechos, convenciones, aprendizajes e historial relevante en dos alcances:

- `~/.alfredo/memory/` para conocimiento que aplica entre proyectos.
- `<repo>/.alfredo/memory/` para conocimiento que solo aplica a un repositorio.

La memoria es append-only por diseño. Los journals crecen con el tiempo, las notas se escriben una vez y los índices derivados se pueden regenerar. La búsqueda funciona offline por palabras clave. Embeddings locales opcionales con Ollama mejoran el ranking cuando están disponibles y vuelven a palabras clave cuando no lo están.

### Contexto

El contexto responde: "qué debe cargar esta tarea ahora?"

Los proyectos pueden declarar tópicos de contexto en `.alfredo/config.yaml`. Una tarea puede referenciar tópicos y archivos. `alfredo context build ALF-...` devuelve un paquete determinístico `alfredo.context/v1` con fuentes agrupadas y una estimación aproximada de tokens, para que los agentes carguen material relevante en vez de redescubrir el proyecto en cada sesión.

### Skills

Las skills son guías portables de capacidad. Cada skill vive en `skills/<nombre>/SKILL.md`, con referencias, scripts y assets opcionales cargados solo cuando hacen falta. Las skills hacen que el comportamiento del agente sea enseñable sin volcar todos los detalles en cada prompt.

### Reglas

Las reglas son restricciones y estándares siempre activos. Viven en `rules/` y los adaptadores las renderizan hacia cada target seleccionado. Usa reglas para comportamientos que deben aplicar ampliamente; usa skills para procedimientos específicos de una tarea.

### Personas

Las personas son archivos livianos de voz y preferencias. Viven en `personas/` y pueden sembrarse en targets sin sobrescribir ediciones locales del usuario en updates futuros.

### Templates

Los templates describen la forma deseada de un artefacto de salida: voz, estructura, tamaño, formato y restricciones. Alfredo provee el schema y los comandos; los equipos crean y empaquetan sus propios templates.

Al crear un template, pregunta o informa el tipo, para que sirve y el formato de
salida. El formato es abierto: los targets conocidos son sugerencias, y un
proyecto puede definir un target de texto puro, archivo customizado o renderer
especifico. Los templates en blanco se escriben en el repositorio en
`templates/<name>/TEMPLATE.md`, no en el perfil de usuario, para poder
empaquetarlos o exportarlos despues.

### Paquetes Y Fuentes

Los paquetes agrupan contenido canónico en unidades instalables versionadas. Un paquete declara sus targets soportados, dependencias, conflictos y rutas de contenido. Las fuentes son catálogos de solo lectura, locales, Git o archives. Instalar paquetes escribe en adaptadores de target, nunca en la fuente.

### Targets Y Adaptadores

Un target es un ambiente explícito de agente, como `codex`, `claude-code`, `cursor`, `antigravity`, `devin`, `gemini-cli`, `via` o `generic`. Un adaptador mapea contenido canónico de Alfredo al layout de directorios de ese target.

`alfredo setup --all` instala solamente los targets declarados por los paquetes oficiales descubiertos que ya están configurados en el alcance local seleccionado. No instala en todos los adapters incorporados solo porque Alfredo sabe que existen.

### Runtime De Tareas

El Runtime de Tareas responde: "qué estamos haciendo ahora?"

Los proyectos mantienen estado durable de trabajo en `.alfredo/` y estado local de máquina en `.alfredo/runtime/`. Las entidades centrales son:

- Run: un objetivo mayor o unidad de orquestación.
- Task: una unidad durable de trabajo con criterios de aceptación y dependencias.
- Session: una instancia temporal de worker usando un adapter/provider soportado.

`READY` es derivado, no persistido. Una tarea está lista cuando está en `BACKLOG`, no tiene dueño, no está bloqueada ni terminal, y todas las dependencias están `DONE`.

Los flujos de desarrollo mayores terminan con una verificación de cierre:
revisar el conjunto de READMEs para detectar comportamiento o notas de setup
desactualizados y revisar los elementos alterados para ver si algo debe ir a la
memoria antes de reportar la tarea master como completa.

## Instalación

macOS y Linux:

```sh
curl -fsSL https://raw.githubusercontent.com/faustobdls/alfredo/main/scripts/install.sh | sh
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/faustobdls/alfredo/main/scripts/install.ps1 | iex
```

El instalador descarga la release más reciente de GitHub para la plataforma actual, valida el checksum SHA-256, instala en `~/.alfredo/bin` y actualiza el PATH del shell actual. Define `ALFREDO_INSTALL_DIR` para elegir otro destino.

## Setup De Targets

Instala paquetes oficiales en todos los targets configurados y declarados por esos paquetes:

```sh
alfredo setup --all
```

Instala solo targets seleccionados:

```sh
alfredo setup --codex
alfredo setup --cursor --gemini-cli
alfredo setup --devin --via
alfredo setup --claude-code
alfredo setup --antigravity
alfredo setup --generic
```

Usa `--scope project` para instalar en el proyecto actual en vez del alcance de usuario, y `--force` para sobrescribir archivos administrados modificados localmente.

## Comandos Comunes

```sh
alfredo init source ./mi-fuente
alfredo source add canonical --local ./mi-fuente
alfredo package list
alfredo package install android-core --target codex --scope user
alfredo package status --target codex
alfredo update --dry-run
alfredo upgrade --check
alfredo template new email-cliente --kind email --description "Use para email de cliente. No para chat interno." --format-target email
alfredo template validate email-cliente
```

```sh
alfredo memory setup --target codex
alfredo memory add "documente el runtime de tareas"
alfredo memory add --kind note --title "Decision de runtime" "las tareas son canonicas"
alfredo memory list --since 30d
alfredo memory search "handoff de tarea"
alfredo memory digest --since 14d
alfredo memory capture
```

```sh
alfredo task create --title "Implementar soporte de reconnect"
alfredo task ready
alfredo session start --adapter codex
alfredo task claim ALF-... --adapter codex --session SES-...
alfredo task start ALF-...
alfredo task checkpoint ALF-... --completed "protocolo" --current "tests"
alfredo task verify ALF-...
alfredo task done ALF-...
alfredo task resume ALF-...
alfredo context build ALF-...
```

La mayoría de los comandos de runtime soporta `--json` para agentes y herramientas.

## Estructura Del Repositorio

```text
alfredo/
├── .github/             # CI, actualizaciones de dependencias y templates del repo
├── adapters/            # Adaptadores de instalacion y renderizado por agente
├── agents/              # Sub-agentes canonicos
├── cli/                 # CLI Dart multiplataforma y entrada del ejecutable nativo
├── docs/                # Documentacion de arquitectura y migraciones
├── packages/            # Bundles instalables de contenido canonico
├── personas/            # Seeds de voz y preferencias durables
├── profiles/            # Selecciones reproducibles personales, trabajo y proyecto
├── rules/               # Reglas canonicas siempre activas
├── schemas/             # Contratos JSON versionados
└── skills/              # Skills portables canonicas
```

## Notas De Arquitectura

- [Adaptadores De Agente](docs/architecture/agent-adapters.md)
- [Agentes](docs/architecture/agents.md)
- [Motor De Contexto](docs/architecture/context-engine.md)
- [Memoria](docs/architecture/memory.md)
- [Personas](docs/architecture/personas.md)
- [Reglas](docs/architecture/rules.md)
- [Skills](docs/architecture/skills.md)
- [Runtime De Tareas](docs/architecture/task-runtime.md)
- [Templates](docs/architecture/templates.md)

## Desarrollo

```sh
cd cli
dart pub get
dart format .
dart analyze
dart test
```
