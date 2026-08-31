# Rules catalog contract

Alfredo ships a set of **rules** alongside `skills/` and `agents/`. A rule is an
always-on constraint or standard: guidance meant to be in an agent's context for
every task, not consulted on demand. Rules live in `rules/` as one Markdown file
per rule and install into each target's rule directory unchanged.

## On-disk shape

```text
rules/
├── smallest-change.md
├── verify-before-claiming.md
├── atomic-commits.md
└── ...
```

Each file is plain Markdown, no frontmatter:

```markdown
# Title

One or two sentences on what this rule governs.

## Section

- Imperative bullets. Short. Each one enforceable.
```

Rules are transformed into each agent's native format by the adapters; the
canonical file stays format-neutral.

## Packaging

The `rules-core` package declares `contents.rules: [rules/<name>.md, ...]` and
targets every agent. `alfredo setup` installs it automatically. `memory-core`
also ships two rules (`memory-usage.md`, `memory-hygiene.md`) scoped to the
memory subsystem.

## The `rules-core` set

Nine always-on rules, in Alfredo's voice:

| Rule | Governs |
| --- | --- |
| `smallest-change` | Keeping diffs proportional to the request |
| `verify-before-claiming` | Fresh evidence before "done" / "fixed" / "passing" |
| `match-the-house-style` | New code reading like the code around it |
| `atomic-commits` | One logical change per commit; commit only when asked |
| `authorization-boundaries` | Confirming hard-to-reverse and outward-facing actions |
| `report-outcomes-faithfully` | Reports that match what actually happened |
| `ask-only-when-blocked` | Asking only genuine user decisions, one at a time |
| `secrets-and-exfiltration` | Credential handling and private data leaving the machine |
| `separate-authoring-from-review` | Author and reviewer are different passes |

## The Alfredo tone

Rules are written as Alfredo would state a house standard: plainly, in the
imperative, without apology or padding. They describe the standard and the
boundary, not the feelings around it. See [agents.md](agents.md) for the persona.

## Adding a rule

1. Add `rules/<name>.md` in the shape above.
2. Add its path to `packages/rules-core/package.yaml`.
3. Bump `packages/rules-core/package.yaml` `version`.
4. Record the change in `CHANGELOG.md`.
