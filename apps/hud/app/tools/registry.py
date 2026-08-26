from __future__ import annotations

import asyncio
import json
import os
import platform
import shutil
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Awaitable, Callable

from app.config import Settings


class ToolError(ValueError):
    """A rejected or failed local tool call."""


@dataclass(slots=True)
class ToolResult:
    name: str
    arguments: dict[str, Any]
    ok: bool
    content: str
    duration_ms: int

    def public(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "arguments": self.arguments,
            "ok": self.ok,
            "duration_ms": self.duration_ms,
        }


ToolHandler = Callable[[dict[str, Any]], Awaitable[str]]


class ToolRegistry:
    """Read-only, typed tools exposed to the local model."""

    MAX_OUTPUT = 40_000
    MAX_READ = 64_000
    SKIP_DIRS = {".git", ".venv", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", "node_modules"}
    TEXT_SUFFIXES = {
        ".css", ".csv", ".html", ".ini", ".js", ".json", ".md", ".py", ".rst",
        ".sh", ".toml", ".ts", ".tsx", ".txt", ".xml", ".yaml", ".yml",
    }

    def __init__(self, config: Settings):
        self.config = config
        self._handlers: dict[str, ToolHandler] = {
            "get_disk_usage": self._disk_usage,
            "get_system_info": self._system_info,
            "list_project_files": self._list_project_files,
            "read_project_file": self._read_project_file,
            "search_project": self._search_project,
            "git_status": self._git_status,
            "git_diff": self._git_diff,
        }

    @property
    def schemas(self) -> list[dict[str, Any]]:
        return [
            self._schema("get_disk_usage", "Consultar o espaço total, usado e livre no disco local. Não altera o sistema.", {}),
            self._schema("get_system_info", "Consultar macOS, arquitetura, hostname, memória e uptime. Não altera o sistema.", {}),
            self._schema("list_project_files", "Listar arquivos e diretórios dentro do projeto Alfredo.", {
                "relative_path": {"type": "string", "description": "Caminho relativo ao projeto; use . para a raiz."},
            }),
            self._schema("read_project_file", "Ler um arquivo de texto dentro do projeto Alfredo.", {
                "relative_path": {"type": "string", "description": "Caminho relativo do arquivo dentro do projeto."},
            }, ["relative_path"]),
            self._schema("search_project", "Buscar texto nos arquivos legíveis do projeto Alfredo.", {
                "query": {"type": "string", "description": "Texto literal a procurar, entre 2 e 100 caracteres."},
            }, ["query"]),
            self._schema("git_status", "Consultar o estado Git do projeto sem fazer alterações.", {}),
            self._schema("git_diff", "Consultar alterações Git não commitadas no projeto sem fazer alterações.", {}),
        ]

    @staticmethod
    def _schema(name: str, description: str, properties: dict[str, Any], required: list[str] | None = None) -> dict[str, Any]:
        return {
            "type": "function",
            "function": {
                "name": name,
                "description": description,
                "parameters": {
                    "type": "object",
                    "properties": properties,
                    "required": required or [],
                    "additionalProperties": False,
                },
            },
        }

    async def execute(self, name: str, arguments: Any) -> ToolResult:
        started = time.monotonic()
        try:
            args = self._arguments(arguments)
            handler = self._handlers.get(name)
            if handler is None:
                return ToolResult(name, args, False, "Ferramenta desconhecida ou não autorizada.", 0)
            content = await handler(args)
            return ToolResult(name, args, True, content[: self.MAX_OUTPUT], int((time.monotonic() - started) * 1000))
        except (ToolError, OSError, UnicodeError) as exc:
            safe_args = arguments if isinstance(arguments, dict) else {}
            return ToolResult(name, safe_args, False, f"Ferramenta recusada: {str(exc)[:500]}", int((time.monotonic() - started) * 1000))

    @staticmethod
    def _arguments(value: Any) -> dict[str, Any]:
        if isinstance(value, dict):
            return value
        if isinstance(value, str):
            try:
                parsed = json.loads(value)
            except json.JSONDecodeError as exc:
                raise ToolError("Argumentos da ferramenta não são JSON válido.") from exc
            if isinstance(parsed, dict):
                return parsed
        raise ToolError("Argumentos da ferramenta devem ser um objeto.")

    def _project_path(self, relative: Any, *, file: bool | None = None) -> Path:
        if not isinstance(relative, str) or len(relative) > 500:
            raise ToolError("Caminho inválido.")
        raw = Path(relative or ".")
        if raw.is_absolute() or ".." in raw.parts:
            raise ToolError("Somente caminhos relativos dentro do projeto são permitidos.")
        root = self.config.project.resolve()
        try:
            target = (root / raw).resolve(strict=True)
        except OSError as exc:
            raise ToolError("Caminho não encontrado.") from exc
        if not target.is_relative_to(root):
            raise ToolError("Caminho fora do projeto.")
        if file is True and not target.is_file():
            raise ToolError("O caminho não é um arquivo.")
        if file is False and not target.is_dir():
            raise ToolError("O caminho não é um diretório.")
        return target

    async def _disk_usage(self, args: dict[str, Any]) -> str:
        self._no_args(args)
        usage = await asyncio.to_thread(shutil.disk_usage, self.config.project)
        gib = 1024 ** 3
        return json.dumps({
            "volume": str(self.config.project.anchor or "/"),
            "total_gib": round(usage.total / gib, 2),
            "used_gib": round(usage.used / gib, 2),
            "free_gib": round(usage.free / gib, 2),
            "used_percent": round(usage.used * 100 / usage.total, 1),
        }, ensure_ascii=False)

    async def _system_info(self, args: dict[str, Any]) -> str:
        self._no_args(args)
        info: dict[str, Any] = {
            "system": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
            "hostname": platform.node(),
            "cpu_count": os.cpu_count(),
        }
        if shutil.which("sw_vers"):
            info["macos"] = await self._fixed_process(["sw_vers", "-productVersion"])
        if shutil.which("uptime"):
            info["uptime"] = await self._fixed_process(["uptime"])
        if shutil.which("sysctl"):
            memory = await self._fixed_process(["sysctl", "-n", "hw.memsize"])
            if memory.isdigit():
                info["memory_gib"] = round(int(memory) / 1024 ** 3, 2)
        return json.dumps(info, ensure_ascii=False)

    async def _list_project_files(self, args: dict[str, Any]) -> str:
        self._only(args, {"relative_path"})
        target = self._project_path(args.get("relative_path", "."), file=False)
        root = self.config.project.resolve()

        def collect() -> str:
            rows = []
            for child in sorted(target.iterdir(), key=lambda p: (not p.is_dir(), p.name.casefold())):
                if child.name in self.SKIP_DIRS or child.name.startswith("."):
                    continue
                kind = "directory" if child.is_dir() else "file"
                rows.append({"path": str(child.relative_to(root)), "type": kind})
                if len(rows) >= 200:
                    break
            return json.dumps(rows, ensure_ascii=False)

        return await asyncio.to_thread(collect)

    async def _read_project_file(self, args: dict[str, Any]) -> str:
        self._only(args, {"relative_path"})
        target = self._project_path(args.get("relative_path"), file=True)
        if target.suffix.casefold() not in self.TEXT_SUFFIXES:
            raise ToolError("Tipo de arquivo não permitido para leitura.")
        if target.stat().st_size > self.MAX_READ:
            raise ToolError(f"Arquivo acima do limite de {self.MAX_READ} bytes.")
        return await asyncio.to_thread(target.read_text, encoding="utf-8")

    async def _search_project(self, args: dict[str, Any]) -> str:
        self._only(args, {"query"})
        query = args.get("query")
        if not isinstance(query, str) or not 2 <= len(query) <= 100 or "\x00" in query:
            raise ToolError("Consulta deve ter entre 2 e 100 caracteres.")
        root = self.config.project.resolve()

        def search() -> str:
            matches = []
            visited = 0
            for path in root.rglob("*"):
                if any(part in self.SKIP_DIRS or part.startswith(".") for part in path.relative_to(root).parts):
                    continue
                if not path.is_file() or path.is_symlink() or path.suffix.casefold() not in self.TEXT_SUFFIXES:
                    continue
                visited += 1
                if visited > 500 or path.stat().st_size > 512_000:
                    continue
                try:
                    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                        if query.casefold() in line.casefold():
                            matches.append({"path": str(path.relative_to(root)), "line": number, "text": line[:300]})
                            if len(matches) >= 50:
                                return json.dumps(matches, ensure_ascii=False)
                except (OSError, UnicodeError):
                    continue
            return json.dumps(matches, ensure_ascii=False)

        return await asyncio.to_thread(search)

    async def _git_status(self, args: dict[str, Any]) -> str:
        self._no_args(args)
        return await self._git(["status", "--short", "--branch"])

    async def _git_diff(self, args: dict[str, Any]) -> str:
        self._no_args(args)
        return await self._git(["diff", "--no-ext-diff", "--"])

    async def _git(self, arguments: list[str]) -> str:
        if not shutil.which("git"):
            raise ToolError("Git não está instalado.")
        return await self._fixed_process(["git", "-C", str(self.config.project), *arguments])

    async def _fixed_process(self, arguments: list[str]) -> str:
        proc = await asyncio.create_subprocess_exec(
            *arguments,
            stdin=asyncio.subprocess.DEVNULL,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=str(self.config.project),
            env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "LANG": "C.UTF-8"},
        )
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=15)
        except TimeoutError:
            proc.kill()
            await proc.wait()
            raise ToolError("Comando local excedeu 15 segundos.")
        if proc.returncode:
            raise ToolError(stderr.decode(errors="replace")[-800:] or f"Comando terminou com código {proc.returncode}.")
        return stdout.decode(errors="replace")[: self.MAX_OUTPUT].strip() or "Sem saída."

    @staticmethod
    def _only(args: dict[str, Any], allowed: set[str]) -> None:
        extra = set(args) - allowed
        if extra:
            raise ToolError(f"Argumentos não permitidos: {', '.join(sorted(extra))}.")

    @classmethod
    def _no_args(cls, args: dict[str, Any]) -> None:
        cls._only(args, set())
