# Rules catalog contract

Alfredo ships a set of **rules** alongside `skills/` and `agents/`. A rule is a
constraint or standard rendered by adapters into an agent environment. Rules
live in `rules/` as one Markdown file per rule and install into each target's
rule directory unchanged.

The long-term context strategy is not "load every rule forever." Rules should be
classified as either compact core invariants or conditional policies.

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

## Classification

Core invariants should be few and short enough to remain in every context:

- `smallest-change`
- `verify-before-claiming`
- `authorization-boundaries`
- `secrets-and-exfiltration`
- `report-outcomes-faithfully`

Conditional policies are loaded when the workflow or task calls for them:

- `atomic-commits` when Git operations or commits are relevant.
- `match-the-house-style` when authoring or editing code.
- `separate-authoring-from-review` when review is part of the workflow.
- `ask-only-when-blocked` when autonomous execution is requested.
- `memory-usage` and `memory-hygiene` when using the memory subsystem.
- `external-content-provenance` when the `web-research` skill runs or a task
  pulls in external content.

Adapters may still install the whole catalogue for compatibility. Context
routing should prefer the split above to reduce always-on token cost.

## The `rules-core` set

Ten rules, in Alfredo's voice:

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
| `external-content-provenance` | Fetched content is a dated, hashed snapshot, not live truth |

## The Alfredo tone

Rules are written as Alfredo would state a house standard: plainly, in the
imperative, without apology or padding. They describe the standard and the
boundary, not the feelings around it. See [agents.md](agents.md) for the persona.

## Adding a rule

1. Add `rules/<name>.md` in the shape above.
2. Add its path to `packages/rules-core/package.yaml`.
3. Bump `packages/rules-core/package.yaml` `version`.
4. Record the change in `CHANGELOG.md`.
