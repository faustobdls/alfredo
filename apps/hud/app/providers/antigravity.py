from app.providers.base import Provider, ProviderResult
from app.schemas import ErrorInfo, ProviderStatus


class AntigravityProvider(Provider):
    id, name = "antigravity", "Antigravity"
    async def status(self) -> ProviderStatus:
        return ProviderStatus(id=self.id, name=self.name, available=False, diagnostic="Nenhuma CLI ou SDK programático oficial do Antigravity foi confirmado neste ambiente.")
    async def execute(self, prompt: str, model: str | None = None) -> ProviderResult:
        return ProviderResult(self.id, model, 0, error=ErrorInfo(code="unavailable", message="Antigravity indisponível.", detail="Instale ou configure uma integração programática oficial e documentada."))
