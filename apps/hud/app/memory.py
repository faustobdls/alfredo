from __future__ import annotations

import asyncio, json, os, re, tempfile, uuid
from pathlib import Path
from app.config import Settings


class MemoryError(ValueError): pass


class MemoryStore:
    def __init__(self, config: Settings):
        self.config = config
        self.proposals = config.runtime / "proposals"
        self.proposals.mkdir(parents=True, exist_ok=True)
        self._locks: dict[Path, asyncio.Lock] = {}

    def safe_target(self, relative: str) -> Path:
        raw = Path(relative)
        if raw.is_absolute() or ".." in raw.parts or raw.suffix.lower() != ".md": raise MemoryError("Caminho inválido; use um arquivo .md relativo.")
        if not raw.parts or raw.parts[0] not in self.config.allowed_memory_dirs: raise MemoryError(f"A escrita deve ficar em: {', '.join(self.config.allowed_memory_dirs)}.")
        vault = self.config.vault.resolve()
        target = (vault / raw).resolve(strict=False)
        if not target.is_relative_to(vault): raise MemoryError("Caminho fora do cofre.")
        cursor = vault
        for part in raw.parts[:-1]:
            cursor /= part
            if cursor.is_symlink() and not cursor.resolve().is_relative_to(vault): raise MemoryError("Symlink aponta para fora do cofre.")
        return target

    def read_selected(self, paths: list[str]) -> list[tuple[str, str]]:
        selected = []
        vault = self.config.vault.resolve()
        for relative in paths[:8]:
            raw = Path(relative)
            if raw.is_absolute() or ".." in raw.parts or raw.suffix.lower() != ".md": raise MemoryError("Caminho de contexto inválido.")
            try: target = (vault / raw).resolve(strict=True)
            except OSError as exc: raise MemoryError("Nota de contexto não encontrada.") from exc
            if not target.is_relative_to(vault) or target.is_symlink() or not target.is_file(): raise MemoryError("Nota de contexto fora do cofre ou inválida.")
            selected.append((str(raw), target.read_text(encoding="utf-8")[:4_000]))
        return selected

    def search(self, query: str, limit: int = 8) -> list[dict]:
        terms = [x for x in re.findall(r"\w+", query.casefold()) if len(x) > 1]
        if not terms or not self.config.vault.is_dir(): return []
        found = []
        for path in self.config.vault.rglob("*.md"):
            rel = path.relative_to(self.config.vault)
            if any(p.startswith(".") for p in rel.parts) or path.is_symlink(): continue
            try: text = path.read_text(encoding="utf-8")[:500_000]
            except (OSError, UnicodeError): continue
            hay = f"{path.stem}\n{text}".casefold()
            score = sum(hay.count(t) for t in terms)
            if not score: continue
            pos = min((hay.find(t) for t in terms if t in hay), default=0)
            excerpt = " ".join(text[max(0, pos-80):pos+240].split())
            found.append({"path": str(rel), "title": path.stem, "excerpt": excerpt, "score": score})
        return sorted(found, key=lambda x: (-x["score"], x["path"]))[:max(1, min(limit, 20))]

    def propose(self, relative: str, title: str, content: str) -> dict:
        self.safe_target(relative)
        proposal_id = uuid.uuid4().hex
        payload = {"id": proposal_id, "path": relative, "title": title, "content": content}
        (self.proposals / f"{proposal_id}.json").write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        return payload

    async def approve(self, proposal_id: str) -> dict:
        proposal_file = self.proposals / f"{proposal_id}.json"
        if not proposal_file.is_file(): raise MemoryError("Proposta inexistente ou já utilizada.")
        payload = json.loads(proposal_file.read_text(encoding="utf-8"))
        target = self.safe_target(payload["path"])
        lock = self._locks.setdefault(target, asyncio.Lock())
        async with lock:
            if target.exists(): raise MemoryError("O arquivo já existe; nenhuma sobrescrita foi feita.")
            target.parent.mkdir(parents=True, exist_ok=True)
            body = f"# {payload['title']}\n\n{payload['content'].rstrip()}\n"
            fd, temp_name = tempfile.mkstemp(prefix=".alfredo-", suffix=".tmp", dir=target.parent)
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as handle:
                    handle.write(body); handle.flush(); os.fsync(handle.fileno())
                os.replace(temp_name, target)
            finally:
                if os.path.exists(temp_name): os.unlink(temp_name)
            proposal_file.unlink(missing_ok=True)
        return {"path": payload["path"], "title": payload["title"]}
