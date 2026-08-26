from __future__ import annotations

from typing import Any, Literal
from pydantic import BaseModel, Field

ProviderId = Literal["auto", "codex", "claude", "antigravity", "ollama"]


class ErrorInfo(BaseModel):
    code: str
    message: str
    detail: str | None = None


class ToolExecution(BaseModel):
    name: str
    arguments: dict[str, Any] = Field(default_factory=dict)
    ok: bool
    duration_ms: int


class ProviderStatus(BaseModel):
    id: str
    name: str
    available: bool
    diagnostic: str
    models: list[str] = []


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=20_000)
    provider: ProviderId = "auto"
    model: str | None = Field(default=None, max_length=100)
    allow_fallback: bool = False
    context: list[str] = Field(default_factory=list, max_length=8)


class ChatResponse(BaseModel):
    requested_provider: str
    used_provider: str | None
    model: str | None
    routing_reason: str
    duration_ms: int
    fallback_used: bool = False
    answer: str | None = None
    notes_used: list[str] = Field(default_factory=list)
    tools_used: list[ToolExecution] = Field(default_factory=list)
    error: ErrorInfo | None = None


class SpeakRequest(BaseModel):
    text: str = Field(min_length=1, max_length=8_000)
    voice: str | None = Field(default=None, max_length=100)


class MemoryProposalRequest(BaseModel):
    path: str = Field(min_length=1, max_length=240)
    title: str = Field(min_length=1, max_length=200)
    content: str = Field(min_length=1, max_length=100_000)


class MemoryApprovalRequest(BaseModel):
    proposal_id: str = Field(pattern=r"^[0-9a-f]{32}$")


class MemoryResult(BaseModel):
    path: str
    title: str | None = None
    excerpt: str | None = None
    score: int | None = None
