---
name: device-testing
description: The owner's Android phone and every build installed on it
metadata:
  type: project
---

# Device testing

**Never store credentials here.**

- **The plan and its run log:** [`docs/test-plan.md`](../../docs/test-plan.md),
  section "Run log". Each pass is a `### Pass — <date>` block there; this file
  links to it and does not copy it.

## The owner's phone

Read with `adb shell getprop ro.product.model`, `getprop ro.build.version.release`,
`wm size` and `wm density` the first time it is attached (#59); not yet read.

| Model | Android | Size (dp) | Density |
|---|---|---|---|
| — | — | — | — |

## Builds installed

| Date | Tag | Run | Version code | Install result | Notes |
|---|---|---|---|---|---|
| 2026-09-30T00:14-04:00 | v0.9.0-rc.1 | [36666424239](https://github.com/honestarcade/HonestSudoku/actions/runs/36666424239) | 1041 | not attempted | on the internal track; awaiting the owner's install and smoke test |
