---
name: android-toolchain
description: Which JDK and Android SDK the Gradle build uses on the owner's machine, what had to be done to make it work, and the emulator that exists
metadata:
  type: project
---

# Android toolchain (owner's machine)

Recorded while executing #12 on 2026-09-19, corrected on the same day (#81, #88).
Claims here were checked against the machine on 2026-09-19, and the ones that
were merely kept were checked too — that is the step the first correction
skipped (#88).

**Do not read that as a guarantee.** The second correction then invented a
mechanism to explain the first error and shipped it unchecked under exactly
such a promise (#99). A blanket "everything was verified" is only ever as good
as the pass that wrote it, and this file has now broken one. Treat each
statement below on its own, and prefer the ones that say what was observed
over the ones that say why.

## JDK

- **`/usr/bin/java` is the macOS stub**, not a JDK. Running it prints "Unable to
  locate a Java Runtime". Anything that probes for `java` on `PATH` and believes
  what it finds will think a JDK is present when none is.
- Homebrew's **`openjdk@21`** is at `/opt/homebrew/opt/openjdk@21` (a symlink to
  `Cellar/openjdk@21/21.0.12.1`), not linked onto `PATH`.
- Flutter is wired to it by `flutter config --jdk-dir /opt/homebrew/opt/openjdk@21`.
  That setting lives in `~/.config/flutter/settings`; **no shell rc file was
  edited**, so nothing outside Flutter knows about this JDK. That last clause is
  load-bearing — see the `JAVA_HOME` note under **Emulator**.
- Gradle then runs on that JDK (confirmed in the process list during a build).

## Android SDK

- SDK root: `~/Library/Android/sdk`.
- **Android Studio 2026.1 IS installed**, at `~/Applications/Android Studio.app`.
  An earlier version of this file said there was none (#88).
- **`flutter doctor` lists no Android Studio section at all**, and the reason
  is not where it looks. An earlier correction to this file guessed that doctor
  skips `~/Applications` (#99). It does not — `flutter_tools`'s
  `android_studio.dart` checks `/Applications` and `~/Applications` and runs a
  Spotlight query besides. The real reason is that **this Flutter version ships
  no Android Studio validator**: there is no `android_studio_validator.dart`
  and `doctor.dart` assembles none, so no machine gets that section. Do not
  use doctor's output to decide whether Studio is installed.
- **Nothing in this project's build path uses it.** The build is Gradle via
  `flutter build`, the JDK comes from Flutter's own config, and the emulator is
  driven from the command line. Studio is available if you want a GUI; no
  instruction in this repository depends on it.
- **The Gradle build needs no command-line tools.** Early in #12, with
  cmdline-tools absent, `flutter build appbundle --debug` succeeded: Gradle
  fetched what it needed and accepted the licences as it went. The fallback the
  plan described — download the tools zip, run `sdkmanager`, then
  `flutter doctor --android-licenses` — was not needed to build.
- Present now: `platforms/` holds `android-35`, `android-36` and `android-37.0`;
  `ndk/28.2.13676358`; `cmake/3.22.1`. Only platform 36 and CMake 3.22.1 were
  observed being installed during that build. **Where 35 and 37.0 came from is
  not established** — most likely Android Studio, which was already here. Do not
  read this list as "Gradle fetched all of it".
- Related, and the reason the causal story above is hedged:
  `~/Library/Android/sdk/emulator` is dated **26 August**, well before this
  project began on 18 September. The SDK and the emulator package predate the
  repository.
- `flutter doctor` still warns about Android, and the warning **changed** when
  the command-line tools arrived, from `cmdline-tools component is missing` to:

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

There is **an AVD on this machine and no physical device**.

- **Name `sudoku-dev`**, device profile `pixel_7`, API 34, image
  `system-images;android-34;google_apis;arm64-v8a`, ABI `arm64-v8a`.
- Start it with
  `~/Library/Android/sdk/emulator/emulator -avd sudoku-dev &`; it comes up as
  `emulator-5554` in `adb devices`.
- It was created with `avdmanager` from
  `~/Library/Android/sdk/cmdline-tools/latest/bin`, which is why those tools
  were installed. Note that Android Studio's Device Manager could have done the
  same thing without them — see the SDK section.

**`sdkmanager` and `avdmanager` need `JAVA_HOME` exported first.** They find no
JDK otherwise, because the only one on this machine is known to Flutter's config
and not to the shell:

```sh
$ ~/Library/Android/sdk/cmdline-tools/latest/bin/avdmanager list avd
The operation couldn't be completed. Unable to locate a Java Runtime.

$ JAVA_HOME=/opt/homebrew/opt/openjdk@21 \
    ~/Library/Android/sdk/cmdline-tools/latest/bin/avdmanager list avd
    Name: sudoku-dev
```

`flutter` and Gradle do **not** need this; they read the `jdk-dir` setting.

### What #12 exercised on it

The app installed, launched, showed its launcher icon and its `Honest Sudoku`
label, and held portrait through a forced rotation. This was on a running app,
not inferred from a manifest.

**On the rotation control.** The first control tried was the Pixel launcher,
which did not rotate either — so it confirmed nothing, and the check was redone
against **Settings**, which rotated to 2400×1080 under the same command that
left this app at 1080×2400. That is what was observed. The earlier version of
this note asserted the launcher is "itself portrait-locked" as the explanation;
that is **not** established — the launcher's own manifest declares
`screenOrientation="-1"` (UNSPECIFIED), so whatever held it in portrait was a
runtime setting rather than a manifest lock. Use Settings as the control; treat
the reason as unknown.

M6's device passes can use this AVD as it stands. Nothing needs building from
scratch.
