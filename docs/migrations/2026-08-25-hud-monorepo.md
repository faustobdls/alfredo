# HUD monorepo migration

## Context

The repository had no initial commit when the migration started. All product files were untracked, so Git cannot express these changes as renames or provide a pre-migration hash baseline.

## Evidence captured during execution

- Before migration, `pytest -q` reported 20 passing tests.
- The pre-migration inventory contained 31 visible HUD source files under `app/`, `web/`, `tests/`, and `docs/`, plus `README.md`, `pyproject.toml`, and `.env.example` at the repository root.
- Each item was moved with a filesystem rename into `apps/hud/`; every rename command completed successfully.
- The post-migration inventory contains the same 31 visible source files under `apps/hud/`, plus `apps/hud/.env.example`.
- The local ignored `.env` was moved to `apps/hud/.env` without reading or logging its contents.
- After migration, the original 20 tests still passed. A new regression test was then added for static assets outside the HUD working directory, bringing the suite to 21 tests.

## Path mapping

| Before | After |
| --- | --- |
| `app/**` | `apps/hud/app/**` |
| `web/**` | `apps/hud/web/**` |
| `tests/**` | `apps/hud/tests/**` |
| `docs/implementation-plan.md` | `apps/hud/docs/implementation-plan.md` |
| `pyproject.toml` | `apps/hud/pyproject.toml` |
| `.env.example` | `apps/hud/.env.example` |
| `.env` | `apps/hud/.env` |
| `README.md` | `apps/hud/README.md` |

The new root `README.md` is a monorepo guide and is not a replacement for any omitted HUD content.

## Verification contract

Future changes to the HUD run `.github/workflows/alfredo_hud.yaml`. The workflow installs `apps/hud`, runs its complete pytest suite, and includes a regression that serves `/` and `/static/app.js` after changing to an unrelated working directory.
