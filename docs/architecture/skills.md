# Skills catalog contract

A **skill** is an on-demand capability guide: instructions an agent loads when a
task matches, in place of its default approach. Skills live in `skills/` as one
directory per skill, each with a required `SKILL.md`.

## On-disk shape

```text
skills/
├── autopilot/
│   └── SKILL.md
├── android-app-security/
│   └── SKILL.md
└── ...
```

`SKILL.md` is a Claude Code compatible skill definition:

```markdown
---
name: autopilot
description: Use for <trigger>. Not for <anti-trigger>.
---

<the method the agent should follow>
```

- `name` matches the directory.
- `description` is written as "Use for … Not for …" so an agent can decide
  whether the skill applies.

Assets and scripts a skill needs live beside its `SKILL.md` in the same
directory and are installed with it.

## Two families

**Domain skills** teach a technical capability. The `android-core` package ships
these: kernel internals, platform internals, native development, app security,
and ADB device-fleet operation.

**Workflow skills** teach an orchestration method — how to run a phased,
verified process using Alfredo's [agent catalogue](agents.md). The `skills-core`
package ships ten, in Alfredo's voice:

| Skill | Method |
| --- | --- |
| `autopilot` | Idea → working code: spec, plan, build, QA, validate |
| `ralph` | Persistence loop, story by story, until each passes review |
| `ralplan` | Consensus planning gate before autonomous execution |
| `ultrawork` | Parallel execution of independent units with a concurrency bound |
| `ultraqa` | Test / diagnose / fix cycle until the acceptance criteria pass |
| `team` | Coordinated agents on one shared task list with dependencies |
| `plan` | Ordered work plan, by interview or directly; plan review |
| `deep-interview` | Socratic requirements crystallisation before autonomous work |
| `trace` | Evidence-driven causal investigation with competing hypotheses |
| `deslop` | Deletion-first, regression-safe cleanup of generated slop |

Workflow skills write their working state under `.alfredo/work/<skill>/` so a run
can resume after interruption.

## Packaging

Each package declares `contents.skills: [skills/<name>, ...]`. Installation
preserves the canonical path, so `skills/autopilot/SKILL.md` lands at
`<target>/skills/autopilot/SKILL.md`. `alfredo setup` installs every official
package that supports the target.

## Adding a skill

1. Create `skills/<name>/SKILL.md` (plus any assets) in the shape above.
2. Add `skills/<name>` to the appropriate package's `contents.skills`.
3. Bump that package's `version`.
4. Record the change in `CHANGELOG.md`.
