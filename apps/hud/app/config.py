from __future__ import annotations

import os
import shutil
from dataclasses import dataclass, field
from pathlib import Path


def _load_dotenv(path: Path) -> None:
    if not path.is_file():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip("'\""))


@dataclass(slots=True)
class Settings:
    project: Path
    vault: Path
    runtime: Path
    ollama_base_url: str
    ollama_model: str
    ollama_fast_model: str
    ollama_fallback_model: str
    whisper_model_path: Path
    tts_voice: str
    provider_timeout: float = 120.0
    transcription_timeout: float = 120.0
    max_prompt_chars: int = 20_000
    max_audio_bytes: int = 25 * 1024 * 1024
    allowed_memory_dirs: tuple[str, ...] = field(default_factory=lambda: ("Alfredo",))
    hud_root: Path = field(
        default_factory=lambda: Path(__file__).resolve().parents[1],
    )

    @classmethod
    def load(cls, env_file: Path | None = None) -> "Settings":
        hud_root = Path(__file__).resolve().parents[1]
        project = Path(os.getenv("ALFREDO_PROJECT", Path.cwd())).expanduser().resolve()
        _load_dotenv(env_file or hud_root / ".env")
        runtime = Path(os.getenv("ALFREDO_RUNTIME", "~/Library/Application Support/Alfredo")).expanduser().resolve()
        runtime.mkdir(parents=True, exist_ok=True)
        (runtime / "tmp").mkdir(exist_ok=True)
        defaults = runtime / "models/whisper/ggml-small.bin"
        dirs = tuple(x.strip() for x in os.getenv("ALFREDO_MEMORY_DIRS", "Alfredo").split(",") if x.strip())
        return cls(
            project=Path(os.getenv("ALFREDO_PROJECT", project)).expanduser().resolve(),
            vault=Path(os.getenv("ALFREDO_VAULT", "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/AlfredoVault")).expanduser().resolve(),
            runtime=runtime,
            ollama_base_url=os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434").rstrip("/"),
            ollama_model=os.getenv("OLLAMA_MODEL", "qwen3.5:9b"),
            ollama_fast_model=os.getenv("OLLAMA_FAST_MODEL", "qwen3.5:4b"),
            ollama_fallback_model=os.getenv("OLLAMA_FALLBACK_MODEL", "qwen3.5:2b"),
            whisper_model_path=Path(os.getenv("WHISPER_MODEL_PATH", defaults)).expanduser().resolve(),
            tts_voice=os.getenv("ALFREDO_TTS_VOICE", "Luciana"),
            provider_timeout=float(os.getenv("ALFREDO_PROVIDER_TIMEOUT", "120")),
            transcription_timeout=float(os.getenv("ALFREDO_TRANSCRIPTION_TIMEOUT", "120")),
            max_prompt_chars=int(os.getenv("ALFREDO_MAX_PROMPT_CHARS", "20000")),
            max_audio_bytes=int(os.getenv("ALFREDO_MAX_AUDIO_BYTES", str(25 * 1024 * 1024))),
            allowed_memory_dirs=dirs or ("Alfredo",),
            hud_root=hud_root,
        )

    def executable(self, name: str) -> str | None:
        return shutil.which(name)


settings = Settings.load()
