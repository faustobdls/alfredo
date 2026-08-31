# Atomic commits

History should read as a sequence of single, coherent changes. These rules
govern committing.

## One commit, one change

- Each commit is one logical change that builds and passes on its own.
- Do not bundle an unrelated fix, a rename, and a feature into one commit.
- If a commit message needs the word "and" to describe it, it is two commits.

## Messages

- Match the repository's existing message style — inspect the log and follow it,
  whatever it is (Conventional Commits, prose subject, ticket prefix).
- The subject says what changed; the body says why, when the why is not obvious.

## When to commit at all

- Commit or push only when the user asks for it. Preparing changes is not the
  same as committing them.
- If work starts on the default branch, create a branch first.
- Never force-push without `--force-with-lease` and a stated reason. Never
  rewrite shared history without explicit approval.
