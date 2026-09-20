# Honest Sudoku

A fully offline Sudoku game for Android phones, built with Flutter.

The project is under construction; gameplay and features are planned and tracked as GitHub Issues.

## Requirements

- Android 7.0 (API 24) or newer.
- Flutter (stable channel) and a JDK 17 or newer for the Gradle build.

## Build and run

```sh
flutter pub get
flutter run                        # a connected Android device or emulator
flutter build appbundle --debug    # the Android App Bundle
```

## Quality gate

One command runs everything CI runs, in the order CI runs it:

```sh
tools/gate.sh
```

Six steps, stopping at the first failure: resolve dependencies against the
lockfile, analyze (infos are fatal), check formatting, run the tests including
the invariant guards, build the release bundle, and scan that bundle for
Android permissions. It reports rather than rewrites — a formatting failure
names the file and leaves it alone.

The **CI** workflow (`.github/workflows/ci.yml`, job `gate`) runs this same
script on every pull request, so green locally and green in CI mean the same
thing. `main` will not accept a merge until that check passes — the
`main-pr-required` ruleset requires the status check named `gate`, which is
what the checks list renders as `CI / gate`. The required context is the
**check-run name**, not the rendered one; setting it to `CI / gate` blocks
every merge instead, because nothing ever reports under that name. The invariant
guards also run as their own named step before the full gate, so a breached
invariant is the first red line in the checks rather than something to find
inside a long log.

**The Flutter version.** `.fvmrc` holds the exact version CI uses, and
`pubspec.yaml` declares the minimum the code needs. To move to a newer Flutter,
bump `.fvmrc` and, if the code now needs it, raise the `flutter:` range under
`environment:` — a guard fails if the pin drops below the range. Running the
gate on a different local version prints one note on stderr and carries on;
CI always uses the pin.

**Signing.** With no `HS_*` variables set the release build falls back to the
debug key, so the gate passes on a fresh clone with no secrets, and the build
step says which key it used. With `HS_RELEASE=1` and no secrets the gate fails
at the build step on purpose: that is how CI proves a release is really signed.
The signing procedure and the rotation runbook are in
`.n8/memory/android-signing.md`.

## Release

A release is a tag. Nothing is published by hand.

```sh
git tag v0.1.0 && git push origin v0.1.0
```

`.github/workflows/release.yml` triggers on any `v*` tag. It re-runs the whole
PR gate first (`uses: ./.github/workflows/ci.yml`, not a second copy of the
steps), then builds a signed bundle, scans it for Android permissions, checks
it against the committed upload certificate, attaches it to the GitHub release
with a `.sha256` sidecar, and uploads it to the Play **internal** track. The
Play upload is the last step, so a failure anywhere earlier ships nothing.

**Never re-tag a version; ship the next one.** A moved tag would produce a
second build claiming to be the same release, and Play will not accept a
version code it has already seen.

**Version codes.** `tools/ci_version.sh <ref> <run_number> <run_attempt>`
derives them: the name is the tag without its `v`, and the code is
`1000 + run_number * 10 + run_attempt`. That rises strictly across runs, and a
re-run of a failed run gets a higher code than the attempt it replaces — which
matters because Play rejects a reused code.

**Promotion** is a separate manual workflow: `.github/workflows/play-promote.yml`
moves the newest completed release from one testing track to another. It
refuses `production` in its first step, before any credential is minted.
Production is a human act in the Play Console, on purpose.

**The five secrets** the release path reads, all repository secrets:

| Secret | What it holds |
|---|---|
| `HS_KEYSTORE_B64` | the upload keystore, base64 on one line |
| `HS_KEYSTORE_PASS` | the keystore password |
| `HS_KEY_ALIAS` | the key alias inside the keystore |
| `HS_KEY_PASS` | the key password |
| `PLAY_SERVICE_ACCOUNT_JSON` | the Play Developer API service-account key |

They are set once, by name, from scripts rather than by hand:
`tools/setup_play_ci.sh` creates the service account and sets the last one;
`tools/set_ci_secrets.sh` sets the other four from the local credentials file.
Neither ever prints a value. `.github/workflows/play-api-check.yml` is a manual
dispatch that proves the secrets work — that the service account can reach the
Play API and that the keystore secrets open the keystore — without building or
publishing anything.

## Privacy

The app collects nothing and has no network access: the release build requests
no Android permissions at all, INTERNET included. The full policy is published
at <https://honestarcade.github.io/HonestSudoku/privacy> and lives in this
repository at `docs/privacy.md` — everything under `docs/` is public.

## License

**MIT** (see `LICENSE`) — covering the source code and the art, so a clone
builds the actual game rather than a silhouette of it. Use it, learn from it,
ship your own.

Two things are held back, because they are not ours to give away:

**Audio.** When licensed sound effects ship, they will not be covered by the
MIT licence, and their provenance will be recorded in the audio licence file
that ships beside them. Synthesised placeholder sounds are MIT-covered like the
rest of the code.

**Names and logos.** "Honest Arcade", "Honest Sudoku", the four-corner outline
mark shared across the studio's apps, and the launcher icons built from it are
trademarks of Honest Arcade. A copyright licence does not grant trademark
rights: fork the game freely, but ship it under your own name and mark.

## Security

See [SECURITY.md](SECURITY.md) for how to report a vulnerability.
