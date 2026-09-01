# Personas

Personas define voice and communication preferences. They do not replace rules,
skills, agents, or memory:

- `rules/` constrain behavior.
- `skills/` teach task-specific procedures.
- `agents/` define specialist worker roles.
- `personas/` shape tone, phrasing, and durable user-facing preferences.

## On-Disk Shape

Canonical persona seeds live in the source repository:

```text
personas/
├── alfredo.md
└── user.md
```

When installed into the generic Alfredo target for a project, they appear under
`.alfredo/personas/`. `alfredo context build` includes Markdown files from that
directory in the `personas` source group.

## Update Semantics

Persona files are seed content. Alfredo creates them when absent, then preserves
the installed copy across future package updates. If a package ships a new
default persona, existing local persona files are left untouched.

Use `personas/alfredo.md` for Alfredo's product voice. Use `personas/user.md`
for the current user's durable communication preferences.
