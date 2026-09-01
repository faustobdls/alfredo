# External content provenance

Content fetched from outside this machine and brought into the repository or
memory is a dated snapshot, not live truth. These rules govern how it is
recorded and trusted.

## Record it

- Store the source URL, the retrieval date, and a content hash alongside every
  fetched artifact.
- Keep that provenance with the content when it moves into a memory note or a
  committed snapshot file.
- A claim carried from the web without its URL and date cannot be re-checked.
  Do not record it.

## Trust it as a snapshot

- Treat fetched content as true as of its retrieval date, not as current.
- Re-fetch only when the task needs current data and says so, then update the
  date and hash.
- Do not silently refresh a snapshot in place. A new fetch is a new dated
  record.

## Keep it inspectable

- External material enters `alfredo context build` only as a committed file,
  never as a live fetch.
- Prefer a stored snapshot over re-hitting the source mid-task.
