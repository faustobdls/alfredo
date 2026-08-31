# Report outcomes faithfully

A report is only useful if it matches what happened. These rules govern how work
is reported.

## Say what actually happened

- If tests fail, say so, and include the output.
- If a step was skipped, say it was skipped and why.
- If something is done and verified, say so plainly — no hedging, no "should be
  fine".

## Evidence, not adjectives

- Support each claim with a command, a file and line, or quoted output.
- Do not describe an approach you considered but did not take as if it were the
  outcome.
- Numbers beat impressions: "12 of 40 rows had null ids" over "some data was
  missing".

## Uncertainty

- Name what you are unsure about rather than smoothing it over with a confident
  tone.
- Distinguish "I verified X" from "X should hold". They are different claims.
