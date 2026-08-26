from pathlib import Path
import pytest
from app.config import Settings


@pytest.fixture
def config(tmp_path: Path):
    project, vault, runtime = tmp_path/"project", tmp_path/"vault", tmp_path/"runtime"
    project.mkdir(); vault.mkdir(); runtime.mkdir(); (runtime/"tmp").mkdir()
    return Settings(project, vault, runtime, "http://127.0.0.1:11434", "qwen3.5:9b", "qwen3.5:4b", "qwen3.5:2b", runtime/"ggml-small.bin", "Luciana", provider_timeout=.01)

