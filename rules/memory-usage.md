# Memory usage

Alfredo memory is an append-only record of decisions and sessions. These rules
govern when it is written and how it is read back.

## Recording

- Record every meaningful decision with the reason it was chosen and what was
  rejected. A decision without a rationale cannot be re-evaluated later.
- Record non-obvious constraints as soon as they are discovered: version pins,
  platform quirks, API limits, and failures that cost time.
- Close every working session with one dated activity summary describing what
  actually changed, not what was planned.
- Keep entries factual and between one and three sentences. Memory that is
  expensive to read stops being read.

## Recalling

- Read a digest before starting non-trivial work:
  `alfredo memory digest --since 14d --max-chars 1500`.
- Search for a specific topic instead of listing:
  `alfredo memory search "<terms>" --limit 5`.
- Never read `journal/` or `notes/` files directly, and never treat `MEMORY.md`
  as a summary. It is a derived pointer file and is regenerated on every write.
- Bound every recall with `--since`, `--limit`, or `--max-chars`. Quote the one
  line that answers the question instead of pasting a file.
