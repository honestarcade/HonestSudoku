# Decision log

Append-only. One `##` section per skill run (or per ad-hoc change), entries in chronological order.
Record real decisions (choices between alternatives, assumptions, deviations from plan), not routine actions.

Entry format:

```markdown
## /n8-exec M1 — 2026-09-18

- **Decision:** What was chosen.
  **Why:** The reasoning and the alternatives passed over.
  **Issue:** #14
```

Ad-hoc entries (changes made outside the n8SDLC commands that deviate from planned issues):

```markdown
## Ad-hoc — 2026-09-18

- **Change:** What changed.
  **Why:** The reasoning.
  **Affects:** Milestones/issues whose plans may now be stale.
```

`/n8-replan` appends `— reconciled by /n8-replan <date>` to ad-hoc entries once processed.

## /n8-init — 2026-09-18

- **Decision:** Kept the fresh `flutter create` scaffold with all six platforms (android, ios, web, macos, linux, windows).
  **Why:** No user preference was given; trimming is cheap later and the CI matrix is decided during roadmap.
- **Decision:** Security findings from audits are filed as public issues (`security_findings: issues`).
  **Why:** Public repo, client-side game with no deployed service; open findings help players assess risk and integrate with milestone tracking.
- **Decision:** Area labels: `area:app`, `area:platform`, `area:ci`, `area:docs`.
  **Why:** Mirrors the actual directories (lib/+test/, native shells, .github/, docs). Can be split further (e.g. engine vs ui) once lib/ has structure.
- **Decision:** Overwrote the description of GitHub's default `documentation` label to the n8SDLC wording; left the other default labels (enhancement, duplicate, invalid, wontfix, good first issue, accessibility) untouched.
  **Why:** Repo had no issues yet, so nothing curated was lost; n8SDLC never deletes labels it did not create.

## /n8-roadmap — 2026-09-18

- **Decision:** v1 targets Android only, portrait; iOS and web deferred to the post-v1 backlog epic.
  **Why:** The design is a portrait phone app and the studio's Play Console path already exists from Frog Across; owner chose Android-first when asked.
  **Issue:** #10
- **Decision:** Fully automated release: `v*` tag → signed AAB → Google Play internal track via CI; production promoted from a closed test.
  **Why:** Same shape as Frog Across; owner chose it over release-artifact-only.
  **Issue:** #8, #9
- **Decision:** Puzzle difficulty is solver-graded by hardest technique, with a unique-solution guarantee, instead of the prototype's givens-ratio carving.
  **Why:** The design's difficulty descriptions name techniques (singles, pairs, chains); ratio carving cannot honour them and may produce multi-solution boards. Owner chose this.
  **Issue:** #1
- **Decision:** Android application id `com.honestarcade.sudoku`.
  **Why:** Owner's call; replaces the scaffold's `com.honestarcade.sudoku.honest_sudoku`. Immutable after the first Play upload, so set in M0.
  **Issue:** #7
- **Decision:** Four invariants recorded in CLAUDE.md: no ads/tracking/network; boards generated on device with exactly one solution; lean dependencies; deterministic generation. An earlier "engine is pure Dart, no plugins" candidate was demoted to an import-guard AC on the engine epic at the owner's request.
  **Why:** Owner wants Flutter and necessary plugins available and only objects to bloat; the pure-Dart engine is a convention for testability, not a product rule.
  **Issue:** #1, #7
- **Decision:** A dedicated M6 "Testing and bug fixing" milestone precedes launch.
  **Why:** Owner asked for it; device testing across the size/difficulty/mode matrix is substantial and should not hide inside the launch milestone.
- **Decision:** Coverage claim "Implement: `Honest Sudoku.dc.html`" recorded against the design file; blocks on epics #1–#5 and milestones M2–M5. The design's own "next" list (daily calendar, enter-a-puzzle, Killer/Jigsaw) is outside the claim.
  **Why:** The owner named the design as the specification; the surface is enumerable (nine screens plus the constants tables).
- **Decision:** Audio assets are owner-supplied; the sound system is built against placeholders.
  **Why:** Same as Frog Across; no audio exists in the design project.
  **Issue:** #5
- **Deferred to planning:** state-management and local-storage package choices (under the lean-dependency invariant), minSdk, generation performance fallback for 16×16 Evil, whether OS app backup should include puzzle data.

## /n8-plan M0 — 2026-09-18

