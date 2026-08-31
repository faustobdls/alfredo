---
name: android-linux-kernel
description: Analyze Android kernel behavior and kernel-to-userspace boundaries for device bring-up, performance, power, scheduling, memory, storage, networking, and security decisions.
tags: [domain:android, domain:linux, discipline:development, topic:linux-kernel, topic:platform-internals]
---

# Android Linux Kernel

Use this skill when a problem crosses the Android framework/native boundary into the Linux kernel, GKI/vendor modules, or device drivers. Do not use it for ordinary application debugging.

## Frame the problem before proposing changes

- Establish the exact kernel and userspace contract: device/SoC, Android release, kernel version and configuration, GKI versus vendor module ownership, boot image/module provenance, SELinux domain, and reproducible symptom.
- Classify the layer at fault: framework policy, HAL, native daemon, Binder/IPC, driver, subsystem, scheduler or resource governor. Prefer traces and counters that distinguish plausible layers over a broad configuration sweep.
- Follow Android-specific ownership boundaries. A change may be technically valid yet incompatible with GKI/KMI stability, module signing, OTA, Verified Boot, SELinux policy, CTS/VTS, or vendor support obligations.

## Investigative discipline

- Use minimally invasive observation first: `dmesg`/log buffers, `/proc` and `/sys`, ftrace/tracefs, Perfetto, Binder and memory diagnostics. Correlate host time and device time when comparing events.
- For memory, separate allocator pressure, reclaim, LMKD policy, PSI, cgroup limits, and an actual kernel leak. For latency, distinguish run-queue delay, CPU frequency/thermal limits, IRQ/driver stalls, I/O wait, and Binder contention.
- For a driver or subsystem proposal, specify the control path, data path, synchronization/lifetime model, failure recovery, power-management behavior, and user-visible compatibility impact.

## Change criteria

- Make the smallest change that tests a stated hypothesis; preserve a known-good boot/recovery path and capture rollback requirements before touching boot-critical artifacts.
- Treat kernel configuration, boot images, privileged debugging, rooting, unlocking, and flashing as explicit authorization gates. Never imply these are routine prerequisites.
- Report evidence, inferred causal chain, uncertainty, affected kernel/userspace contract, validation matrix, and rollback plan. Avoid claiming kernel causality from a single log line or a one-device result.
