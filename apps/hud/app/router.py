from __future__ import annotations

from app.providers.base import Provider
from app.schemas import ChatRequest, ChatResponse

CODE_WORDS = ("código", "codigo", "code", "repositório", "repositorio", "teste", "debug", "bug", "python", "git")
CLAUDE_WORDS = ("planejamento", "plano longo", "redação", "redacao", "ensaio", "análise extensa", "analise extensa")
LOCAL_WORDS = ("offline", "privado", "local", "simples", "rápido", "rapido")


class ProviderRouter:
    def __init__(self, providers: dict[str, Provider]): self.providers = providers

    def choose(self, request: ChatRequest) -> tuple[str, str]:
        if request.provider != "auto": return request.provider, "Provedor selecionado manualmente."
        text = request.message.casefold()
        if any(x in text for x in CODE_WORDS): return "codex", "Regra Auto: tarefa de código, repositório, teste ou depuração."
        if any(x in text for x in CLAUDE_WORDS): return "claude", "Regra Auto: planejamento, redação ou análise extensa."
        if "antigravity" in text: return "antigravity", "Regra Auto: solicitação explícita das capacidades do Antigravity."
        if any(x in text for x in LOCAL_WORDS): return "ollama", "Regra Auto: pedido simples, privado ou offline."
        return "ollama", "Regra Auto: pedido geral encaminhado ao provedor local por privacidade."

    async def chat(self, request: ChatRequest) -> ChatResponse:
        chosen, reason = self.choose(request)
        result = await self.providers[chosen].execute(request.message, request.model)
        fallback = False
        if result.error and request.allow_fallback and chosen != "ollama":
            fallback = True
            reason += " O provedor falhou e o fallback local autorizado foi usado."
            result = await self.providers["ollama"].execute(request.message, request.model if request.model in getattr(self.providers["ollama"], "allowed_models", set()) else None)
        return ChatResponse(requested_provider=request.provider, used_provider=result.provider, model=result.model, routing_reason=reason, duration_ms=result.duration_ms, fallback_used=fallback, answer=result.answer, tools_used=result.tools_used or [], error=result.error)
