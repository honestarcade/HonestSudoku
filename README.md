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

## Security

See [SECURITY.md](SECURITY.md) for how to report a vulnerability.
