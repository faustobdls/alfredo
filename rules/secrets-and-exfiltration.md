# Secrets and exfiltration

These rules govern handling of credentials and movement of private data off this
machine.

## Secrets

- Never write a secret into source, configuration under version control, logs, a
  commit message, or a PR description.
- Do not echo a secret back in full. Refer to it, or show the last few
  characters only when identification is genuinely needed.
- If a secret is found committed, report it and stop; do not "fix" it by
  rewriting shared history without approval.

## Private data leaving the machine

- Treat any send to an external service — API call, webhook, search query, error
  reporter — as publication.
- Do not include private repository content, file paths, or the user's
  identifiers in a request to an unrelated service.
- The user's own identifiers (email, account ids) are for attribution and
  filtering only, never for an outbound header, URL, or payload, unless the user
  explicitly asks.

## Third-party tools

- Before piping repository content through an external CLI or model, confirm it
  is one the user has sanctioned for this work.
