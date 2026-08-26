from __future__ import annotations

import asyncio
from pathlib import Path
from fastapi import FastAPI, File, HTTPException, Query, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from app.config import settings
from app.memory import MemoryError, MemoryStore
from app.providers import AntigravityProvider, ClaudeProvider, CodexProvider, OllamaProvider
from app.router import ProviderRouter
from app.schemas import ChatRequest, ChatResponse, MemoryApprovalRequest, MemoryProposalRequest, SpeakRequest
from app.voice.speaker import Speaker
from app.voice.transcriber import AudioError, Transcriber

app = FastAPI(title="Alfredo", version="0.1.0", docs_url="/api/docs")
providers = {p.id: p for p in (CodexProvider(settings), ClaudeProvider(settings), AntigravityProvider(), OllamaProvider(settings))}
router = ProviderRouter(providers)
memory = MemoryStore(settings)
transcriber = Transcriber(settings)
speaker = Speaker(settings)
web_dir = settings.hud_root / "web"


@app.exception_handler(MemoryError)
@app.exception_handler(AudioError)
async def domain_error(_: Request, exc: Exception):
    return JSONResponse(status_code=400, content={"error": {"code": "invalid_request", "message": str(exc)}})


@app.get("/api/health")
async def health():
    statuses = await asyncio.gather(*(p.status() for p in providers.values()))
    return {"status": "online", "runtime": str(settings.runtime), "providers_available": sum(s.available for s in statuses)}


@app.get("/api/providers")
async def provider_statuses():
    return await asyncio.gather(*(p.status() for p in providers.values()))


@app.post("/api/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    if len(request.message) > settings.max_prompt_chars: raise HTTPException(413, "Mensagem acima do limite configurado.")
    selected = await asyncio.to_thread(memory.read_selected, request.context) if request.context else []
    if selected:
        context = "\n\n".join(f"[Nota: {path}]\n{text}" for path, text in selected)
        routed_request = request.model_copy(update={"message": f"{request.message}\n\nContexto selecionado pelo usuário:\n{context}"})
    else:
        routed_request = request
    result = await router.chat(routed_request)
    result.notes_used = [path for path, _ in selected]
    return result


@app.post("/api/transcribe")
async def transcribe(audio: UploadFile = File(...)):
    if audio.size is not None and audio.size > settings.max_audio_bytes: raise HTTPException(413, "Áudio acima do limite permitido.")
    data = await audio.read(settings.max_audio_bytes + 1)
    if len(data) > settings.max_audio_bytes: raise HTTPException(413, "Áudio acima do limite permitido.")
    return {"text": await transcriber.transcribe(data, audio.content_type or "")}


@app.post("/api/speak")
async def speak(request: SpeakRequest):
    try: return {"spoken": True, "voice": await speaker.speak(request.text, request.voice)}
    except ValueError as exc: raise HTTPException(400, str(exc)) from exc


@app.get("/api/memory/search")
async def memory_search(q: str = Query(min_length=2, max_length=200), limit: int = Query(8, ge=1, le=20)):
    return {"results": await asyncio.to_thread(memory.search, q, limit)}


@app.post("/api/memory/propose")
async def memory_propose(request: MemoryProposalRequest):
    return memory.propose(request.path, request.title, request.content)


@app.post("/api/memory/approve")
async def memory_approve(request: MemoryApprovalRequest):
    return await memory.approve(request.proposal_id)


@app.get("/")
async def index(): return FileResponse(web_dir / "index.html")


app.mount("/static", StaticFiles(directory=web_dir), name="static")
