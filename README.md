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
the invariant guards (`flutter test --no-pub --exclude-tags weekly,bench`),
build the release bundle, and scan that bundle for Android permissions. It
reports rather than rewrites — a formatting failure names the file and leaves
it alone.

Two test tiers are left out of the gate because they take too long for a pull
request. `weekly` runs the engine guards over far more seeds for every size and
difficulty (`engine_guard_weekly_test.dart`), and
`.github/workflows/engine-nightly.yml` runs it every Sunday
(or on demand from the Actions tab). `bench` times the generator on this
machine: `flutter test --tags bench`. `dart_test.yaml` lists what runs where.

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

**Signing.** The four variables are `HS_KEYSTORE_PATH`, `HS_KEYSTORE_PASS`,
`HS_KEY_ALIAS` and `HS_KEY_PASS` — named here because the documentation
referred only to `HS_*`, so a contributor could not learn them from it
(#123). Set all four to sign with the upload key; set none and the release
build falls back to the debug key, so the gate passes on a fresh clone with
no secrets. Setting some but not all is refused rather than silently
downgraded.

`HS_RELEASE=1` makes a missing signing input a hard failure instead of that
fallback — that is how CI proves a release is really signed. Only the exact
value `1` counts; anything else warns and is treated as unset.

`tools/gate.sh --signing-mode` prints what the next build would do, without
running one. The build writes its own verdict to `$HS_SIGNING_VERDICT` and the
gate reads it back, so a disagreement between the two is itself a gate
failure.

Verify a built bundle against the committed certificate with
`tools/verify_upload_cert.sh`. The signing procedure and the rotation runbook
are in `.n8/memory/android-signing.md`; the certificate's alias and
fingerprint are in `android/signing/README.md`.

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

**Never re-tag a version that shipped; ship the next one.** A moved tag
would produce a second build claiming to be the same release, and Play will
not accept a version code it has already seen.

A tag whose run failed *before* the `ship` job is a different case, and it has
a precedent: `v0.1.0` was first cut at a commit whose gate was cancelled by the
battery's timeout, so no bundle was built and no version code was consumed. The
release object held no assets, the tag was deleted, and it was re-cut at the
commit carrying the fix. Check both — no assets on the release, `ship` skipped
in the run — before moving a tag, and say so where you record it.

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
| `HS_KEY_PASS` | the key password — **must equal `HS_KEYSTORE_PASS`** |
| `PLAY_SERVICE_ACCOUNT_JSON` | the Play Developer API service-account key |

A PKCS12 keystore has one password for the store and the key, so those two
are the same value by format design. `keytool` ignores a separate `-keypass`
and exits 0 whatever it is given, so nothing can prove a key password after
the fact — the release workflow asserts the two secrets agree instead, and
refuses before building if they do not.

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

Three things are held back, because they are not ours to give away:

**Audio.** When licensed sound effects ship, they will not be covered by the
MIT licence, and their provenance will be recorded in the audio licence file
that ships beside them. Synthesised placeholder sounds are MIT-covered like the
rest of the code.

**Fonts.** Outfit and IBM Plex Mono, bundled in `assets/fonts/`, are under
the SIL Open Font License 1.1, whose texts sit beside them; they are neither
covered by the MIT licence nor trademarks of Honest Arcade. IBM Plex Mono's
licence reserves the font name "Plex" (Outfit's reserves none), and
`assets/fonts/README.md` records where each file came from.

**Names and logos.** "Honest Arcade", "Honest Sudoku", the four-corner outline
mark shared across the studio's apps, and the launcher icons built from it are
trademarks of Honest Arcade. A copyright licence does not grant trademark
rights: fork the game freely, but ship it under your own name and mark.

## Security

See [SECURITY.md](SECURITY.md) for how to report a vulnerability.
