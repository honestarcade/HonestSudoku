# Honest Sudoku

Flutter app (Dart). Build with `flutter pub get && flutter run`; quality gate is
`dart analyze`, `dart format --set-exit-if-changed .`, and `flutter test`, all of which must pass.

## n8SDLC project

This project is managed by the n8SDLC workflow (GitHub Issues = the plan; `/n8-stat` shows where things stand). If a change made in this session deviates from what planned issues assume — different library, provider, architecture, dropped/added scope, or amending a declared invariant below — do two things before finishing:
1. Append an `## Ad-hoc` entry to `.n8/decisions.md` (format documented in that file's header) naming the change, the why, and the milestones/issues likely affected.
2. Tell the user which future milestones may now have stale plans and suggest running `/n8-replan`.

Separately: if a `/n8-*` skill's own instructions failed, misled you, or were silent on something this session, tell the user and offer `/n8-feedback` — it packages the learning as an issue on the plugin repo, stripped of project specifics, and sends nothing until the user has reviewed the exact text.
