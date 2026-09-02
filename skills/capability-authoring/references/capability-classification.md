# Capability classification

Classify the observable job before choosing its container. A user-supplied
label is a hint, not the decision.

1. A deterministic operation with a fixed input and output contract belongs in
   the CLI or an adapter, not in a prompt artifact.
2. A constraint that should apply broadly and continuously is a `rule`.
3. A durable voice or preference seed is a `persona`.
4. A reusable output shape is a `template`.
5. A repeatable procedure that can run in the caller's context is a `skill`.
6. A focused worker that benefits from an isolated context, an unknown number
   of investigation steps, or independent review is an `agent`.
7. A distributable group of canonical content with targets, dependencies, and
   versions is a `package`.

If a method is reusable but its application requires isolated investigation,
split it: put the method in a skill and let the agent apply it. Stop and ask
when no classification has a clear observable fit.
