---
name: android-native-development
description: Design and debug Android native code using the NDK, JNI, C/C++, Rust, Binder, and platform constraints with explicit ABI, lifecycle, performance, and deployment tradeoffs.
---

# Android Native Development

Use this skill for native Android implementation or debugging where JNI/NDK, ABI, low-level performance, native crashes, media/graphics, or native IPC materially affects the design. Do not activate for Kotlin-only feature work.

## Choose native deliberately

- State why native code is warranted: existing library reuse, deterministic low-level access, throughput/latency, graphics/media stack integration, or platform service integration. Native code does not bypass Android permission, lifecycle, sandbox, or OEM constraints.
- Define the boundary early: ownership and lifetime across Kotlin/Java and native code, threading/callback contract, cancellation, error conversion, resource cleanup, and what happens on process death or configuration changes.
- Pick the narrowest ABI and distribution strategy compatible with the product. Account for ABI splits, minSdk, NDK/API level, STL/runtime choice, symbol visibility, linker namespaces, Play/device constraints, and reproducible builds.

## Reliability and performance

- Keep JNI crossings coarse and explicit; avoid holding JNI references or VM-attached threads beyond their required lifetime. Use local/global/weak references according to ownership, and ensure native-created threads detach predictably.
- Investigate native failures with symbols and real device artifacts: tombstones, logcat, unwind quality, sanitizer feasibility, and build IDs. Do not treat an unsymbolized crash address as a root cause.
- Measure before optimizing. Attribute costs across JNI marshalling, allocations, locks, I/O, GPU/media pipeline, CPU/thermal throttling, and Android scheduling before proposing a native rewrite.

## Delivery standard

Specify the cross-language contract, supported ABI/API matrix, build and packaging changes, failure behavior, observability, test strategy on physical devices, and a safe fallback when native loading or capability checks fail.
