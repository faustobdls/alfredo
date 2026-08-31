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
- Registro validado de fuentes locales de solo lectura mediante `source add`, `list`, `show`, `test` y `remove`.
- Un paquete mínimo `android-core` que ejercita el contrato del catálogo.
- El HUD FastAPI existente, aislado en `apps/hud/`.
- Raíces versionadas para skills, paquetes, reglas, adaptadores, schemas y perfiles.
- CI de la CLI Dart en macOS, Linux y Windows, además de la suite de pruebas Python del HUD.

Las fuentes Git/archive, la instalación de paquetes, los adaptadores de agentes y los comandos Android son las próximas etapas de implementación.

## Estructura del repositorio

```text
alfredo/
├── .github/             # CI, actualización de dependencias y plantillas
├── adapters/            # Adaptadores de instalación y renderizado por agente
├── apps/
│   └── hud/             # HUD FastAPI local y frontend del navegador
├── cli/                 # CLI Dart multiplataforma y entrada del binario nativo
├── docs/                # Decisiones arquitectónicas y documentación transversal
├── packages/            # Conjuntos instalables de skills, reglas, scripts y assets
├── profiles/            # Configuraciones reproducibles personales, laborales y de proyecto
├── rules/               # Reglas canónicas de comportamiento e ingeniería
├── schemas/             # Contratos versionados de fuentes, paquetes, perfiles y lockfiles
└── skills/              # Skills portables canónicas para agentes de IA
```

### `.github/`

Contiene las automatizaciones del repositorio. `alfredo_cli.yaml` formatea, analiza, prueba y compila la CLI Dart en las tres familias de sistemas operativos. `alfredo_hud.yaml` instala y prueba el HUD Python. Dependabot consulta los paquetes Dart en `cli/`.

### `cli/`

Contiene el paquete Dart puro `alfredo_cli` y el ejecutable `alfredo`. Ya implementa la validación de fuentes locales y el CRUD del registro. Sus próximas responsabilidades son:

- Descargas de solo lectura y snapshots inmutables.
- Búsqueda en el catálogo y resolución de paquetes.
- Instalación, actualización, diff, rollback y eliminación.
- Alcances de usuario y proyecto.
- Detección de agentes y selección de adaptadores.
- Futuros comandos multi-device en `alfredo android`.

La CLI no depende del runtime de Flutter. Los binarios nativos se compilarán en el sistema operativo de destino.

### `skills/`

Es la fuente canónica de las skills reutilizables. Cada skill será un directorio con un `SKILL.md` obligatorio y directorios opcionales `scripts/`, `references/` y `assets/`. Las skills describen conocimiento y procedimientos especializados, como kernel Android, desarrollo nativo, diagnóstico, seguridad y operación de flotas ADB.

Las versiones específicas para cada agente deben generarse desde este contenido canónico y no mantenerse como copias independientes.

### `packages/`

Contiene paquetes instalables. Un paquete puede agrupar varias skills, reglas, scripts, referencias y requisitos de adaptadores en una unidad versionada, como `android-core`, `adb-device-fleet` o `android-security`.

Los paquetes declararán dependencias, conflictos, targets compatibles y versiones semánticas. Una skill enseña una capacidad; un paquete distribuye un conjunto de capacidades.

### `rules/`

Contiene instrucciones canónicas sobre cómo debe trabajar un agente: estándares de código, requisitos de seguridad, límites de autorización, recolección de evidencias y convenciones del proyecto. Los adaptadores convierten estas reglas al formato nativo de cada agente.

### `adapters/`

Contiene lógica y plantillas de instalación para Codex, Claude Code, Cursor, Antigravity y destinos genéricos basados en directorios. Los adaptadores conocen las rutas y formatos de cada agente, pero no son propietarios del conocimiento canónico.

### `schemas/`

Contiene contratos v1 legibles por máquina para manifiestos de fuentes, paquetes y perfiles. Los contratos de estado instalado y lockfile vendrán después. La validación ocurre antes de persistir una fuente o escribir en el entorno de un agente.

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

1. Completar los schemas de lockfile y estado instalado.
2. Extender el registro local ya implementado con descargas Git/archive y caché inmutable.
3. Añadir resolución determinista e instalación transaccional.
4. Implementar adaptadores para Codex, Claude Code, Cursor y Antigravity.
5. Añadir update, diff, rollback, perfiles y bundles offline.
6. Publicar binarios firmados para macOS, Windows y Linux.
7. Construir comandos Android y ADB multi-device.
8. Completar las skills iniciales de Android internals, desarrollo nativo, diagnóstico y seguridad.

## Idiomas de la documentación

- English: [README.md](README.md)
- Português do Brasil: [README.pt-BR.md](README.pt-BR.md)
- Español: [README.es.md](README.es.md)
