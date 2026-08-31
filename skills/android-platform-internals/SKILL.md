---
name: android-platform-internals
description: Reason about Android framework, system-server, Binder, HAL, ART, permissions, and build-system internals when behavior depends on platform boundaries rather than app code alone.
---

# Android Platform Internals

Use this skill for Android platform or AOSP-level behavior: system services, Binder contracts, permission enforcement, process lifecycle, HAL/VINTF, ART/runtime, and build or partition boundaries. It is not a replacement for standard app-development guidance.

## Diagnose by authority and boundary

- Identify the caller identity, process, UID, SELinux domain, permission/AppOp, user/profile, and device configuration that govern the behavior. An API’s Java surface alone rarely explains system behavior.
- Trace the request from API to framework service, Binder interface, native service/HAL, and driver only as far as the evidence requires. State which parts are public SDK, hidden/system API, vendor implementation, or device-specific.
- Separate platform source facts from OEM behavior. Confirm the running build fingerprint and relevant module/partition version before extrapolating from AOSP source.

## Design decisions

- Prefer supported SDK and compatibility-stable extension points. If a solution requires privileged permissions, hidden APIs, signature allowlists, system-image changes, or root, call it out early with deployment and maintenance consequences.
- Preserve Android compatibility boundaries: stable AIDL where applicable, VINTF declarations, SELinux neverallow expectations, API/ABI compatibility, modular-system component ownership, and multi-user semantics.
- For startup/lifecycle failures, correlate Zygote/app process state, system_server service readiness, Binder failures, package manager state, and crash/tombstone evidence rather than relying on a single log tag.

## Output

Explain the responsible component and enforcement point, the supported implementation route, alternatives with their privilege/compatibility cost, verification on representative API/OEM configurations, and any assumption that still needs a device or source check.
