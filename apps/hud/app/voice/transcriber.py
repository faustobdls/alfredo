from __future__ import annotations

import asyncio, shutil, tempfile
from pathlib import Path
from app.config import Settings

ALLOWED_MIME = {"audio/webm", "audio/ogg", "audio/mp4", "audio/mpeg", "audio/wav", "audio/x-wav"}


class AudioError(ValueError): pass


class Transcriber:
    def __init__(self, config: Settings): self.config = config

    async def transcribe(self, data: bytes, mime: str) -> str:
        base_mime = mime.split(";", 1)[0].lower()
        if base_mime not in ALLOWED_MIME: raise AudioError("Formato de áudio não aceito.")
        if not data or len(data) > self.config.max_audio_bytes: raise AudioError("Áudio vazio ou acima do limite permitido.")
        whisper = shutil.which("whisper-cli")
        ffmpeg = shutil.which("ffmpeg")
        if not whisper or not ffmpeg: raise AudioError("ffmpeg ou whisper-cli não está disponível.")
        if not self.config.whisper_model_path.is_file(): raise AudioError("Modelo Whisper não encontrado no caminho configurado.")
        temp_dir = Path(tempfile.mkdtemp(prefix="audio-", dir=self.config.runtime / "tmp"))
        source, wav = temp_dir / "input", temp_dir / "audio.wav"
        try:
            source.write_bytes(data)
            await self._run([ffmpeg, "-nostdin", "-v", "error", "-y", "-i", str(source), "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", str(wav)], 45)
            out = await self._run([whisper, "-m", str(self.config.whisper_model_path), "-f", str(wav), "-l", "auto", "-nt"], self.config.transcription_timeout)
            return " ".join(line.strip() for line in out.splitlines() if line.strip()).strip()
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)

    async def _run(self, args: list[str], timeout: float) -> str:
        proc = await asyncio.create_subprocess_exec(*args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        try: out, err = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        except TimeoutError:
            proc.kill(); await proc.wait(); raise AudioError("A operação de áudio excedeu o tempo limite.")
        if proc.returncode: raise AudioError(err.decode(errors="replace")[-800:] or "Falha no processamento do áudio.")
        return out.decode(errors="replace")

