from __future__ import annotations

import time
import httpx
from app.config import Settings
from app.providers.base import Provider, ProviderResult
from app.schemas import ErrorInfo, ProviderStatus
from app.tools import ToolRegistry


class OllamaProvider(Provider):
    id, name = "ollama", "Local / Ollama"
    allowed_models = {"qwen3.5:9b", "qwen3.5:4b", "qwen3.5:2b", "gemma4:e4b"}
    max_tool_calls = 6

    def __init__(self, config: Settings, tools: ToolRegistry | None = None):
        self.config = config
        self.tools = tools or ToolRegistry(config)

    async def models(self) -> list[str]:
        async with httpx.AsyncClient(timeout=3) as client:
            response = await client.get(f"{self.config.ollama_base_url}/api/tags")
            response.raise_for_status()
            return [m["name"] for m in response.json().get("models", [])]

    async def status(self) -> ProviderStatus:
        try:
            models = await self.models()
            return ProviderStatus(id=self.id, name=self.name, available=True, diagnostic=f"Serviço local acessível; {len(models)} modelo(s) encontrado(s).", models=models)
        except Exception as exc:
            return ProviderStatus(id=self.id, name=self.name, available=False, diagnostic=f"Ollama local inacessível: {type(exc).__name__}.")

    async def execute(self, prompt: str, model: str | None = None) -> ProviderResult:
        started = time.monotonic()
        selected = model or self.config.ollama_model
        if selected not in self.allowed_models:
            return ProviderResult(self.id, selected, 0, error=ErrorInfo(code="invalid_model", message="Modelo local não permitido no HUD."))
        try:
            installed = await self.models()
            if selected not in installed:
                return ProviderResult(self.id, selected, 0, error=ErrorInfo(code="model_missing", message=f"O modelo {selected} não está instalado.", detail="Instale manualmente com Ollama ou escolha um modelo disponível."))
            messages: list[dict] = [
                {
                    "role": "system",
                    "content": (
                        "Você é Alfredo, um assistente local discreto, confiável e conciso. "
                        "Responda no idioma do usuário. Você possui ferramentas locais somente leitura. "
                        "Quando a pergunta depender do estado atual do computador ou do projeto, use a ferramenta apropriada; "
                        "não invente resultados. Nunca alegue ter executado uma ação sem um resultado de ferramenta."
                    ),
                },
                {"role": "user", "content": prompt},
            ]
            used: list[dict] = []
            async with httpx.AsyncClient(timeout=self.config.provider_timeout) as client:
                while len(used) < self.max_tool_calls:
                    response = await client.post(
                        f"{self.config.ollama_base_url}/api/chat",
                        json={"model": selected, "stream": False, "messages": messages, "tools": self.tools.schemas},
                    )
                    response.raise_for_status()
                    assistant = response.json().get("message", {})
                    messages.append(assistant)
                    calls = assistant.get("tool_calls") or []
                    if not calls:
                        answer = str(assistant.get("content") or "").strip()
                        return ProviderResult(self.id, selected, int((time.monotonic()-started)*1000), answer=answer, tools_used=used)
                    for call in calls:
                        if len(used) >= self.max_tool_calls:
                            break
                        function = call.get("function") or {}
                        tool_result = await self.tools.execute(str(function.get("name") or ""), function.get("arguments") or {})
                        used.append(tool_result.public())
                        messages.append({"role": "tool", "tool_name": tool_result.name, "content": tool_result.content})
            return ProviderResult(
                self.id,
                selected,
                int((time.monotonic()-started)*1000),
                tools_used=used,
                error=ErrorInfo(code="tool_limit", message="Ollama excedeu o limite de ferramentas desta solicitação."),
            )
        except httpx.TimeoutException:
            return ProviderResult(self.id, selected, int((time.monotonic()-started)*1000), error=ErrorInfo(code="timeout", message="Ollama excedeu o tempo limite."))
        except Exception as exc:
            return ProviderResult(self.id, selected, int((time.monotonic()-started)*1000), error=ErrorInfo(code="connection_error", message="Falha ao consultar o Ollama local.", detail=str(exc)[:500]))
