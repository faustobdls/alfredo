---
name: adb-device-fleet
description: Operate and collect reproducible UI evidence from multiple Android devices through ADB, especially parallel serial-scoped test and screenshot workflows.
---

# ADB Device Fleet

Use this skill for connected-device discovery, repeatable screenshots, UI state capture, and diagnostics across more than one Android device. It is not a generic Android UI-testing guide.

## Operating model

- Treat the ADB serial as mandatory state. Discover with `adb devices -l`, select explicit serials, and invoke every device command as `adb -s <serial> ...`. Never rely on the implicit default device when a fleet is attached.
- Capture a per-run inventory first: serial, product/model, Android build fingerprint, connection state, target package/activity, and timestamp. Keep evidence in a run directory segmented by serial.
- Run independent device work concurrently, but bound concurrency to avoid saturating USB, ADB server, host storage, or the device under test. Collect per-device results; a timeout or offline device must not discard evidence from healthy devices.
- For visual evidence, first stabilize the target state, then capture both `exec-out screencap -p` and the state needed to interpret it (`uiautomator dump`, focused window/activity, and relevant logs). Name files with an ordered timestamp and serial-safe identifier.

## Evidence and failure isolation

- Check device readiness before actions (`get-state`, boot completion where relevant, screen/keyguard state). Report devices that are unauthorized, offline, or unavailable separately instead of retrying blindly.
- Prefer deterministic transitions: explicit intents, package-scoped commands, and observable completion criteria. Record the exact command and its exit status alongside artifacts.
- When outcomes differ, compare metadata and UI hierarchy before declaring a product regression. Hardware, API level, locale, density, permissions, overlays, and device policy are common confounders.
- Do not delete, reset, install, uninstall, change settings, or grant permissions as part of observation unless the task explicitly authorizes that mutation and identifies the affected serials.

## Deliverable

Return a compact fleet summary: attempted serials, successful evidence paths, per-device failures and stage, commands/state sufficient to reproduce, and a clear distinction between shared and device-specific failures.
