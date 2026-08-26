from __future__ import annotations

import asyncio
import json

from app.tools import ToolRegistry


async def test_disk_usage_is_typed_and_read_only(config):
    result = await ToolRegistry(config).execute("get_disk_usage", {})
    payload = json.loads(result.content)
    assert result.ok
    assert payload["free_gib"] >= 0
    assert set(payload) == {"volume", "total_gib", "used_gib", "free_gib", "used_percent"}


async def test_project_read_and_search(config):
    source = config.project / "hello.py"
    source.write_text("print('alfredo marker')\n", encoding="utf-8")
    registry = ToolRegistry(config)

    read = await registry.execute("read_project_file", {"relative_path": "hello.py"})
    search = await registry.execute("search_project", {"query": "alfredo marker"})

    assert read.ok and "alfredo marker" in read.content
    assert search.ok and json.loads(search.content)[0]["path"] == "hello.py"


async def test_project_tools_block_traversal_and_unknown_tools(config, tmp_path):
    outside = tmp_path / "outside.txt"
    outside.write_text("private", encoding="utf-8")
    registry = ToolRegistry(config)

    traversal = await registry.execute("read_project_file", {"relative_path": "../outside.txt"})
    absolute = await registry.execute("read_project_file", {"relative_path": str(outside)})
    unknown = await registry.execute("run_shell", {"command": "whoami"})

    assert not traversal.ok and "Somente caminhos relativos" in traversal.content
    assert not absolute.ok
    assert not unknown.ok and "não autorizada" in unknown.content


async def test_git_tool_uses_exec_without_shell(config, monkeypatch):
    seen = {}

    class Process:
        returncode = 0

        async def communicate(self):
            return b"## main", b""

    async def fake_exec(*args, **kwargs):
        seen["args"] = args
        seen["kwargs"] = kwargs
        return Process()

    monkeypatch.setattr(asyncio, "create_subprocess_exec", fake_exec)
    result = await ToolRegistry(config).execute("git_status", {})

    assert result.ok and result.content == "## main"
    assert seen["args"][-3:] == ("status", "--short", "--branch")
    assert "shell" not in seen["kwargs"]
    assert seen["kwargs"]["stdin"] is asyncio.subprocess.DEVNULL

