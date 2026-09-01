# Agent adapter contract

Alfredo keeps one canonical package representation and maps it into each
agent's local configuration layout. Adapters own path selection and rendering;
they never mutate package sources.

The same rule applies to Task Runtime. `.alfredo/` owns tasks, sessions, runs,
checkpoints, dependencies, and context references. Agent directories may contain
rendered bootstrap files, skills, rules, and agents, but they must not become
authoritative work stores.

| Target | User root | Project root | Skill rendering |
| --- | --- | --- | --- |
| Codex | `.codex/` | `.agents/` | canonical `skills/` tree |
| Claude Code | `.claude/` | `.claude/` | canonical `skills/` tree |
| Cursor | `.cursor/` | `.cursor/` | native canonical `skills/` tree |
| Antigravity | `.gemini/config/` | `.agents/` | canonical `skills/` tree |
| Generic | `.alfredo/` | `.alfredo/` | canonical content tree |

Installation preserves each canonical content path verbatim under the target
root, so `skills/<name>/SKILL.md` lands at `<target>/skills/<name>/SKILL.md`,
`rules/<name>.md` at `<target>/rules/<name>.md`, and `agents/<name>.md` at
`<target>/agents/<name>.md`. For Claude Code that last path is
`~/.claude/agents/<name>.md`, the native sub-agent location. See
[agents.md](agents.md) for the agent catalog contract.

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
- Keep per-target, per-scope lockfiles under `.alfredo/runtime/locks/`.
