# Audio provenance

> **Scope note.** The repository's `LICENSE` (MIT) covers the source code and
> the art. The audio files listed under **Licensed** below are **not** covered
> by it: they are licensed to Honest Arcade for use in Honest Sudoku, and no
> licence is granted to use them in another project. The synthesised
> placeholders listed under **Placeholders** are MIT-covered like the code.
>
> To make your own clips, the prompts, length budgets and mix levels are all
> in `tools/sfx.py`.

Every file in `assets/audio/` is listed here. The audio guard
(`test/guards/audio_assets_guard_test.dart`) fails the build if a file is
neither a placeholder with a matching digest below nor a canonical clip with a
source and a licence in the Licensed table. This file ships inside the app
beside the clips, because `pubspec.yaml` declares the whole directory so that
a real clip needs no Dart change.

## Licensed

| File | Source | Licence |
|---|---|---|

## Placeholders

Synthesised by `tools/make_placeholder_sfx.py` (Python standard library, no
randomness beyond a seeded generator) and MIT-covered. The digest is the
64-bit FNV-1a of the file's bytes; the guard recomputes it, and
`tools/make_placeholder_sfx.py --check` regenerates the clips and compares.

<!-- placeholders:begin -->
| File | FNV-1a | Source |
|---|---|---|
| `placeholder-place.wav` | `086ccbe544989835` | tools/make_placeholder_sfx.py |
| `placeholder-mistake.wav` | `209a5933cda804eb` | tools/make_placeholder_sfx.py |
| `placeholder-solve.wav` | `22f828836f56f17d` | tools/make_placeholder_sfx.py |
| `placeholder-lose.wav` | `1c1f6bc550aff1ca` | tools/make_placeholder_sfx.py |
<!-- placeholders:end -->

## Replacing a placeholder

Drop the real `<clip>.wav` into `assets/audio/`, delete
`placeholder-<clip>.wav`, and add its row to the Licensed table — no Dart
changes. `tools/sfx.py --install <clip> <file>` does all three.
