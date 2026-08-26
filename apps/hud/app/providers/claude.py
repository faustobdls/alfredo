from __future__ import annotations

import json, shutil, time
from app.config import Settings
from app.providers.base import Provider, ProviderResult, run_process
from app.schemas import ErrorInfo, ProviderStatus


class ClaudeProvider(Provider):
    id, name = "claude", "Claude Code"
    def __init__(self, config: Settings): self.config = config

    async def status(self) -> ProviderStatus:
        if not shutil.which("claude"):
            return ProviderStatus(id=self.id, name=self.name, available=False, diagnostic="Claude Code não encontrado no PATH.")
        try:
            code, out, _, _ = await run_process(["claude", "auth", "status", "--json"], "", str(self.config.project), 5)
            auth = json.loads(out)
            if code or not auth.get("loggedIn"):
                return ProviderStatus(id=self.id, name=self.name, available=False, diagnostic="CLI encontrada, mas a sessão não está autenticada. Execute `claude auth login`.")
            return ProviderStatus(id=self.id, name=self.name, available=True, diagnostic="CLI autenticada; execução não interativa em modo de planejamento.")
        except Exception as exc:
            return ProviderStatus(id=self.id, name=self.name, available=False, diagnostic=f"Não foi possível verificar a autenticação do Claude: {type(exc).__name__}.")

    async def execute(self, prompt: str, model: str | None = None) -> ProviderResult:
        started = time.monotonic()
        if not shutil.which("claude"):
            return ProviderResult(self.id, model, 0, error=ErrorInfo(code="unavailable", message="Claude Code não encontrado."))
        args = ["claude", "--print", "--output-format", "json", "--permission-mode", "plan", "--no-session-persistence", "--safe-mode"]
        if model: args.extend(["--model", model])
        try:
            code, out, err, ms = await run_process(args, prompt, str(self.config.project), self.config.provider_timeout)
            if code:
                detail = err[-1000:]
                try: detail = json.loads(out).get("result") or detail
                except json.JSONDecodeError: detail = detail or out[-1000:]
                return ProviderResult(self.id, model, ms, error=ErrorInfo(code="process_error", message="Claude não concluiu a solicitação.", detail=detail or f"código {code}"))
            try: answer = json.loads(out).get("result", out.strip())
            except json.JSONDecodeError: answer = out.strip()
            return ProviderResult(self.id, model or "configurado no Claude", ms, answer=answer)
        except TimeoutError:
            return ProviderResult(self.id, model, int((time.monotonic()-started)*1000), error=ErrorInfo(code="timeout", message="Claude excedeu o tempo limite."))
