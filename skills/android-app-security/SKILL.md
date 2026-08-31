---
name: android-app-security
description: Assess, harden, and—only in explicitly authorized labs—test Android application security across app, IPC, storage, network, WebView, native, and platform boundaries.
tags: [domain:android, discipline:security, topic:app-security, topic:offensive-security, topic:defensive-security, topic:hardening, tool:adb]
---

# Android App Security

Use this skill for Android application security reviews, defensive remediation, or authorized security testing. Keep observation, defense, lab exploitation, and privileged operations distinct.

## Select the authorized mode

- **Observation:** inspect manifests, APK metadata, runtime configuration, logs, and behavior without altering the app, device, account, data, or traffic.
- **Defense:** design or implement mitigations such as component exposure controls, permission checks, secure storage, network hardening, WebView controls, supply-chain updates, native hardening, logging hygiene, and regression tests.
- **Authorized lab exploitation:** demonstrate a specific hypothesis only when the user explicitly identifies an owned/authorized target and test environment, allowed techniques, and scope. Keep impact minimal, use synthetic data, and stop once the hypothesis is proven.
- **Privileged actions:** rooting, bootloader changes, debugging other apps, bypassing security controls, extracting protected data, persistence, account/session access, or interacting with production systems require explicit authorization immediately before the action. Do not infer it from a general assessment request.

## Assess by Android attack surface

- Model exported activities/services/receivers/providers, intent handling, pending intents, deep links/app links, custom permissions, Binder boundaries, shared storage, backups, WebView/JS bridges, TLS/network security, authentication/session state, dynamic code/loading, native libraries, and third-party SDKs.
- Verify enforcement at the receiving boundary, not only at the caller. Consider caller UID/package verification, signature permissions, URI grants, canonical paths, deserialization, origin isolation, and TOCTOU risks.
- Consider realistic preconditions: Android/API/OEM version, app signing and update path, user interaction, permission state, attacker-app capabilities, device posture, and data sensitivity. Do not label theoretical patterns as exploitable without a reachable path.

## Report and remediate

- Record scope, authorization, affected versions, reproducible evidence, impact, preconditions, and confidence. Redact secrets and avoid publishing operational exploit detail beyond the authorized audience.
- Prioritize fixes that eliminate the vulnerable trust boundary, then add defense in depth. Supply verification steps and regression tests that prove the defense on supported Android versions.
- Escalate immediately when evidence suggests active compromise, credential exposure, sensitive-data exfiltration, or a production-impacting path; preserve evidence and follow the organization’s incident process instead of continuing active testing.