- **Decision:** Six stories (#12–#17), no spikes, no subtasks; chain #12 → {#13, #14, #15, #16} → #17.
  **Why:** Every story is one session and its "how" is settled by the discretion lines; nothing needed a prototype.
- **Decision:** Zero Android permissions in the release build, not merely no INTERNET; invariant 1 reworded accordingly.
  **Why:** Owner chose it; matches the design's "NO PERMISSIONS" promise. Guard: #14 (manifests + bundle scan).
- **Decision:** Plugins are adopted only during planning, after the planner reads the plugin's manifest and the owner approves; build-time permission removal rules are forbidden.
  **Why:** Owner: "Ask me. This should be done during planning. Determine any plugins needed during planning and check the manifest."
  **Issue:** #14, #15
- **Decision:** iOS, macOS, Linux, Windows and web platform folders are deleted from the repo.
  **Why:** Owner chose it; regenerable with `flutter create --platforms`.
  **Issue:** #12
- **Decision:** minSdk pinned at 24 (Flutter 3.47 default).
  **Why:** No owner floor given; covers Android 7.0+; one-line change later.
  **Issue:** #12
- **Decision:** Upload keystore is PKCS12 with a single password; both `HS_KEYSTORE_PASS` and `HS_KEY_PASS` are kept for Gradle and hold the same value.
  **Why:** Modern keytool ignores a distinct key password for PKCS12; pretending otherwise would confuse the runbook.
  **Issue:** #13
- **Decision:** GitHub Pages is enabled as a post-merge step of the milestone.
  **Why:** The Pages API needs `docs/` on `main`; enabling on the branch 404s.
  **Issue:** #16
- **Decision:** Guards for invariants 2 and 4 deferred to M2 (`guard: deferred → M2`); guards for invariants 1 and 3 planned as #14 and #15.
  **Why:** The engine does not exist before M2, so those guards cannot fail on a real breach yet.
- **Decision:** Toolchain facts recorded for execution: no Android Studio, no JDK on PATH (use Homebrew openjdk@21 via `flutter config --jdk-dir`), cmdline-tools missing, no device or AVD (executor creates one).
  **Why:** Discovered by the executor simulation; would otherwise be the first blocker of `/n8-exec M0`.
  **Issue:** #12

## /n8-plan M1 — 2026-09-18

- **Decision:** Four stories (#18–#21), no spikes, no subtasks; chain {#18, #19} → #20 → #21.
- **Decision:** The Play Console app entry and its service account move from the Launch epic (#9, M7) into M1 (#19), so the tag-to-Play path is proven with a real tag; App Signing enrols at the first upload (#20). #19 edits epic #9 and M7's phase 1 when it lands.
  **Why:** Owner chose it; without it M1's upload step is unverifiable until M7. Frog Across did the same.
- **Decision:** Production is a human act in the Play Console; the service account is granted testing-track release only and the promote workflow refuses `production` (#21 also amends epic #8's "or production" wording).
  **Why:** Owner chose it, matching Frog Across.
- **Decision:** Pushing a `v*` tag is the stage approval; no GitHub Environment reviewer step.
  **Why:** Owner chose it; tags are cut by `/n8-release` from verified `main`.
- **Decision:** The executor scripts the Google Cloud setup (project `honestsudoku-ci`, service account, key → GitHub secret) with the owner's local gcloud login; the owner does the Console clicks.
  **Why:** Owner chose it.
- **Decision:** Flutter version pinned in `.fvmrc`, read by `subosito/flutter-action` and by `tools/gate.sh` (warn only); `pubspec.yaml` keeps a range.
  **Why:** The executor simulation found an exact pin in pubspec makes `flutter pub get` refuse other versions, defeating the warn-only intent.
- **Decision:** Version code = 1000 + run_number × 10 + run_attempt (attempt 1–9); version name from the tag.
  **Why:** A plain run-number scheme repeats the code on a re-run after a transient failure and Play rejects it.
- **Decision:** #20, #21 and #19 verify after the milestone PR merges (a release tag must point at `main`) and close through the post-merge state check; the milestone PR closes #18 only.
  **Why:** Structural; the coverage check flagged the contradiction with "PR closes all stories".
- **Decision:** Action majors resolved 2026-09-18: checkout v7, setup-java v6, flutter-action v2, upload-artifact v7, upload-google-play v1, action-shellcheck 2.0.0; Dependabot carries them forward.

## /n8-plan M2 — 2026-09-18

- **Decision:** Six stories (#22–#27), no spikes, no subtasks; chain #22 → {#23, #24}; #23 → #25 → #26 → #27.
- **Decision:** Unsupported size/difficulty pairs (4×4 Expert and Evil, 6×6 Evil) are refused by the engine and greyed out in setup, matching the design's statistics breakdown.
  **Why:** Owner chose "Unavailable"; small grids cannot honestly require those techniques.
  **Issue:** #25
- **Decision:** 16×16 waits for the real board, up to a 15-second ceiling, then fails with a clear message; no relabelled fallback.
  **Why:** Owner chose it over capping at five seconds.
  **Issue:** #27
- **Decision:** Within a band, boards aim at the design's givens counts (keep ratios 0.55/0.46/0.38/0.31/0.25, floor n + n/2) while the solver proves the label; Evil takes whatever count uniqueness allows.
  **Why:** Owner chose "match the design's counts" so the setup screen can show the count before generation.
  **Issue:** #25
- **Decision:** Technique ladder and bands: singles → Easy; locked candidates → Medium; pairs → Hard; triples and X-wing → Expert; anything beyond → Evil. Documented on the `Engine` wiki page.
  **Issue:** #25
- **Decision:** Guards for invariants 2 and 4 are #26; the PR gate samples seeds 200/200/40/5 by shape (16×16 Evil weekly only) and a weekly run covers 200 seeds for every pair. Epic #1's "200 seeds per pair in CI" criterion is amended accordingly by #25.
  **Why:** The full set cannot fit the three-minute guard budget; the executor simulation and coverage check closed the arithmetic.
- **Decision:** Golden fixtures hash with FNV-1a (no new package); the full-grid construction is pinned to the design's JavaScript output for seed 20260824.
  **Why:** SHA-256 would add a dependency (invariant 3); the pinned board catches any drift in shuffle nesting.
  **Issue:** #23
- **Decision:** `package:meta` is allowed inside the engine (ships with the SDK) for `@visibleForTesting`.
  **Issue:** #22, #27
- **Decision:** The engine is pure Dart under `lib/engine/` with an import guard; the game-state model (place, undo, strikes) is M3's first story, built on this engine.

## /n8-plan M3 — 2026-09-18

- **Decision:** Nine stories (#28–#36), no spikes, no subtasks; chain #28 → #29 → #30; #31 after #29; #32, #33, #34, #35 after #31; #36 last.
- **Decision:** The board layout scales with screen width (cap 430/390), top-aligned inside a safe area.
  **Why:** Owner chose it over fixed pixel sizes.
  **Issue:** #36
- **Decision:** Android back on the board pauses; back while paused goes to the main menu; backgrounding auto-pauses and the game stays paused on return.
  **Why:** Owner chose both.
  **Issue:** #36
- **Decision:** The strike counter counts a wrong entry immediately even in announce-at-end mode (as the prototype); pencil marks use a fixed slot per value (unlike the prototype's packed order).
  **Why:** Owner's calls.
  **Issue:** #34, #31
- **Decision:** Divergences from the prototype recorded for verification: redo recomputes won/lost; check and hint idle when the game is over or paused; a pencil-mark toggle on a filled cell is a no-op; the hinted cell's yellow clears on any selection or notice change; lowering the strike limit mid-game loses only on the next wrong entry; both overlays hide the board; Zen's grid-full message drops "the ones in red"; hover borders become a press dip.
  **Why:** Each closes a hole or a self-contradiction the prototype leaves; all are listed in the milestone's REFINED lines.
- **Decision:** No state-management package. The game model is pure Dart under `lib/game/` with its own imports guard; a `ChangeNotifier` controller under `lib/ui/board/` owns state, clock and lifecycle.
  **Why:** Invariant 3; the model stays unit-testable without Flutter.
  **Issue:** #28, #36
- **Decision:** Board text ignores the system text scale in M3; M5's accessibility story revisits font scaling with the large-digits setting.
- **Decision:** No `TODO` comments in code: the gate runs `dart analyze --fatal-infos` and `todo` is an info. Temporary code is marked with a plain `// M4 replaces …` comment.
  **Why:** Found by the executor simulation; a TODO would have failed the gate.
- **Decision:** M3 launches straight into a 9×9 Medium board with a plain loading placeholder and placeholder routes; M4 replaces them with the designed screens.
