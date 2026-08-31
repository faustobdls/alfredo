# Agent adapter contract

Alfredo keeps one canonical package representation and maps it into each
agent's local configuration layout. Adapters own path selection and rendering;
they never mutate package sources.

| Target | User root | Project root | Skill rendering |
| --- | --- | --- | --- |
| Codex | `.codex/` | `.agents/` | canonical `skills/` tree |
| Claude Code | `.claude/` | `.claude/` | canonical `skills/` tree |
| Cursor | `.cursor/` | `.cursor/` | native canonical `skills/` tree |
| Antigravity | `.gemini/config/` | `.agents/` | canonical `skills/` tree |
| Generic | `.alfredo/` | `.alfredo/` | canonical content tree |

The implementation accepts injectable user and project roots. Normal execution
uses the user's home and current working directory; CI and isolated environments
may set `ALFREDO_USER_ROOT` and `ALFREDO_PROJECT_ROOT`.

These mappings follow the documented extension models for
[Claude Code skills](https://code.claude.com/docs/en/slash-commands),
[Cursor skills](https://prod.cursor.com/docs/skills), and
[Antigravity skills](https://www.antigravity.google/docs/skills?authuser=14).
Codex mapping follows the local `$CODEX_HOME/skills` contract exposed by Codex.

## Safety invariants

- Resolve every canonical source path below its validated source root.
- Stage and digest all files before committing them to the target.
- Refuse collisions with unmanaged files or modified managed files.
- Track ownership outside the agent directory in deterministic installed state.
- Preserve locally modified files during uninstall.
- Keep per-target, per-scope lockfiles under `.alfredo/locks/`.
