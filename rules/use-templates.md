# Use templates

An output template is a project's recorded contract for how a class of artifact
should come out — an email, a slide deck, a memo. When one exists, it is the
house style for that artifact, not a suggestion. These rules govern applying it.

## Check before you write

- Before producing an email, a slide deck, a memo, a report, or any comparable
  authored artifact, resolve a template: `alfredo template match <kind>`.
- If a template resolves, read it in full — frontmatter and body — before
  drafting.
- If none resolves, proceed and say so plainly in the result. Do not invent a
  template or borrow one from another project.

## Follow the contract

- Hold the declared `voice`: temperature, person, greeting, and sign-off.
- Produce the declared `structure`, in order. Note any section the source
  material cannot fill rather than padding it.
- Stay within `length`. Honour every `constraints.always` and
  `constraints.never`.
- Render to `format.target`, using `format.theme` for styling. Hand off to
  whatever renderer the session has; the template names the target, not the
  tool.

## Keep authoring and checking apart

- Applying a template is authoring. Verifying the artifact against the template
  is a separate pass: sections present, tone held, length met, nothing
  forbidden. Defer to **separate-authoring-from-review**.
