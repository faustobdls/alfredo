from __future__ import annotations

import asyncio
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any, Sequence

from app.schemas import ErrorInfo, ProviderStatus


@dataclass(slots=True)
class ProviderResult:
    provider: str
    model: str | None
    duration_ms: int
    answer: str | None = None
    error: ErrorInfo | None = None
    tools_used: list[dict[str, Any]] | None = None


async def run_process(args: Sequence[str], prompt: str, cwd: str, timeout: float) -> tuple[int, str, str, int]:
    started = time.monotonic()
    try:
        proc = await asyncio.create_subprocess_exec(
            *args,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=cwd,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(prompt.encode()), timeout=timeout)
        return proc.returncode or 0, stdout.decode(errors="replace"), stderr.decode(errors="replace"), int((time.monotonic() - started) * 1000)
    except TimeoutError:
        if "proc" in locals():
            proc.kill()
            await proc.wait()
        raise


class Provider(ABC):
    id: str
    name: str

    @abstractmethod
    async def status(self) -> ProviderStatus: ...

    @abstractmethod
    async def execute(self, prompt: str, model: str | None = None) -> ProviderResult: ...
