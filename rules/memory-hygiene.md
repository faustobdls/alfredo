# Memory hygiene

These rules keep the memory store searchable, trustworthy, and safe to sync.

## Shape

- Write exactly one fact per note. If describing a note requires the word "and",
  it is two notes.
- Durable facts belong in `notes/`; time-bound observations belong in
  `journal/`. Do not put a decision in the journal and expect to find it later.
- Give every note a title that would work as a search query.

## Scope

- Choose the user store for cross-project practice and the project store for
  anything meaningful only inside the current repository.
- When the correct scope is ambiguous, suggest a scope, explain why, and ask the
  user before writing. A fact filed in the wrong store is a fact nobody finds.

## Safety invariants

- Never record secrets, credentials, tokens, private keys, or personal data.
- Never record `.env` contents, even redacted. Record that a credential exists
  and where it is configured, never its value.
- Never edit or delete a past journal entry. Append a dated correction instead;
  the history of a wrong belief is part of the record.
- Never hand-edit `MEMORY.md`. It is regenerated from the journal and notes.
