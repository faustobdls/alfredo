# Templates catalog contract

An **output template** is a project's recorded contract for how a class of
authored artifact should come out — an email, a slide deck, a memo, a report.
It captures the voice, structure, length, format, and hard constraints an agent
should apply whenever it produces that kind of artifact.

Alfredo ships **no templates**. The subsystem is machinery only: a schema, a
CLI, a rule, and a workflow skill. Teams author their own templates and
distribute them like any other content — in a package, from a private source
repo, or as loose files in one project.

When an agent is asked to create a template, it asks three questions before
writing the file: the template kind, what the template is for, and the output
format. It then creates the blank template scaffold in the repository's
`templates/<name>/TEMPLATE.md` and reports that path. It does not create new
templates in the user profile; project-root templates are the exportable source
that can later be packaged as a service.

Templates answer: "what should this artifact look like when it is done?" That is
distinct from skills (a method to follow), rules (an always-on standard), and
memory (what we know).

## On-disk shape

One directory per template, each with a required `TEMPLATE.md`:

```text
templates/
└── bank-email/
    ├── TEMPLATE.md          # YAML frontmatter + Markdown body
    └── references/          # optional: example artifacts, theme assets, seeds
```

`TEMPLATE.md` frontmatter is validated against
[`schemas/template.schema.json`](../../schemas/template.schema.json). The
Markdown body below the frontmatter is free prose — the guidance an agent reads
before drafting, the same progressive-disclosure role a `SKILL.md` method
plays.

```markdown
---
schema_version: 1
name: bank-email                  # matches the directory
kind: email                       # the artifact class this governs
description: Use for client-facing email in the bank's voice. Not for Slack.
voice:
  temperature: formal             # formal | neutral | warm | casual
  person: first-person-plural
  greeting: "Prezado(a) {name},"
  signoff: "Atenciosamente,"
structure:
  - opening: one sentence stating the purpose
  - body: 1-3 short paragraphs, one idea each
  - call_to_action: the explicit next step
length:
  max_words: 220
format:
  target: markdown                # suggested, not closed: markdown, plain,
                                  # email, pptx, marp, gamma, figma-slides,
                                  # docx, html, or a project-defined target
  theme: references/bank-theme.md
constraints:
  always: ["cite the account manager"]
  never: ["emojis", "unhedged legal claims"]
examples:
  - references/example-onboarding.md
---

Prose contract: tone to hold, phrasing to prefer and avoid, and the reasoning
behind the structure above.
```

- `name` and `kind` are lowercase-hyphen identifiers. `name` matches the
  directory.
- `description` is written as "Use for … Not for …" so an agent can decide
  whether the template applies.
- `format.target` is open. Known targets such as `markdown`, `plain`, `email`,
  `pptx`, `marp`, `gamma`, `figma-slides`, `docx`, and `html` are suggestions,
  not a closed enum. A project can define its own target for a pure text file,
  a custom file type, or a renderer handled elsewhere.
- Every field except `schema_version`, `name`, `kind`, and `description` is
  optional. A template can be as small as those four lines plus a body.

## Discovery and precedence

`alfredo template` scans, most authoritative first:

1. `templates/` at the project root — canonical, for a project or source repo
   that authors its own.
2. `<agent-dir>/templates/` inside the project — installed copies
   (`.claude/`, `.agents/`, `.codex/`, `.cursor/`, `.gemini/config/`,
   `.gemini/`, `.devin/`, `.via/`, `.alfredo/`).
3. `<agent-dir>/templates/` under the user's home — user-scoped installs.

Templates are deduped by `name`; the first hit wins, so a canonical template
overrides an installed one of the same name.

## Resolution

`alfredo template match <query>` resolves a template deterministically:

1. exact `name` match, then
2. exact `kind` match (lowest `name` wins on a tie), then
3. highest keyword score of the query against `name` + `kind` + `description`,
   ties broken by `name`.

Step 3 is the fuzzy fallback for a free-text request from an agent. A template
pinned on a task (`context.template`) resolves with steps 1–2 only, so a
briefing stays predictable.

## Packaging and installation

A package declares `contents.templates: [templates/<name>, ...]` in its
`package.yaml`. Installation preserves the canonical path, so
`templates/bank-email/TEMPLATE.md` lands at
`<target>/templates/bank-email/TEMPLATE.md` for every supported target. See
[agent-adapters.md](agent-adapters.md).

`alfredo setup` installs official packages only. Because Alfredo ships no
`templates-*` package, a fresh install has no templates until a team adds one.

### Publishing a template set

```sh
alfredo init source ./bank-templates
# add a package with:
#   contents:
#     templates:
#       - templates/bank-email
#       - templates/bank-slides
alfredo source add bank --local ./bank-templates
alfredo package install bank-templates --target codex
```

## How agents consume templates

- The `use-templates` rule (in `rules-core`, a conditional policy) tells an
  agent to run `alfredo template match <kind>` before producing an artifact and
  to follow whatever resolves.
- The `compose-from-template` skill (in `skills-core`) is the method for turning
  existing source material — an outline, a roteiro, notes — into the finished
  artifact under a resolved template, then verifying the result against the
  contract in a separate pass.
- `alfredo context build` includes a resolved template under
  `sources.templates` when a task sets `context.template`.

## CLI

| Command | Purpose |
| --- | --- |
| `alfredo template list` | Every discovered template: name, kind, description, origin |
| `alfredo template show <name>` | One template's frontmatter and body |
| `alfredo template new <name> --kind <kind> --description <text> --format-target <target>` | Scaffold `templates/<name>/TEMPLATE.md` in the project |
| `alfredo template validate [<name>]` | Validate one template, or all of them |
| `alfredo template match <query>` | Resolve the best template for a kind or request |

## Adding a template kind of your own

1. Ask or decide the kind, what the template is for, and the output format.
2. `alfredo template new <name> --kind <kind> --description <text> --format-target <target>`.
3. Fill in `voice`, `structure`, `length`, `constraints`, and the body.
4. `alfredo template validate <name>`.
5. Ship it in a package's `contents.templates`, or keep it in the project.
