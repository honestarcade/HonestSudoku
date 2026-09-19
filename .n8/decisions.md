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

## /n8-plan M4 — 2026-09-19

- **Decision:** Ten stories (#37–#46), no spikes, no subtasks; chain #37 → #38 → #39 → #40 → {#41, #42, #43, #44 → #45} → #46.
- **Decision:** Plugins `path_provider` and `url_launcher` adopted after manifest checks (no permissions declared; url_launcher adds only an internal activity), with `# why:` lines carrying the check date.
  **Why:** Owner approved both over hand-written platform channels.
  **Issue:** #38, #44
- **Decision:** Android automatic backup stays on; the privacy policy (M0 #16) gains a sentence saying Android's own backup may copy saved progress to the player's Google account and the studio never receives it.
  **Why:** Owner chose it so a new phone keeps stats. Amends #16 (unexecuted) via #38.
- **Decision:** Returning to the board (menu Continue, back from Rules or Settings) lands paused; a fresh generation enters playing.
  **Why:** Owner chose it; consistent with "no time counted you didn't play". Diverges from the prototype.
  **Issue:** #39
- **Decision:** A loss or an abandoned puzzle ends the streak; starting a new board while one is unfinished counts as started-not-solved.
  **Why:** Owner chose it; matches "Finished without giving up".
  **Issue:** #37, #39
- **Decision:** One `AppSettings` document (game toggles, theme, sound toggles, last setup incl. next-board strike/announce modes) with a single `updateSettings`; setup edits the next board's modes, Settings edits the running game's; a restored game's modes become the running modes and are written back.
  **Why:** The prototype shared one value between both screens; the executor simulation showed the two screens need different targets once a game can be in progress.
  **Issue:** #38, #41, #42, #39
- **Decision:** The saved game stores the puzzle's solution and givens so restore never regenerates; a finished game is deleted at launch; stats persist with the game writes, not per second.
  **Issue:** #38, #39
- **Decision:** M3's win card (#35) is amended to show the recorded streak (no `+ 1`); the win is recorded before the card mounts.
  **Why:** Avoids a double count.
  **Issue:** #37, #39
- **Decision:** Version from a build-time `HS_VERSION` define (gate and release workflow), no package-info plugin; the About screen drops the design's install-size text.
  **Issue:** #40, #42, #44
- **Decision:** Non-board screens use logical points, scroll, and honour the system text scale; a parameterised overflow test at 1.3× covers every route.
  **Issue:** #40, #46
- **Decision:** Route destinations follow the design's `goMenu`/`goBack` split (setup, stats and About the App always to the menu; settings, how-to and studio to the board when opened from the pause card, else the menu); route helpers live in one file so only they push the board or menu routes.
  **Issue:** #40, #46
- **Decision:** One second-pass simulation agent stalled for hours without reporting; it was replaced by a fresh run rather than waited on.

## /n8-plan M5 — 2026-09-19

- **Decision:** Sound plays through a ~60-line in-repo Android `SoundPool` bridge on a method channel, not a plugin.
  **Why:** `audioplayers` depends on `http`, which #15's blocklist refuses under invariant 1; `just_audio` brings a full media player and `audio_session`; `soundpool` was last published in 2023 against Kotlin 1.5 / compileSdk 31. A bridge adds no package, no permission and no transitive surface. Haptics need no plugin at all (`HapticFeedback`).
  **Issue:** #49, #55

- **Decision:** Sounds fire on placement, mistake, solve and the last strike; one per entry, by priority. In announce-at-the-end mode a wrong entry plays the ordinary click, not the thud.
  **Why:** Owner chose the four events. The thud would reveal the mistake that the at-the-end mode exists to hide.
  **Issue:** #49

- **Decision:** Sounds use `USAGE_GAME`/`CONTENT_TYPE_SONIFICATION`, so they follow media volume and mute, not the ringer switch; flipping Sound effects on plays one confirmation click.
  **Why:** Owner's calls; matches how games behave and gives immediate proof the sound works at the current volume.
  **Issue:** #49

- **Decision:** Design colours that fail the 4.5:1 contrast guideline are nudged to the nearest passing shade of the same hue, each recorded in a table; the six brand swatches are never changed.
  **Why:** Owner chose nudging over exempting. The failures are Paper pencil marks (2.9:1), Paper user digits (4.0), Paper wrong digits (4.4), the dim mono label (3.5) and the card kicker (3.7) — plus anything the guideline runs turn up, including hint-yellow marks on Paper.
  **Issue:** #52, #56

- **Decision:** Grid cells are exempt from the 48 dp tap-target guideline under a project guideline that skips nodes tagged `grid-cell`; every other control meets it, with pad and tool hit areas reaching 48 dp by inflating the pad's own box.
  **Why:** A 16×16 cell is 22 pt and cannot be 48. A `RenderBox` rejects hit tests outside its own size, so overlapping keys alone would leave the outer keys' extra area dead.
  **Issue:** #56

- **Decision:** Grid digits and pencil marks follow only the Large digits setting; the rest of the board screen follows the phone's font size up to 1.3×. The notice banner caps at three lines and the pad follows its measured height, dropping to two lines rather than covering the tools.
  **Why:** Owner's call on the banner; the grid is geometry-bound, so system scaling there would break the board.
  **Issue:** #53

- **Decision:** Screens keep M4's 150 ms cross-fade and only the win/out-of-strikes card rises; everything animated collapses to an instant change under the phone's remove-animations setting.
  **Why:** Owner's calls. The design's `hs-rise` applies to the end-of-game card alone.
  **Issue:** #50

- **Decision:** Fonts are the static Outfit and IBM Plex Mono instances, fetched from pinned commits by a script, hash-pinned and committed; Outfit becomes the app-wide theme font.
  **Why:** Invariant 1 forbids fetching fonts at runtime; pinned hashes make the download reproducible and let the guard enforce it.
  **Issue:** #47

- **Decision:** The launcher ships an adaptive icon plus an Android 13 monochrome layer; the brand sheet's light tile is not shipped. The studio's four-corner mark is verified against a committed copy of Honest Frog Across's brand SVG, which must be copied from that repo rather than retyped.
  **Why:** Android uses one icon. Honest Chess and Honest Solitaire do not exist yet, so Frog Across holds the canonical studio mark; retyping the paths from the issue would make the guard prove only internal consistency.
  **Issue:** #54

- **Decision:** Store screenshots are captured by an integration test driven with `flutter drive` on a 1080×1920 emulator, with fixed seeds, pinned status bar and statistics seeded backwards from what the capture run itself records.
  **Why:** `flutter test` cannot write screenshots. The run's own play fires `recordStart` and `recordAbandon`, so a naively seeded book photographs the wrong numbers.
  **Issue:** #57

- **Decision:** The coverage check rejected three story ownerships before filing. Map items for grid-size scaling and the palette now point at M3's #31/#36 as the deliverers, with the M5 stories named as evidence only; a twelfth item was added for the menu, About-the-App and About-Honest-Arcade marks.
  **Why:** #52's only criterion touching the swatches says they are untouched, and #57's screenshots evidence scaling without asserting it. An owner column that names a story which disclaims the work reads as covered while covering nothing.
  **Issue:** #48, #52, #57

- **Decision:** Audit emphases refreshed and still provisional (M6 and M7 unplanned). M5 adds native and asset surface — the sound bridge, bundled fonts and audio — plus the accessibility exemption, which the audit should re-test rather than trust.
  **Why:** The whole-project analysis can only be final once the highest feature milestone and every lower one are planned.
  **Issue:** M8

## /n8-plan M6 — 2026-09-19

- **Decision:** The roadmap's phase 4 — the release-candidate dry run — is executed first, not last, and M6 opens with #59.
  **Why:** An acceptance criterion that reads "the owner confirms on device" cannot be met without an installable build, and the build is what a release produces. Frog Across recorded this circularity across five rounds of device testing and resolved it the same way: cut to the internal track first.
  **Issue:** #59

- **Decision:** The candidate tag is pushed directly with `git tag`, not through `/n8-release`.
  **Why:** That command's argument grammar is `X.Y.Z` or a bump keyword with no prerelease form, and its hard stops require every included milestone to be verified-closed with no open `confirmed` bugs. M6 is neither while its own first story runs — which is the point of a dry run.
  **Issue:** #59

- **Decision:** M6's fixes land on `main` in batches rather than in one milestone pull request at the end, and each batch that needs owner re-testing becomes the next `-rc.N`.
  **Why:** Every batch has to become a build the owner can install and replay; waiting for a single merge at the end would make the repeat passes impossible. This departs from the n8SDLC branch-per-milestone convention in CLAUDE.md, so it is recorded as drift rather than assumed.
  **Issue:** #59, #64, #67

- **Decision:** The device matrix is the owner's one modern phone plus two emulators — API 24 at 720×1280 and a large modern one — and the plan states what that cannot prove.
  **Why:** Owner has one phone ("One modern phone I own", 2026-09-19). Android 7 has no hardware behind it, so the outcome says so instead of claiming a device pass.
  **Issue:** #61, #64

- **Decision:** A defect blocks the release when it crashes, breaks a rule of play, makes a control unreachable, reports wrong statistics or breaks accessibility; cosmetic drift moves to the backlog epic #10 with the owner's explicit say-so. The judgement rides on the existing `sev:*` labels, since no `blocking` label exists.
  **Why:** Owner's bar ("Anything that misleads or blocks play", 2026-09-19).
  **Issue:** #67

- **Decision:** The real sound effects are generated in M6 with the owner's ElevenLabs key on the Creator plan, auditioned through a release build on the phone, and a build carrying any placeholder becomes unshippable — the placeholder check moves before the Play upload step and step order is asserted by parsing the workflow.
  **Why:** Owner chose to generate in M6 on the Creator plan (2026-09-19). Proving the gate by pushing a scratch tag would spend the signing key and the service-account secret and risk an accidental upload, so the check is extracted to a script and the ordering asserted mechanically.
  **Issue:** #63

- **Decision:** Invariant 4 gains its first assertion on ARM: the soak recomputes #26's golden-seed fingerprints on the device and compares them with the committed host values.
  **Why:** The coverage check found that invariant 4's guard has only ever run on the development machine. A host-only determinism check cannot see a host/device divergence, which is exactly the class of defect this milestone exists to find.
  **Issue:** #65

- **Decision:** The generation timeout path is exercised deliberately with a lowered ceiling rather than hoped for, and rotation is tested as a lock rather than a feature.
  **Why:** A 16×16 Evil board that completes in time never exercises the failure path, so it would ship unrun. The app is portrait-only, so the original criterion tested a behaviour that must not exist.
  **Issue:** #61, #64

- **Decision:** Device stories install with `bundletool` through `tools/install_build.sh`, not `adb install`.
  **Why:** The second coverage run caught that `adb install` cannot take an AAB, which every device story depended on.
  **Issue:** #61

- **Decision:** Audit emphases refreshed, still provisional (M7 unplanned). M6 adds device-only suites that CI never runs, a hard audio gate and the first ARM determinism check — all things a later audit should re-test rather than trust.
  **Why:** The analysis is final only once the highest feature milestone and every lower one are planned.
  **Issue:** M8

## /n8-plan M7 — 2026-09-19

- **Decision:** The store listing and every App content declaration are completed before the closed test, not alongside it.
  **Why:** Play refuses a completed release outside the internal track while an app is still a draft. Frog Across discovered this only when its own promotion came back as a draft release. Item 17 therefore blocks item 19.
  **Issue:** #71, #72

- **Decision:** The act that takes the app out of draft — publishing the closed-testing release — belongs to #72, and #71 only clears the obstacles to it.
  **Why:** The coverage check found the act orphaned: each of the two stories named the other as the publisher, which is the same failure the milestone exists to avoid. The second check found the corrected criterion still contradicted by that story's title, summary, stated truth, artifact line and discretion; all five were rewritten.
  **Issue:** #71, #72

- **Decision:** Countries and regions are set explicitly, once for the closed-testing track and once for production.
  **Why:** The plan had no item for them at all. A tester outside the selected set cannot install and looks exactly like one who never opted in; a 100% rollout to no countries is live nowhere.
  **Issue:** #72, #74

- **Decision:** The closed test starts at the beginning of M7 rather than running in parallel with M6, and recruiting starts on the milestone's first day with a target of fifteen.
  **Why:** Owner's calls ("At the start of M7", "None yet", 2026-09-19). The fourteen days are therefore added to the schedule rather than absorbed into it. Fifteen because Play restarts the count on a dip below twelve.
  **Issue:** #70, #73

- **Decision:** The fourteen-day log records joiners and leavers, not only a daily headcount, and the Console's own qualification indicator closes the criterion.
  **Why:** Play counts per tester — twelve people each need fourteen consecutive days — so a roster that churns can show twelve every single day while nobody accumulates fourteen.
  **Issue:** #73

- **Decision:** The owner performs every Play Console action personally; the agent prepares an entry sheet for each page and never drives the Console. GitHub is the agent's: tags, workflows, releases and records.
  **Why:** Owner's call ("You do it; I prepare everything", 2026-09-19). Browser control was available and deliberately not used: the Console is the owner's Google account, and a form submitted before they read it is not a form they agreed to.
  **Issue:** #68, #69, #70, #71, #72, #73, #74

- **Decision:** A blocking defect found during the hold ships as v1.0.1 to the testers, with its own release notes and GitHub release; the fourteen days do not restart and the production rollout promotes the newer code.
  **Why:** Owner's call ("Ship 1.0.1 to the testers", 2026-09-19). Play counts testers opted in to the track, not to a version. The launch record is written against the version actually released, not the one first planned.
  **Issue:** #73, #74, #75

- **Decision:** On release day the promote workflow is dispatched once at production, expecting refusal, and the run URL is quoted.
  **Why:** M1 proved the service account cannot reach production; this proves it has not drifted on the one day it matters. A permission granted in the meantime would silently widen what CI can do.
  **Issue:** #74

- **Decision:** Audit emphases are now final rather than provisional, since M7 is the highest feature milestone and every lower one is planned.
  **Why:** The analysis can only be final once nothing below it can still change. Added since the last revision: store-truth (does the listing still describe the build?) and a check that the service account still cannot reach production.
  **Issue:** M8

- **Decision:** Two project skills approved for building: a Play Console launch runbook and a Sudoku techniques reference. An owner-task tracking issue (#76) lists all eleven owner actions in plan order.
  **Why:** Owner's calls (2026-09-19). The runbook pays off on the studio's third app; the techniques reference is read by both the engine's grading and the difficulty tuning. The tracker exists because three owner tasks gate long waits and the label alone does not show what is coming.
  **Issue:** #76

## Ad-hoc — 2026-09-19

- **Change:** Both project skills approved during `/n8-plan M7` — the Play Console launch runbook and the Sudoku techniques reference — were **not built**. The suggestions are recorded on #9 and #25 instead, with what each should encode.
  **Why:** `/n8-skill`'s own rule: a skill is grounded in real paths and symbols at HEAD, and where that code does not exist yet the suggestion is noted and the skill built after the milestone verifies. Today `lib/` holds only the Flutter scaffold's `main.dart`, there is no `.github/workflows/`, no `tools/`, and no `.n8/memory/play-console.md`. The cold-test gate is also unrunnable without an artefact to prove against. Building either now would produce a document describing how such things usually work rather than how this project's actually do — the failure the rule exists to prevent.
  **Affects:** nothing in the plan is stale; these are additions to make after M2 (#25) and M7 (#9) verify.

## /n8-exec M0 — 2026-09-19

- **Decision:** Merged PR #11 (the planning state) before starting, as the run's first act.
  **Why:** `main` carried the init commit only. The four project invariants were not in CLAUDE.md, and `.n8/config.yml` still listed all six platforms with no `android.application_id`. #12 implements that id and #14/#15 are guard stories for invariants that were not written down on the branch they would have been built from. Executing M0 off that `main` would have meant implementing stories whose own configuration answers did not exist in the tree.
  **Issue:** precondition for all of M0

- **Decision:** `minSdk = 24` pinned literally in `android/app/build.gradle.kts` rather than inherited from `flutter.minSdkVersion`, with an inline comment pointing here.
  **Why:** #12's acceptance criterion. The value happens to equal Flutter 3.47's default today, so inheriting would look identical and silently move when Flutter raises its floor. Pinning records the choice: Android 7.0 and newer, which is every device that can install from Play.
  **Issue:** #12

- **Decision (Rule 1 — own bug):** The identity guard's "old id absent" walk decoded every tracked file under `android/` as UTF-8 and crashed on the launcher PNGs. Changed to decode bytes as latin1.
  **Why:** The walk must cover binaries — an id string can appear in one — and latin1 never throws while still matching an ASCII id byte for byte. Caught by running the guard, not by reading it.
  **Issue:** #12

- **Decision (Rule 3 — blocker):** Pointed Flutter at Homebrew's `/opt/homebrew/opt/openjdk@21` with `flutter config --jdk-dir`.
  **Why:** `/usr/bin/java` on this machine is the macOS stub that reports "Unable to locate a Java Runtime", so Gradle had no JDK. The planned toolchain note named this exact remedy. No shell rc file was edited; the setting lives in Flutter's own config.
  **Issue:** #12

- **Decision:** Rewrote `pubspec.yaml` rather than editing it in place, keeping a two-line header.
  **Why:** #12's discretion asks for every scaffold comment block removed, and those blocks are most of the file — the scaffold's iOS, Windows and web versioning notes, the asset and font examples. Rewriting is legible; a dozen deletions are not.
  **Issue:** #12

- **Decision (deviation from an acceptance criterion):** #14's bundle scan was specified as "exit 1 if any run contains `android.permission.`". That rule can never pass on any Flutter release build, so it is not the rule that shipped. `tools/check_aab.sh` allowlists exactly one string, `android.permission.DUMP`, and says so loudly on every clean run.
  **Why:** `android.permission.X` appears in a manifest for two opposite reasons. `<uses-permission android:name="...">` **requests** a capability — what invariant 1 forbids. `android:permission="..."` on a component **restricts** who may reach it — a lock, not a key, granting the app nothing. Every Flutter release build carries the second kind, from androidx.profileinstaller's `ProfileInstallReceiver`. Verified against Gradle's merged release manifest: the release build has **zero** `<uses-permission>` of any `android.permission.*`, no INTERNET, and one `android:permission="android.permission.DUMP"` attribute. A byte scan cannot see that difference, so the allowlist encodes it. Anything else, including a new restriction, still fails.
  **Issue:** #14

- **For the owner to confirm:** the release build also declares a signature-level permission on **itself**, `com.honestarcade.sudoku.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`, added automatically by androidx.core so dynamically-registered receivers are not world-readable. It is granted only to this app's own signature, is not an `android.permission.*`, and Play does not show custom signature permissions to users — so the "NO PERMISSIONS" promise on the About screen still holds. But invariant 1 literally says "no Android permissions at all", and this is a permission element in the shipped manifest. Removing it is not possible without dropping androidx, which means dropping Flutter. Recorded here and raised on #14 rather than decided silently.
  **Issue:** #14

- **Decision (Rule 1 — own bug):** `tools/check_aab.sh` used `grep -q` in two places and returned **different answers for identical runs**.
  **Why:** `grep -q` exits at the first match, closing the pipe under `unzip`, which dies of SIGPIPE; `set -o pipefail` then makes that the pipeline's exit status. On a 44 MB bundle it is a race, so the manifest-entry check passed or failed at random — caught only because I ran the same command twice and got different results. Both are `grep -c` now, which reads to the end. Verified stable over six consecutive runs per exit path.
  **Issue:** #14
