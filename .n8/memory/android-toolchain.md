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
- `flutter doctor` reports `cmdline-tools component is missing`, and it still
  does after a successful build. **This did not block anything.** The Gradle
  build installed what it needed by itself and accepted the licences as it went:
  SDK Platform 36 and CMake 3.22.1 were both fetched and their licences accepted
  during `flutter build appbundle --debug`.
- So the fallback the plan described — download the command-line tools zip, run
  `sdkmanager`, then `flutter doctor --android-licenses` — **was not needed**.
  Leave it here as the remedy if a future build does complain about licences.
- `flutter doctor` will keep showing that warning. It is not a blocker and
  should not be treated as one.

## First build cost

`flutter build appbundle --debug` took **163 seconds** of Gradle time on a cold
cache, most of it downloading and installing the SDK platform, CMake and the
Kotlin toolchain. Later builds are much faster. Anything that times out a first
build at two minutes will fail for this reason alone and not because the build
is broken.

## No device

There is **no physical Android device attached and no AVD** on this machine.
#12's launcher, label and rotation checks were verified against the built
bundle's own manifest rather than a running app — the bundle is the artefact
that ships, so it is the stronger evidence for those three facts. Anything
genuinely needing a running app (M6's device passes) needs an AVD created first,
which needs the command-line tools above.
