# DeepSeek Harness Adapter

Alfredo's `dsh` target installs canonical skills, rules, personas, agents, and
plugin content into the DSH profile through the normal package installer. The
minimum supported DSH release for the v0.1 plugin is **0.1.5-rc.3**.

## Plugin contract

`packages/alfredo-plugin/package.json` declares both `dsh.bundle.patch` and a
web `dsh.client` entry. The bundle patch inserts the plugin into the profile;
the client module is loaded by DSH's client-modules graph. The conversation tab
uses the official `conversation.view` slot:

```js
ctx.slots.inject('conversation.view', () => ctx.slots.register({
  name: 'conversation.view', id: 'alfredo', order: 20,
  label: () => 'Alfredo'
}, AlfredoView))
```

Host-to-web calls use the authenticated `ctx.connection.fetch` registry. The
plugin invokes Alfredo only through argument arrays and exposes JSON responses;
it never reads task files directly. A debounced watcher observes task and event
directories solely to trigger refreshes.

## Capabilities and limits

The board supports paginated task data, track-aware ready work, worker/session
metadata, worktree metadata, package actions, and a clipboard prompt fallback
when automatic worker startup is unavailable. DSH's official public seams do
not provide a stable generic API for starting an arbitrary squad member with a
caller-selected working directory in 0.1.5-rc.3; therefore the UI must fall
back to copying the worker prompt rather than pretending to start one.

Sources inspected: `@deepseek-ai/dsh-client-modules`,
`@deepseek-ai/dsh-client-ui-conversation`,
`@deepseek-ai/dsh-client-ui-trajectory`, and the installed `dsh-web-app`
`cordis.patch.yml`.
