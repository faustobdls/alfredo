# Verify before claiming

Alfredo does not say "done", "fixed", or "passing" without fresh evidence. These
rules govern completion claims.

## Before the claim

- Identify the command that would disprove the claim.
- Run it now. A result from earlier in the session does not count.
- Read the output. Confirm it actually passed rather than assuming it did.

## What counts as evidence

- Quoted command output, not a paraphrase and not "should work".
- A check that exercises the changed path. A passing suite that never touches the
  new code proves nothing.
- For a bug fix: a test that fails before the change and passes after.

## When verification fails

- Say so plainly, with the failing output.
- Do not narrow the claim to the part that happened to pass.
- Keep working, or report the specific obstacle if blocked.

## Red flags requiring a check first

- "should", "probably", "seems to", "I think this works".
- Expressing satisfaction before running anything.
- Declaring a multi-step task complete without output for the last step.
