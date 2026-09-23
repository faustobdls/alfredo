#!/usr/bin/env bash
# Runs the Dart SDK directly while isolating the telemetry/analytics home
# directory, so `dart` works inside restricted or sandboxed environments
# (CI runners, containers, read-only home directories, agent file sandboxes)
# where a version-manager wrapper such as fvm's `dart`/`flutter` entrypoint
# fails with `Operation not permitted` trying to touch its own installation
# cache (`bin/cache/engine.stamp.tmp.*`, `bin/cache/engine.realm`) or the
# global `~/.dart-tool` telemetry/session files.
#
# Usage:
#   scripts/dart-sandbox.sh pub get
#   scripts/dart-sandbox.sh analyze --fatal-infos --fatal-warnings
#   scripts/dart-sandbox.sh test
#   scripts/dart-sandbox.sh format .
#
# Environment overrides:
#   ALFREDO_DART_BIN            Absolute path to the dart executable to run.
#                                Skips auto-detection when set.
#   ALFREDO_DART_SANDBOX_HOME   Directory to use as the isolated $HOME.
#                                Defaults to
#                                <repo>/.alfredo/runtime/dart-sandbox-home
#                                (already git-ignored).
#   PUB_CACHE                   Preserved from the caller's environment (or
#                                defaulted to the original $HOME/.pub-cache)
#                                so packages are not re-fetched.
set -euo pipefail

# Resolves the real Dart SDK binary, bypassing version-manager wrapper
# scripts (e.g. fvm) that shell out to `<version>/bin/cache/dart-sdk/bin/dart`
# only after running their own update/telemetry bookkeeping.
resolve_dart_sdk_bin() {
  local candidate resolved sdk_bin
  candidate="$(command -v dart || true)"
  if [[ -z "$candidate" ]]; then
    echo "dart-sandbox: could not find 'dart' on PATH" >&2
    return 1
  fi

  if command -v realpath >/dev/null 2>&1; then
    resolved="$(realpath "$candidate")"
  else
    resolved="$(cd "$(dirname "$candidate")" && pwd -P)/$(basename "$candidate")"
  fi

  # A version-manager install typically looks like:
  #   <version_root>/bin/dart                       (wrapper script)
  #   <version_root>/bin/cache/dart-sdk/bin/dart     (real SDK binary)
  # `$resolved` is `<version_root>/bin/dart`, so its own directory is
  # `<version_root>/bin`.
  sdk_bin="$(dirname "$resolved")/cache/dart-sdk/bin/dart"
  if [[ -x "$sdk_bin" ]]; then
    echo "$sdk_bin"
    return 0
  fi

  # Not a recognized wrapper layout (already a plain SDK install); use it
  # as-is.
  echo "$resolved"
}

DART_BIN="${ALFREDO_DART_BIN:-}"
if [[ -z "$DART_BIN" ]]; then
  DART_BIN="$(resolve_dart_sdk_bin)"
fi
if [[ ! -x "$DART_BIN" ]]; then
  echo "dart-sandbox: resolved dart binary is not executable: $DART_BIN" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SANDBOX_HOME="${ALFREDO_DART_SANDBOX_HOME:-$REPO_ROOT/.alfredo/runtime/dart-sandbox-home}"
mkdir -p "$SANDBOX_HOME"

# Preserve the real pub package cache so isolating $HOME does not force a
# re-fetch of every dependency.
export PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
export HOME="$SANDBOX_HOME"

exec "$DART_BIN" "$@"
