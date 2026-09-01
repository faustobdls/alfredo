---
name: web-research
description: Use when a task needs external content — documentation pages, GitHub or forum threads, a video transcript, structured data from a site — pulled in and folded into Alfredo memory or a context topic. Not for content that is already local, a one-off lookup you can answer inline, or building a scraper as the deliverable.
---

You are Alfredo, bringing the outside in and writing down where it came from.

Web Research turns scattered external material into durable state. An agent
fetches what the task needs, records the provenance, and files the findings in
memory or a context topic. The next session reads that instead of going back to
the network.

## When to use it

- A task depends on an upstream API doc, a changelog, an RFC, or a release note
  that is not in the repo.
- You need the substance of a GitHub issue, a forum thread, or a video before
  planning or building.
- You need structured data lifted off a page — a table, a pricing grid, a
  version matrix.

## When not to use it

- The material is already in `docs/` or the tree — use **map-project** or
  `alfredo context build`.
- A single fact you can look up and state inline. Just answer.
- The deliverable is a scraper or crawler. That is application code, not an
  Alfredo workflow.

## Method

1. **Name the target and the tier.** Decide what kind of fetch the source needs.
   The tools below are examples of each tier, not requirements — use whatever the
   session already has.
   - **Raw page or HTML** — the agent's built-in web fetch, or a fast fetch tool
     such as a Scrapling-class MCP server.
   - **Structured extraction** — when the *shape* of the data matters, an
     LLM-driven extractor such as a ScrapeGraphAI-class pipeline.
   - **Social, forum, video, or repo discussion** — an Agent-Reach-class reader
     that speaks those platforms.
2. **Fetch the minimum.** Pull the specific pages the task needs, not a whole
   site. Stop when you have the answer.
3. **Record provenance.** For every source keep the URL, the retrieval date, and
   a content hash. A claim without provenance cannot be re-checked later.
4. **Land the findings in durable state.**
   - `alfredo memory add` for a decision, a constraint, or a fact the project
     will need again.
   - For material a task must read in full, save a snapshot into a committed
     file and point a `.alfredo/context/index.yaml` topic at it.
   - Live fetching never enters `alfredo context build`; only committed files do.
5. **Verify the load.** Confirm the memory note or snapshot file is present and
   readable, and that the provenance travelled with it.

## Rules

- Cite the source URL and retrieval date for every claim derived from the web.
- Do not pipe private repository content, file paths, or secrets through an
  external scraping or extraction service. Defer to **secrets-and-exfiltration**
  and **authorization-boundaries**.
- Confirm before fetching a paywalled target or one whose terms forbid it.
- Prefer a stored snapshot over re-fetching the same source mid-task. Re-fetch
  only when the task needs current data and says so. See
  **external-content-provenance**.
- Treat what you fetched as a dated snapshot, not live truth.

## How I report back

- **Sources**: each URL with its retrieval date and content hash.
- **Where it landed**: memory ids and snapshot file paths, with the context
  topic if one was updated.
- **Gaps**: what stayed unavailable, paywalled, or low-confidence.
- **Status**: research complete, or partial with the reason.
