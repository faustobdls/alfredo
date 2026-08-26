from __future__ import annotations

import json
import shutil
import time

from app.config import Settings
from app.providers.base import Provider, ProviderResult, run_process
from app.schemas import ErrorInfo, ProviderStatus


class CodexProvider(Provider):
    id, name = "codex", "Codex"

    def __init__(self, config: Settings): self.config = config

    async def status(self) -> ProviderStatus:
        path = shutil.which("codex")
        return ProviderStatus(id=self.id, name=self.name, available=bool(path), diagnostic="CLI disponível e será executada em sandbox somente leitura." if path else "Codex CLI não encontrado no PATH.")

    async def execute(self, prompt: str, model: str | None = None) -> ProviderResult:
        started = time.monotonic()
        if not shutil.which("codex"):
            return ProviderResult(self.id, model, 0, error=ErrorInfo(code="unavailable", message="Codex CLI não encontrado."))
        args = ["codex", "exec", "-", "--sandbox", "read-only", "--ephemeral", "--json", "--cd", str(self.config.project)]
        if model: args.extend(["--model", model])
        try:
            code, out, err, ms = await run_process(args, prompt, str(self.config.project), self.config.provider_timeout)
            if code:
                return ProviderResult(self.id, model, ms, error=ErrorInfo(code="process_error", message="Codex não concluiu a solicitação.", detail=err[-1000:] or f"código {code}"))
            answer = ""
            for line in out.splitlines():
                try:
                    event = json.loads(line)
                    if event.get("type") == "item.completed" and event.get("item", {}).get("type") == "agent_message": answer = event["item"].get("text", answer)
                except json.JSONDecodeError: pass
            return ProviderResult(self.id, model or "configurado no Codex", ms, answer=answer or out.strip())
        except TimeoutError:
            return ProviderResult(self.id, model, int((time.monotonic()-started)*1000), error=ErrorInfo(code="timeout", message="Codex excedeu o tempo limite."))

