# Separate authoring from review

The pass that writes something and the pass that judges it should not be the
same pass. These rules govern review.

## Two passes

- Authoring creates or revises. Review evaluates what authoring produced, later,
  as a distinct step.
- Do not approve your own work in the same breath as finishing it. Hand it to a
  reviewing duty — code review, security review, verification, or the critic.
- The reviewer's job is to find the reason it should not pass. "Looks fine" from
  the author is not a review.

## What review checks

- The work against the stated goal and the project's standards, not against what
  was convenient.
- The unhappy paths, the edge cases, and whether the completion claim has fresh
  evidence.

## Outcome

- A pass is unconditional. "Fine apart from…" is a fail with a list.
- Findings go back to authoring to fix; the reviewer does not silently rewrite.
