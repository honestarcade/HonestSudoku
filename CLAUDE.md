# Honest Sudoku

Flutter app (Dart). Build with `flutter pub get && flutter run`; quality gate is
`dart analyze`, `dart format --set-exit-if-changed .`, and `flutter test`, all of which must pass.

## Project invariants

Load-bearing constraints no story may breach without an explicit conversation with the owner. Changing one is plan drift by definition: log it as an ad-hoc ledger entry in `.n8/decisions.md` and suggest `/n8-replan`.

1. **No ads, no tracking, no analytics, no network.** The release build declares no Android permissions at all (INTERNET included) and all player data stays on the device. *(test-enforced: manifest guard plus a byte scan of every built bundle, dependency blocklist over pubspec.lock, no web-font references; fonts are bundled, never fetched — guard: #14, #15 (planned))* **Plugins:** any Flutter plugin is adopted only during planning, after the planner has read the plugin's own `AndroidManifest.xml` for permissions and the owner has approved it; build-time permission removal rules are forbidden, and a plugin's `# why:` line records `declares no permissions (manifest checked <date>)`.
2. **Boards are generated on the device at runtime, never bundled, and every board has exactly one solution.** *(test-enforced: property tests run the real generator over many seeds for every size and difficulty and have the solver count solutions — guard: #26 (planned))*
3. **Lean dependencies.** A third-party package is added only when it is necessary, carries a one-line justification in `pubspec.yaml` as a trailing `# why: <reason>` comment on its key line, and never brings ads, analytics, or network access. *(blocklist and justification test-enforced under invariant 1 — guard: #15 (planned); "necessary" is honor-system, checked by audits)*
4. **Deterministic generation.** The same seed, size, and difficulty always produce the same board. *(test-enforced: golden-seed regression test — guard: #26 (planned))*

## n8SDLC project

This project is managed by the n8SDLC workflow (GitHub Issues = the plan; `/n8-stat` shows where things stand). If a change made in this session deviates from what planned issues assume — different library, provider, architecture, dropped/added scope, or amending a declared invariant below — do two things before finishing:
1. Append an `## Ad-hoc` entry to `.n8/decisions.md` (format documented in that file's header) naming the change, the why, and the milestones/issues likely affected.
2. Tell the user which future milestones may now have stale plans and suggest running `/n8-replan`.

Separately: if a `/n8-*` skill's own instructions failed, misled you, or were silent on something this session, tell the user and offer `/n8-feedback` — it packages the learning as an issue on the plugin repo, stripped of project specifics, and sends nothing until the user has reviewed the exact text.
