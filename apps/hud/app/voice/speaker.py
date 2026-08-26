from __future__ import annotations

import asyncio, shutil
from app.config import Settings


class Speaker:
    def __init__(self, config: Settings): self.config = config

    async def voices(self) -> set[str]:
        proc = await asyncio.create_subprocess_exec("say", "-v", "?", stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        out, _ = await proc.communicate()
        return {line.split()[0] for line in out.decode(errors="replace").splitlines() if line.strip()}

    async def speak(self, text: str, voice: str | None = None) -> str:
        if not shutil.which("say"): raise ValueError("Comando say não encontrado.")
        selected = voice or self.config.tts_voice
        installed = await self.voices()
        if selected not in installed: raise ValueError(f"Voz '{selected}' não está instalada.")
        proc = await asyncio.create_subprocess_exec("say", "-v", selected, text, stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.PIPE)
        _, err = await proc.communicate()
        if proc.returncode: raise ValueError(err.decode(errors="replace")[-500:])
        return selected

