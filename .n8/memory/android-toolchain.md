---
name: android-toolchain
description: Which JDK and Android SDK the Gradle build uses on the owner's machine, and what had to be done to make it work
metadata:
  type: project
---

# Android toolchain (owner's machine)

Recorded while executing #12 on 2026-09-19. This is what the build actually
needed, not what was expected — the plan anticipated more manual setup than
turned out to be necessary.

## JDK

- **`/usr/bin/java` is the macOS stub**, not a JDK. Running it prints "Unable to
  locate a Java Runtime". Anything that probes for `java` on `PATH` and believes
  what it finds will think a JDK is present when none is.
- Homebrew's **`openjdk@21`** was already installed at
  `/opt/homebrew/opt/openjdk@21` but was not linked onto `PATH` and not known to
  Flutter.
- Wired it with `flutter config --jdk-dir /opt/homebrew/opt/openjdk@21`. That
  setting lives in Flutter's own config; **no shell rc file was edited**, so
  nothing outside this project changed.
- Gradle then ran on
  `/opt/homebrew/Cellar/openjdk@21/21.0.12.1/.../bin/java` (confirmed in the
  process list during the build).

## Android SDK

- SDK root: `~/Library/Android/sdk`. **There is no Android Studio** on this
  machine.
- **The Gradle build needs no command-line tools.** Early in #12 `flutter doctor`
  reported `cmdline-tools component is missing`, and the build succeeded anyway:
  Gradle fetched SDK Platform 36, NDK 28.2.13676358 and CMake 3.22.1 by itself
  and accepted their licences as it went, during
  `flutter build appbundle --debug`. So the fallback the plan described —
  download the tools zip, run `sdkmanager`, then `flutter doctor
  --android-licenses` — was **not** needed to build.
- They were installed later in the same story anyway, at
  `~/Library/Android/sdk/cmdline-tools/latest`, because creating an emulator
  needs `sdkmanager` and `avdmanager`. See **Emulator** below.
- `flutter doctor` still warns about Android, but the warning **changed** when
  the tools arrived, from `cmdline-tools component is missing` to:

  ```
  [!] Android toolchain - develop for Android devices (Android SDK version 36.0.0)
      ! Some Android licenses not accepted. To resolve this, run: flutter doctor --android-licenses
  ```

  Neither wording has ever blocked a build here. Do not treat either as one, and
  do not grep for the old string expecting to find it.

## First build cost

`flutter build appbundle --debug` took **163 seconds** of Gradle time on a cold
cache, most of it downloading and installing the SDK platform, CMake and the
Kotlin toolchain. Later builds are much faster. Anything that times out a first
build at two minutes will fail for this reason alone and not because the build
is broken.

## Emulator

There is **an AVD on this machine and no physical device**. It was created
during #12, after this file was first written — which is why it used to say
no emulator existed (#81).

- **Name `sudoku-dev`**, device profile `pixel_7`, API 34, image
  `system-images;android-34;google_apis;arm64-v8a`, ABI `arm64-v8a`.
- Created with `avdmanager` from
  `~/Library/Android/sdk/cmdline-tools/latest/bin`, which is why those tools
  were installed at all.
- Start it with
  `~/Library/Android/sdk/emulator/emulator -avd sudoku-dev &`; it comes up as
  `emulator-5554` in `adb devices`.

What was exercised on it in #12, on a running app rather than inferred from the
manifest: the app installed, launched, showed its launcher icon and its
`Honest Sudoku` label, and **held portrait through a forced rotation**.

That rotation check needs a control, and picking the wrong one makes it
worthless. The first control tried was the Pixel launcher, which is itself
portrait-locked — so it "confirmed" the lock by not rotating either, proving
nothing. **Settings is the control that works**: under the same command that
leaves this app at 1080×2400, Settings rotates to 2400×1080.

M6's device passes can use this AVD as it stands. Nothing needs building from
scratch.
