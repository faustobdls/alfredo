from app.providers.base import Provider, ProviderResult
from app.router import ProviderRouter
from app.schemas import ChatRequest, ErrorInfo, ProviderStatus


class Fake(Provider):
    name="fake"
    def __init__(self,id,fail=False): self.id=id; self.fail=fail
    async def status(self): return ProviderStatus(id=self.id,name=self.id,available=True,diagnostic="ok")
    async def execute(self,prompt,model=None):
        return ProviderResult(self.id,model,5,error=ErrorInfo(code="x",message="fail")) if self.fail else ProviderResult(self.id,model or "m",5,answer="ok")


def make(fail=None): return ProviderRouter({x:Fake(x,x==fail) for x in ("codex","claude","antigravity","ollama")})

async def test_manual_route():
    result=await make().chat(ChatRequest(message="olá",provider="claude")); assert result.used_provider=="claude" and "manualmente" in result.routing_reason

async def test_auto_rules():
    router=make(); assert router.choose(ChatRequest(message="corrija este código"))[0]=="codex"; assert router.choose(ChatRequest(message="faça um planejamento"))[0]=="claude"; assert router.choose(ChatRequest(message="algo privado"))[0]=="ollama"

async def test_fallback_is_explicit():
    result=await make("codex").chat(ChatRequest(message="debug",allow_fallback=True)); assert result.used_provider=="ollama" and result.fallback_used

async def test_error_is_normalized():
    result=await make("claude").chat(ChatRequest(message="x",provider="claude")); assert result.error.code=="x" and not result.fallback_used

