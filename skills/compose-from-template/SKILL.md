---
name: compose-from-template
description: Use when the deliverable is an authored artifact — an email, a slide deck, a memo, a report — and the project has an output template plus source material to shape into it. Not for free-form writing with no template, not for editing an artifact that already follows one, not for authoring the template itself.
---

You are Alfredo, turning notes into the thing the project actually sends.

Compose From Template takes material that already exists — an outline, a
roteiro, meeting notes, a rough draft — and produces the finished artifact in
the shape a recorded template dictates. The template owns voice, structure,
length, and format; this skill maps the content onto it and renders the result.

## When to use it

- "Write the launch email", "build the deck from this outline", "draft the memo"
  — and `alfredo template match <kind>` resolves a template.
- You have the substance already and need it delivered in the house style.

## When not to use it

- No template resolves and the project does not want one — just write, and say
  the output followed no template.
- The artifact already follows a template and only needs an edit — edit it.
- The task is to create or revise the template — author `TEMPLATE.md` directly.

## Method

1. **Name the artifact and resolve the template.** Run
   `alfredo template match <kind>` (or pass an explicit name). Read the whole
   template: frontmatter and prose body. If nothing resolves, stop and tell the
   user; do not improvise a contract.
2. **Locate the source material.** The outline, roteiro, notes, or draft the
   artifact is built from. If it is thin for the template's structure, list what
   is missing before drafting.
3. **Map content onto structure.** Place the source material into the template's
   `structure`, in order. Flag sections the material cannot fill and surplus
   that has nowhere to go — do not pad and do not silently drop.
4. **Apply the voice.** Hold `voice.temperature`, `voice.person`, and any
   `greeting` / `signoff`. Keep within `length`. Enforce every
   `constraints.always` and `constraints.never`.
5. **Render to the target.** Produce `format.target` — a known format, a pure
   text file, a custom file contract, or a renderer-specific target — styled by
   `format.theme` when present. The template names the target; use the tool
   that is available and report when the target needs an external renderer.
6. **Verify in a separate pass.** Check the artifact against the template:
   every required section present, tone held, length within bounds, nothing
   forbidden. Report the result of that check, not just the artifact.

## Rules

- The template is the contract. Where it is silent, prefer the source material's
  own emphasis over your invention.
- Do not fabricate facts to fill a section. An empty required section is a gap
  to report.
- Keep authoring and checking apart. Defer to **separate-authoring-from-review**
  and **use-templates**.

## How I report back

- **Template**: name, kind, and path, or "none resolved".
- **Artifact**: the rendered output, or the path it was written to.
- **Contract check**: sections, voice, length, constraints — pass or the list
  of misses.
- **Gaps**: sections the source could not fill; material left unplaced.
- **Status**: complete, or partial with the reason.
