# Honest Sudoku

Flutter app (Dart). Build with `flutter pub get && flutter run`.

The quality gate is **`tools/gate.sh`** — one command running the six steps CI
runs, in order: dependencies against the lockfile, `dart analyze --fatal-infos`,
format check, `flutter test` (which includes the invariant guards below), the
release bundle build, and `tools/check_aab.sh` over that bundle. It must print
`GATE PASSED` before anything is considered done.

CI runs one more thing the gate does not: **`tools/mutation_check.py`**, its own
job, which reintroduces every known defect one at a time and requires the guard
suite to catch each — naming the assertion that must fire, so a mutation that
merely turns the suite red some other way is reported as WRONG-REASON rather
than a pass. It refuses to run on a dirty tree and restores through a
`try/finally`. Run it locally before changing a guard: a guard weakened by
accident is the failure this project keeps finding, and a green suite is not
evidence that the suite can fail. Adding a guard means adding its mutation.

A comment may say *why*. A claim about what the code does *now* belongs in the
`reason:` of an assertion, where it is executed; a claim about anything else —
history, a measurement, another tool's output, a count — carries a date and a
source in the same sentence, or is cut. Neither half is optional: a `reason:`
cannot hold a fact about history or a measurement, and a sentence with no date
and no source is the one nothing re-reads. Where a count can be computed, cut
it and name the command. When a change is reverted or narrowed, the comments it
added are part of the revert.

Every round of verification since #218 has found new instances, including in
the passes fixing the old ones, so treat this as a standing hazard rather than
a solved problem. The one thing that has worked is moving a claim into
something executed — `dependency_guard_test.dart` holds CLAUDE.md's exemption
list to `pubspec.yaml`, and `memory_guard_test.dart` holds the memory files'
and README's "no credentials here"; neither has rotted. Prefer that to a better
sentence.

## Project invariants

Load-bearing constraints no story may breach without an explicit conversation with the owner. Changing one is plan drift by definition: log it as an ad-hoc ledger entry in `.n8/decisions.md` and suggest `/n8-replan`.

1. **No ads, no tracking, no analytics, no network.** The release build declares no Android permissions at all (INTERNET included) and all player data stays on the device. *(test-enforced: manifest guard plus a byte scan of every built bundle, dependency blocklist over pubspec.lock, no web-font references; fonts are bundled, never fetched — guard: #14, #15 (merged))* **Plugins:** any Flutter plugin is adopted only during planning, after the planner has read the plugin's own `AndroidManifest.xml` for permissions and the owner has approved it; build-time permission removal rules are forbidden, and a plugin's `# why:` line records `declares no permissions (manifest checked <date>)`.
2. **Boards are generated on the device at runtime, never bundled, and every board has exactly one solution.** *(test-enforced: property tests run the real generator over many seeds for every size and difficulty and have the solver count solutions — guard: #26 (planned))*
3. **Lean dependencies.** A third-party package is added only when it is necessary, carries a one-line justification in `pubspec.yaml` as a trailing `# why: <reason>` comment on its key line, and never brings ads, analytics, or network access. *(One exemption from the justification requirement, and it is why the SDK entries carry no `# why:` line: `flutter`, `flutter_test`, `flutter_localizations` (when localisation is added) and `flutter_lints` — the SDK itself plus the lint set everyone runs. `flutter_lints` is a genuine pub.dev package, so the exemption is a real one and was in the code and nowhere in the record until #118.)* *(blocklist and justification test-enforced under invariant 1 — guard: #15 (merged); "necessary" is honor-system, checked by audits)*
4. **Deterministic generation.** The same seed, size, and difficulty always produce the same board. *(test-enforced: golden-seed regression test — guard: #26 (planned))*

## n8SDLC project

This project is managed by the n8SDLC workflow (GitHub Issues = the plan; `/n8-stat` shows where things stand). If a change made in this session deviates from what planned issues assume — different library, provider, architecture, dropped/added scope, or amending a declared invariant below — do two things before finishing:
1. Append an `## Ad-hoc` entry to `.n8/decisions.md` (format documented in that file's header) naming the change, the why, and the milestones/issues likely affected.
2. Tell the user which future milestones may now have stale plans and suggest running `/n8-replan`.

Separately: if a `/n8-*` skill's own instructions failed, misled you, or were silent on something this session, tell the user and offer `/n8-feedback` — it packages the learning as an issue on the plugin repo, stripped of project specifics, and sends nothing until the user has reviewed the exact text.
