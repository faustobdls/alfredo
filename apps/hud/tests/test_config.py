from pathlib import Path
from app.config import Settings


def test_load_config_and_create_runtime(tmp_path, monkeypatch):
    runtime = tmp_path/"with spaces"; project=tmp_path/"p"; project.mkdir()
    monkeypatch.setenv("ALFREDO_PROJECT", str(project)); monkeypatch.setenv("ALFREDO_RUNTIME", str(runtime)); monkeypatch.setenv("OLLAMA_MODEL", "qwen3.5:4b")
    value=Settings.load(project/"missing.env")
    assert value.ollama_model == "qwen3.5:4b"
    assert (runtime/"tmp").is_dir()

