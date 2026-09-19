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

## Test and lint

```sh
dart analyze
dart format --set-exit-if-changed .
flutter test
```

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
