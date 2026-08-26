from __future__ import annotations

import copy

from app.providers.ollama import OllamaProvider
from app.tools import ToolResult


class FakeResponse:
    def __init__(self, payload):
        self.payload = payload

    def raise_for_status(self):
        return None

    def json(self):
        return self.payload


class FakeClient:
    instances = []

    def __init__(self, *args, **kwargs):
        self.posts = []
        self.responses = [
            FakeResponse({"message": {"role": "assistant", "content": "", "tool_calls": [{"function": {"name": "get_disk_usage", "arguments": {}}}]}}),
            FakeResponse({"message": {"role": "assistant", "content": "Há 42 GiB livres."}}),
        ]
        self.__class__.instances.append(self)

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        return None

    async def post(self, url, json):
        self.posts.append(copy.deepcopy(json))
        return self.responses.pop(0)


class FakeTools:
    schemas = [{"type": "function", "function": {"name": "get_disk_usage"}}]

    async def execute(self, name, arguments):
        return ToolResult(name, arguments, True, '{"free_gib": 42}', 1)


async def test_ollama_agent_loop_executes_tool_and_returns_final_answer(config, monkeypatch):
    FakeClient.instances.clear()
    provider = OllamaProvider(config, FakeTools())

    async def models():
        return ["qwen3.5:9b"]

    monkeypatch.setattr(provider, "models", models)
    monkeypatch.setattr("app.providers.ollama.httpx.AsyncClient", FakeClient)

    result = await provider.execute("Quanto espaço livre existe?")

    assert result.answer == "Há 42 GiB livres."
    assert result.tools_used == [{"name": "get_disk_usage", "arguments": {}, "ok": True, "duration_ms": 1}]
    second_messages = FakeClient.instances[0].posts[1]["messages"]
    assert second_messages[-1] == {"role": "tool", "tool_name": "get_disk_usage", "content": '{"free_gib": 42}'}
    assert FakeClient.instances[0].posts[0]["tools"] == FakeTools.schemas
