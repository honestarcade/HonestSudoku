# Decision log

> **What this file is.** A dated, append-only narrative: what was decided, when,
> and why. **Its numbers are as of writing and are not maintained** — counts of
> tests, mutations, timings and issue tallies were corrected in five successive
> passes and went wrong again each time, so they are now read as a record of
> what was believed on that date rather than as current fact. Anything current
> comes from the command: `flutter test --no-pub --tags guard`,
> `python3 tools/mutation_check.py --list`, `gh issue list`. Corrections to an
> earlier entry are written into it in place and marked with the pass that made
> them; entries are not rewritten otherwise.

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
  **Why:** Owner's calls ("At the start of M7", "None yet", 2026-09-19). The fourteen days are therefore added to the schedule rather than absorbed into it. Fifteen because a dip below twelve is treated as restarting the count — the stricter reading, which holds either way; how Play actually counts is unresolved (#148, #164).
  **Issue:** #70, #73

- **Decision:** The fourteen-day log records joiners and leavers, not only a daily headcount, and the Console's own qualification indicator closes the criterion.
  **Why:** a roster that churns can show twelve every single day while nobody accumulates fourteen — *if* Play counts per tester, which is the unresolved question recorded in `.n8/memory/play-console.md` and amended into #70 and #73 on 2026-09-19 (#148, #164). Logging joiners and leavers is the right call under either reading, so the decision stands; the sentence above previously presupposed the per-tester one.
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

## Ad-hoc — 2026-09-19 — reconciled by /n8-replan 2026-09-23

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

- **Decision:** #15's three rules are pure functions over strings in `test/guards/dependency_rules.dart`, and every failure case the test plan asks to synthesize is *also* a permanent unit test with inline fixture text.
  **Why:** The plan's synthesized failures are one-off edits an executor makes, watches fail, and reverts. Nothing then re-proves them. As fixtures they run on every build, so the rules keep demonstrating they can fire rather than only having fired once. Both were done: the fixtures, and the live synthesis against the real pubspec.
  **Issue:** #15

- **Decision (Rule 1 — own bug, found by testing):** The source rule walked `git ls-files lib`, so an **uncommitted** `.dart` file under `lib/` was invisible to it. It walks the filesystem now.
  **Why:** Caught by the live synthesis: two throwaway files containing `fonts.googleapis.com` and `HttpClient()` produced no offenders because they were untracked. The tracked-files approach was borrowed from #12's identity guard, where it is right — `android/` holds build residue and a wrapper jar. `lib/` holds none, so there is nothing to skip and everything to catch. A guard that only sees committed code cannot fail a developer before they commit, which is when it is most useful.
  **Issue:** #15

- **Decision:** `lib/links.dart` is the single file permitted to contain a URL, enforced by a grammar test (comments, `library;` and single-line `const String` declarations only).
  **Why:** #15's criterion. It also makes the source rule's `https://` ban enforceable without exceptions scattered through the codebase — there is exactly one exception and a test that says what may be in it.
  **Issue:** #15

- **Decision:** The privacy policy's effective date is written as 2026-09-19 and will be re-checked against the milestone pull request's actual open date before the PR is opened.
  **Why:** #16's criterion defines the date as "the date the M0 PR is opened", which had not happened when the file was written. A date that is merely plausible is worse than none in a document a regulator or a store reviewer may read, so it is pinned to a real event rather than left as the day the file happened to be created.
  **Issue:** #16

- **Decision:** The docs guard asserts the package id agrees across **three** places — `build.gradle.kts`, `.n8/config.yml` and the policy — rather than the two the criterion names.
  **Why:** The criterion asks that the policy match the build and that the build match the config. Checking both in one guard means the three can never drift pairwise into agreement while disagreeing overall. The policy is the one that matters: a wrong id there is a public document describing a different app.
  **Issue:** #16

- **Decision:** The README's audio paragraph is written in the future tense ("when licensed sound effects ship") and says the synthesised placeholders are MIT-covered.
  **Why:** #16's criterion describes the carve-out, but no audio exists yet and M5 #49 ships placeholders before M6 #63 replaces them. Claiming a licence carve-out over files that do not exist would be false today; M6 #63 rewrites this paragraph in the present tense when the real clips land, which that story's criteria already require.
  **Issue:** #16

- **Decision:** `build.gradle.kts` prints the debug-fallback warning with **both** `logger.warn` and `println`.
  **Why:** #13 specifies `logger.warn(...)` and that is implemented verbatim, but `flutter build` filters Gradle's warn-level output at default verbosity — the line only appeared under `-v`. A warning nobody sees cannot tell a developer their release build is debug-signed, which is the entire reason the criterion asks for one.
  **Issue:** #13

- **Decision:** A partly-set signing environment fails configuration in **every** mode, not only under `HS_RELEASE=1`.
  **Why:** #13's criterion asks for this ("with the variables only partly set in any mode"), and the reason is worth recording: a half-set environment is almost always a typo in a variable name, and falling back to debug signing would hide it until an unsigned bundle reached the Console.
  **Issue:** #13

- **Decision (Rule 1 — own bug):** The credentials file's first line was prose, so `source`-ing it errored, despite the file being documented as an env template. It is a comment now, in the script and in the already-generated file.
  **Why:** Found by using it rather than reading it — sourcing the file to run the signed build printed `command not found: Honest`.
  **Issue:** #13

- **Decision (Rule 3 — blocker):** `.gitignore` gains `/android/build/`.
  **Why:** Gradle writes a reports directory there, and the existing `/build/` pattern is anchored to the repository root, so it was about to be committed. Caught by reading `git status` before committing rather than trusting it.
  **Issue:** #13

- **Note:** the upload keystore was generated with a 40-character random password. The value was never printed, never passed as an argument, and was verified absent from both the tracked files and the working tree by searching for the literal. It exists only in `~/HonestArcadeApps/secrets/sudoku-signing-credentials.txt` (chmod 600), which the owner must move into a password manager and delete.
  **Issue:** #13

- **Decision (Rule 1 — own bug, and the worst one of the run):** `tools/gate.sh` printed `GATE FAILED` and **exited 0**. CI would have read that as a pass.
  **Why:** The runner used `if ! eval "$command"; then status=$?; …`. Inside that branch `$?` is the status of the *negation*, which is always 0, so every failing step exited cleanly. The status is captured before any test now (`status=0; eval "$command" || status=$?`). Caught only because the demo run's `rc` was read rather than its message — the message said the right thing while the exit code said the opposite, which is exactly the false success the whole capture-and-assert discipline exists for.
  **Issue:** #17

- **Decision:** `analysis_options.yaml`'s TODO comment was reworded rather than left as the scaffold had it.
  **Why:** It said TODOs "never block a build", which stopped being true the moment the gate ran `--fatal-infos`. A comment that contradicts the build is worse than none, because it is the thing a contributor reads first.
  **Issue:** #17

- **Note:** `flutter pub get --enforce-lockfile` was verified to actually fail on a real mismatch (downgrading `flutter_lints` in the pubspec → exit 65), rather than assumed. A lockfile check that silently passes is a lockfile check nobody has.
  **Issue:** #17

- **Post-merge (M0):** GitHub Pages enabled by the API — the manual click was not needed. `https://honestarcade.github.io/HonestSudoku/privacy` returns 200 with the policy text, the package id and the effective date; the site root returns 200. Repository `homepage` and `description` set. `.n8/memory/pages.md` corrected from "intended method" to what actually happened.
  **Issue:** #16

## /n8-exec M0 (fix pass) — 2026-09-19

Scoped to the six bugs `/n8-verify M0` filed (#79–#84), on `milestone/m0-fixes`.

- **Decision (Rule 1 — own bug, found twice):** `tools/check_aab.sh` now decodes each `uses-permission` element from the protobuf manifest instead of pattern-matching names across the whole file.
  **Why:** The first version matched `uses-permission` as a whole printable run, and the encoding packs the next field's tag onto the element name, so the run reads `uses-permission"y` and the check never fired — a bundle requesting `com.evilads.sdk.TRACK_USER` exited 0 (#80). The obvious replacement, matching the run start and then hunting the manifest for dotted permission-shaped tokens, failed the real release bundle with fourteen imaginary permissions drawn from intent actions and framework class names. A scan that cries wolf on a clean build gets switched off, so it is no better than blind. The structure is regular — element, namespace, attribute name, length-prefixed value — so the name is simply the run after the one that is exactly `name`. Alternative considered and rejected: `aapt2`, which cannot read an `.aab` directly, and `bundletool`, which is a jar download and a new third party inside the guard.
  **Issue:** #80

- **Decision:** An element whose permission name cannot be decoded is a failure, not a pass.
  **Why:** Fail closed. A request nobody can name is still a request, and an encoding this decoder has not seen must never read as "clean". It also means the verdict never depends on the decode succeeding — only the wording of the message does, which is why the 128-character varint limitation is acceptable and documented rather than solved.
  **Issue:** #80

- **Decision:** Synthetic bundles became a permanent fixture suite (`test/guards/bundle_scan_test.dart`), including a realistic clean bundle that must pass.
  **Why:** Both bugs above lived in the same blind spot: the scanner had only ever been run against real bundles, and a real bundle is clean, so every run agreed with every other run and nobody learned anything. The clean fixture is as important as the dirty ones — it is what would have caught the second bug in a second. Because the fixtures model the encoding rather than being `aapt2` output, a further test pins the model to reality whenever a real bundle exists on disk.
  **Issue:** #80

- **Decision:** `tools/gate.sh` gains a `--signing-mode` flag that reports and exits.
  **Why:** The wrong message shipped because the branch was unreachable by anything but a human watching a real run, and a real run has either all four variables or none — so the case that was wrong was the only case nobody ever saw. A branch nobody can call is a branch nobody can assert. Ten assertions now drive every branch.
  **Issue:** #82

- **Decision:** The `#13` complement is tested by running a real release build, not by inspecting the build file.
  **Why:** It costs two seconds, because the `GradleException` is raised at Gradle configuration time and nothing compiles. Two cases, not one: build.gradle.kts has two separate refusals, and the first draft of the test could not tell them apart — it unset one of four variables, which trips the *partial* check, so the `HS_RELEASE` check was never reached and the test passed against a build file with that check deleted. Caught by mutating the build file rather than trusting a green run.
  **Issue:** #83

- **Decision:** The docs rules moved into `test/guards/docs_rules.dart` as pure functions over strings.
  **Why:** The guard held presence and equality assertions only, so verification had to copy the tree and mutate it four ways by hand to learn whether it worked. Writing the fixtures immediately found a real bug in a new rule: the policy is hard-wrapped, so "requests no permissions at all" is split across two lines and a literal match on it finds nothing. A rule that silently misses the sentence it exists to protect is the failure this whole pass is about, and it surfaced only because a fixture demanded the rule fire.
  **Issue:** #83

- **Decision:** The `## Android SDK` section of `.n8/memory/android-toolchain.md` was rewritten too, though #81 only named `## No device`.
  **Why:** It was stale in the same way and for the same reason — written partway through #12 and never revisited. Correcting one section and leaving the other would leave the file half-wrong, which is worse than uniformly stale: a reader cannot tell which half to trust. `.n8/decisions.md` keeps its planning-time line about no AVD existing, because that ledger records what was decided when.
  **Issue:** #81

- **Decision (housekeeping the previous run owed):** M0's coverage map was rewritten to resolve every item to an issue number, and CLAUDE.md's invariant 1 and 3 annotations to `(merged)`.
  **Why:** The map still read `→ S1, S2` — planning labels that mean nothing to a later reader, which defeats the point of a map whose purpose is to let someone check the claim rather than trust it. Both were listed as housekeeping in M0's own plan and neither was done. Noted on PR #77 by verification.
  **Issue:** #84

- **Note (own process error, already reported on PR #77):** during `/n8-verify M0` six verifier subagents were pointed at one shared worktree and several were told to mutate it. They collided, and three reported transient red runs caused by each other's fixtures. Both blocking findings were re-confirmed by hand in fresh worktrees before being filed. Recorded here so the next verification gives each agent its own worktree.
  **Issue:** #83

## /n8-exec M0 (second fix pass) — 2026-09-19

Scoped to the nine bugs `/n8-verify M0` filed against `74e1f629` (#86–#94), on `milestone/m0-fixes-2`.

- **Decision (the one that matters):** every rule in this pass now **fails closed on a shape it cannot read**, rather than learning one more spelling.
  **Why:** #79, #82, #83 and #80 were all the same bug wearing different clothes, and each fix closed the instances it was shown. The dependency rule had been fixed three times and still had five legal bypasses. The gate's blank check reasoned its way to `isNullOrBlank` in a comment and then asserted only the empty string. The bundle scan learned to decode requests and forgot declarations. "I cannot read this" must never render as "there is nothing here" — so a dependency section that is not a plain block is refused, an undecodable permission element is an offender, and a whitespace variable is unset.
  **Issue:** #86, #91, #87

- **Decision:** the blocklist was extended beyond what #15's acceptance criteria enumerated, without treating it as a blocker.
  **Why:** #94's own text called this an owner decision, and on reflection it is not one. Extending a blocklist makes an existing guard stricter in the direction invariant 1 already points; it cannot forbid anything invariant 1 permitted. Twenty-three names and six new globs, including `webview_flutter`, which embeds a whole browser. What it does amend is the specific list #15 enumerated, which is why this entry exists. A seventeen-package allow list is asserted beside it: a broad glob like `*webview*` is how a blocklist starts refusing ordinary packages, and a guard that cries wolf gets deleted.
  **Issue:** #94, amends #15

- **Decision:** #92's pinning test builds the bundle it needs instead of the gate reordering its steps.
  **Why:** moving the build ahead of the tests would make every failing unit test wait on a full release build, and it would change the step order that the README and CLAUDE.md both publish as "the order CI will run it". Having the test build on demand keeps that order and makes the dependency explicit rather than incidental. The cost is a slower first run on a clean checkout, which is exactly the run that was proving nothing before.
  **Issue:** #92

- **Decision (Rule 1 — own bug, found while writing the fix):** the bundle scanner's permission elements had no end.
  **Why:** the sixteen-run window ran on into following elements, so a later `name` attribute overwrote the permission's, and the clean fixture was reported as requesting `android.intent.action.MAIN`. Elements now end at the next element name, checked *after* the value assignment so a value that looks like an element name — `signature"` is exactly that — is still read first. Caught only because the clean-bundle complement fixture exists; the dirty fixtures all still passed.
  **Issue:** #87

- **Note (own overclaim, corrected):** two commit messages in this pass asserted numbers that were wrong — a test count off by one, and "7 of 12 fixtures fail" where the true figure was 3. Both were amended rather than left, and the second now records *why* it is 3: two of the names are new entries that match under the old boundary too, so only the three whose capture depends on the change fail without it. This is the same class of defect as #88, where the previous pass claimed every memory-file claim had been re-checked.
  **Issue:** #90

- **Note:** `make_upload_key.sh` now exits 2 for an existing keystore where it previously exited 1. The planner's discretion specified 2 for either output; the original code disagreed with the plan and nothing tested it.
  **Issue:** #93

- **Decision (correction, same run):** #92's guarantee moved from the test into `tools/check_aab.sh`, reversing the approach I had committed an hour earlier.
  **Why:** having the test build its own bundle raced. `flutter test` runs files concurrently, and `signing_guard_test.dart` asserts a refused build leaves the bundle untouched, so the build started by `bundle_scan_test.dart` changed the file under it and the gate went red. Two tests fighting over one artefact is worse than the problem being solved. Reordering the gate would fix the race but makes every failing unit test wait on a release build and changes the step order the README and CLAUDE.md publish. The scanner now refuses a bundle that is recognisably a Flutter app yet yields no permission element at all — the signature of an inert decoder, which is what #80 was — and that runs against the real artefact at step 6 of every gate run. Found only by running the gate from an empty `build/` directory; both earlier runs had a bundle already on disk and passed.
  **Issue:** #92

## /n8-exec M0 (third fix pass) — 2026-09-19

Scoped to the thirteen bugs the third `/n8-verify M0` filed against `a6494a7` (#96–#108), on `milestone/m0-fixes-3`. I had reported that a fourth round on this surface was likely worth less than M1's CI; the owner re-ran `/n8-exec M0`, so that is their call and all thirteen were fixed.

- **Decision (the structural one):** where two pieces of code decide the same thing, one of them stops deciding.
  **Why:** `tools/gate.sh` and `build.gradle.kts` both answered "is this variable set", and drifted apart twice — once on ASCII whitespace (#91), once on 0x1C and U+3000 (#106), each time with the gate announcing the upload key over a debug-signed bundle. Narrowing `tr` a third time would have been wrong for the next character class. So Gradle now states which key it used in both branches, and the gate reads that back and **fails if its own prediction disagreed**. The ASCII range is still classified exactly, for the diagnostic; the residual multi-byte gap is now harmless rather than merely unlikely, because drift is itself a gate failure. Proven: four U+3000 values, which `tr` still misses, now stop the gate instead of passing.
  **Issue:** #106

- **Decision:** rules normalise their input rather than being made line-ending-aware.
  **Why:** Dart's `.` excludes `\r` and its non-multiline `$` anchors before it, so a CRLF pubspec made every rule read an empty file — invariant 3 unenforced, `dependency_overrides` unrefused, direct dependencies mislabelled. A guard whose correctness depends on line endings is not a guard. `.gitattributes` pins the working tree too, so the file a contributor edits is the file CI reads.
  **Issue:** #96

- **Decision:** fail-closed extended from section headers to section entries.
  **Why:** #86 applied the refusal to the header and `_sectionEntries` went on silently skipping what it could not parse, so YAML's explicit-key form walked through. The principle was right and applied one level too shallow.
  **Issue:** #96

- **Decision (correction of my own, caught by running):** the two element-start patterns in `check_aab.sh` stay asymmetric.
  **Why:** #103 asked for them to be made the same shape. I did that and the real bundle immediately failed with `PERMISSION: android.permission.DUMP (declared)` — `permission` is also an *attribute* name, `android:permission` on a receiver, and its run is bare. `uses-permission` never appears as an attribute name, which is why only it can afford the looser match. The asymmetry now carries the reason and a fixture.
  **Issue:** #103

- **Decision:** the ads globs were tightened and the allow list extended, amending #15's AC further.
  **Why:** `*ads` and `*ads_*` matched any name containing those letters and refused `gamepads`, a real package from the Flame team, plus five others. The allow list added in #94 had seventeen names and none ended in `ads`, so the case that mattered was the one not asserted. Tightening nearly lost `ads_helper`, an ads-prefixed name, which an existing fixture caught — `ads_*` restores it.
  **Issue:** #97, amends #15

- **Decision:** pinned policy sentences stay literal, but the message changed.
  **Why:** the privacy policy is a public document a non-engineer may edit, and matching whole sentences produced "the policy no longer states X" when someone had merely reworded. The prose comparison now ignores case, commas and markdown emphasis, and where the wording genuinely is the thing being protected the message names what is pinned, why, and what to do. "No longer states" reads as an accusation, and the fastest way past an accusation is to delete the check.
  **Issue:** #102

- **Decision:** `analysis_options.yaml` stops claiming TODOs block the gate, rather than making them block it.
  **Why:** `dart analyze` does not surface the `todo` diagnostic from the command line, so `--fatal-infos` never sees one. Making it true needs a separate check, and whether TODOs should be bannable in a project this young is a decision for the owner rather than a config line. The comment now says what is true and what the alternative would cost.
  **Issue:** #107

- **Decision:** epic #7's third and fifth acceptance criteria were reworded, and the coverage map's housekeeping annotations reconciled to CLAUDE.md.
  **Why:** AC3 said the release build "strips" the INTERNET permission, describing the one mechanism invariant 1 forbids and `permissions_guard_test.dart` fails on; the reword was decided at planning time, logged here, and never applied. AC5 claimed determinism guards were already wired into the suite, which was never true in M0. Both edits are to the plan record, not to scope, and each carries a dated note saying what changed and why.
  **Issue:** #100

- **Note (own overclaim, third occurrence, now recorded in the artefact itself):** `.n8/memory/android-toolchain.md` has been corrected three times and each pass introduced or kept a claim nobody checked — most recently a confident but false explanation of why `flutter doctor` lists no Android Studio section. Flutter does search `~/Applications`; this Flutter version simply has no Android Studio validator. The file's preamble now warns the reader not to treat "everything was verified" as a guarantee, because this file has broken that promise once.
  **Issue:** #99

- **Note (own overclaim, mechanical):** two commit messages in this pass carried wrong test counts and were amended before push. That is the fourth and fifth instance in this milestone of a number asserted rather than read.
  **Issue:** #96

- **Note (a bug reproduced while fixing a bug):** `verify_upload_cert.sh`'s first keytool probe was `cmd | grep -q`, and with `set -o pipefail` the stub's non-zero exit made the pipeline false even when grep matched — so the check never fired and the macOS stub was used as though it worked. Identical in shape to the SIGPIPE race fixed in `check_aab.sh` during the first pass. Captured first now.
  **Issue:** #108

## /n8-exec M1 — 2026-09-19

CI and the tag-to-Play pipeline, on `milestone/m1-ci`. Three stories implemented in full; #19 blocked on the owner, and #20/#21's live verification blocked behind it.

- **Decision:** proceeded with M1 despite two open `sev:high` defects in `tools/gate.sh`, which CI now runs.
  **Why:** #121 (no `GATE FAILED` label when the build step fails) and #120 (the signing cross-check can pass with a false header) were checked against M1's criteria before starting. Neither invalidates them: the gate's exit code still propagates, so CI goes red and the merge block works, and the signing path is not exercised on a pull request because no `HS_*` secrets are present. The cost is log legibility when a CI build fails, which is worth saying once so the first red run is not mistaken for something new. Stopping M1 to fix them first would have delayed the one thing four rounds of local verification could not provide — running all of this somewhere other than this machine.
  **Issue:** #18

- **Decision (deviation from a stated acceptance criterion):** `tools/set_ci_secrets.sh` **parses** the signing credentials file rather than sourcing it, which is what #19's criteria say.
  **Why:** that file executes arbitrary code when sourced (#119, open, `sev:critical`) and records a value that does not open the keystore. Writing new code whose documented happy path is `source` would add a second caller to a known code-execution defect while it is open. Parsing costs three lines, is strictly safer, and keeps working whichever way the quoting is eventually fixed. Flagged on the issue before the code was written, and proven: a credentials file containing a command substitution leaves no trace when parsed.
  **Issue:** #19, deviates from its third criterion

- **Decision:** the two pin greps were run in the form the plugin's Actions lessons actually specify, not the shortened form #18's criterion quotes.
  **Why:** the lessons' greps exempt `./` and `docker://`; the quoted short form does not, and it flags `uses: ./.github/workflows/ci.yml` — which #20's criteria *require*, because the release workflow must call the gate rather than restate it. The two criteria would otherwise contradict each other. Both real greps print nothing.
  **Issue:** #18, #20

- **Decision:** every action version and every input name was resolved by lookup at authoring time.
  **Why:** the plan resolved them on 2026-09-18 and I resolved them again today rather than trusting the note. All six matched. Two input names did not come free: `subosito/flutter-action` publishes `action.yaml`, not `action.yml`, so the first manifest read 404'd and a recalled input name would have gone in unchecked.
  **Issue:** #18

- **Decision:** the ruleset was updated before the milestone PR was opened, so this PR is the first one gated by its own work.
  **Why:** #18's discretion asks for it, and it is the only way the criterion "a PR cannot merge until that check passes" gets tested by the change that introduces it rather than by the next one. Verified by re-reading the ruleset from the server — which was the wrong check, and the criterion it confirmed was itself wrong; see the correction at the end of this file.
  **Issue:** #18

- **Note:** `tools/set_ci_secrets.sh` was written but deliberately **not run**. Running it is the moment the owner's real keystore password moves into a repository secret, and that belongs in a session where the owner can see it happen. It needs no credential of theirs, only their say-so.
  **Issue:** #19

- **Blocker:** #19 needs three owner acts — the Play Console app entry, a `gcloud auth login` on this machine, and the Console permission invite for the service account. The automation for all three is written; the credential is not mine to supply. #20 and #21 are implemented and tested for everything that does not need a credential, and their live verification waits on this.
  **Issue:** #19, blocking the live halves of #20 and #21

- **Decision (Rule 1 — own bug, found by CI on its first run):** `tools/gate.sh` used `mktemp -t hs-gate-build`, which works on macOS and fails on GNU coreutils with "too few X's in template".
  **Why it matters beyond the one line:** this is the first defect in this project found by a machine that is not the author's. Four rounds of local verification could not have found it — the gate passed every time on macOS, where `mktemp -t` treats the argument as a prefix. It failed within two minutes of CI existing. The portable form is an explicit template under `${TMPDIR:-/tmp}`.
  **Issue:** #18

- **Correction (the entry above about the ruleset was wrong, and the method that produced it was wrong):** re-reading the ruleset from the server proved the *rule exists*. It did not prove the rule *binds*, and it does not. The criterion names the context `CI / gate`, and #18's key_links states the string equals `<workflow name> / <job name>` — but a ruleset matches the **check-run name**, which for this workflow is `gate` (app `github-actions`, id 15368). `CI / gate` is only what the pull-request UI renders. So the required context never reports, sits pending forever, and `main` is blocked unconditionally — green or red, PR #124 and PR #125 are both `BLOCKED`. Proof: `isRequired` is **false** for the `gate` check run, from the GraphQL `statusCheckRollup` with `isRequired(pullRequestNumber: 125)`, while the rollup state is `SUCCESS`.
  **Why this got through:** existence was checked, binding was not — the same gap four rounds of M0 verification kept finding in guards, here in a repo setting. #18's own test plan names it under "Not covered": *"whether the required-check context string matches a renamed job"*. The uncovered thing is precisely the thing that broke.
  **What it invalidates:** the first red-then-green demonstration on PR #125 proves nothing about the gate. The check went `FAILURE` then `SUCCESS` and `mergeStateStatus` read `BLOCKED` both times, for a reason unrelated to the check. A demonstration that would have read identically with no gate at all is not evidence.
  **The fix, not yet applied:** `PATCH repos/<repo>/rulesets/23682733` replacing the context with `{"context": "gate", "integration_id": 15368}` — the `integration_id` pins it to GitHub Actions so nothing else can satisfy a check named `gate`. The call was denied by the permission classifier as a CI-bypass, which it is not; it is the opposite, and it is the owner's to allow.
  **Issue:** #18, deviating from its fourth criterion and from the key_links line

- **Resolution (the correction above, applied):** the owner approved the ruleset call. Two things were wrong, not one. The context string was `CI / gate` where GitHub matches the check-run name `gate`; and the update verb is **PUT** with the full ruleset body, not `PATCH` — a `PATCH` returns `404 Not Found` on a ruleset that plainly exists and that `GET` reads back, which reads like a permissions problem and is not one. #18's own discretion note said PUT; I used PATCH anyway and spent a scope check on the wrong hypothesis.
  **The fix:** `PUT repos/<repo>/rulesets/23682733` with the body built from the `GET` by `jq`, replacing the one rule and carrying the `pull_request` rule through verbatim — a PUT replaces the whole `rules` array, so rebuilding it from the server's own copy is what keeps the pull-request requirement from being silently dropped. The context is now `{"context": "gate", "integration_id": 15368}`; the `integration_id` was not in the criterion and pins the check to GitHub Actions, so no other app can satisfy a check named `gate`.
  **Verified by binding, not by existence:** `isRequired` is now **true** on the `gate` check run for both open PRs, and the two states discriminate — red `e89d820` → `rollup=FAILURE`, `mergeStateStatus=BLOCKED`; green `63a2c66` → `rollup=SUCCESS`, `mergeStateStatus=CLEAN`. Before the fix both readings were `BLOCKED`. `required_approving_review_count` is still 0, checked after the PUT.
  **Issue:** #18

## Ad-hoc — 2026-09-19 — reconciled by /n8-replan 2026-09-23

- **Change:** #18's fourth acceptance criterion and its `key_links` line were **amended** after the fact. Both specified the required status-check context as `CI / gate`, i.e. `<workflow name> / <job name>`. A GitHub ruleset matches the **check-run name**, which is `gate`. As written, the criterion blocked every merge to `main` unconditionally. The shipped rule is `{"context": "gate", "integration_id": 15368}`; the `integration_id` is an addition, pinning the requirement to GitHub Actions so nothing else can satisfy a check named `gate`.
  **Why:** implementing the criterion verbatim produced an inert rule that read as correct from the server and blocked everything in practice. The issue text is the plan, so leaving it uncorrected would have any future reader — including `/n8-verify`, which was told to work from the AC — score the shipped state as non-compliant and "fix" it back. Amended in place on the issue with the old text struck through and dated, rather than silently rewritten.
  **Affects:** #18 (closed, text amended), #137. No later milestone plans depend on the context string; M7's release work goes through `release.yml`, which does not read it.

## /n8-exec M1 fixes — 2026-09-19

- **Decision (Rule 1):** `tools/play_release_codes.py` is a new Python helper, so the version-code extraction is a real JSON parse instead of a regex over flattened text.
  **Why:** #128 was two defects in one `sed`, and both were the regex's fault rather than a slip — `[^}]*` cannot cross a nested object, and a greedy `.*` takes the last match. A third regex would have been the third guess. `jq` is not on stock macOS, which is why the regex existed; `python3` is on both stock macOS and `ubuntu-latest`, and the script now says so and fails with a clear message if it is absent. A separate file also makes the logic testable, which the inline `sed` never was.
  **Issue:** #128

- **Decision (Rule 1):** `HS_PLAY_API` makes the Play endpoint overridable, and the promotion path is exercised against a mock API.
  **Why:** everything below the argument checks in `tools/play_promote.sh` was unreachable in a test, which is exactly where #128, #129 and #133 all lived — three defects in the one region with no coverage, while the well-covered refusal layer had none. Follows the precedent of `HS_UPLOAD_CERT` in `tools/verify_upload_cert.sh`. Six scenarios now cover the promotion: notes-bearing release, two releases, draft refusal at PUT, draft refusal at commit, a 403, and a read-back mismatch.
  **Issue:** #128, #129, #133

- **Decision:** `tools/setup_play_ci.sh` now **asks** which Google account to use rather than asserting one.
  **Why:** #134 wanted the active account asserted to be the Play Console owner. The script cannot know which account that is — nothing in the repository records it, and recording it would be the memory-file-guesses-again failure this project keeps hitting. So it names the account it found and requires a confirmation, with `HS_PLAY_ACCOUNT` for a non-interactive run. That refuses the wrong-account case without inventing the right one.
  **Issue:** #134

- **Decision:** the keystore pre-flight in `tools/set_ci_secrets.sh` is skipped, loudly, when no real keytool is found, rather than refusing.
  **Why:** the first version used `command -v keytool`, which on macOS finds a stub that exists, is executable and cannot run — so the pre-flight would have refused every correct credentials file, a worse bug than the one it was added for. It now resolves keytool the way `verify_upload_cert.sh` does and probes it. Refusing outright would make a real keytool a hard requirement for setting secrets, which is not this story's bargain.
  **Issue:** #126

- **Decision:** the unresolved Play 14-day rule is recorded as unresolved, with the stricter reading recommended, rather than picked.
  **Why:** `.n8/memory/play-console.md` asserted both readings in consecutive sentences (#139) and nothing in the repository or in #19 sources either. Choosing one would have replaced a visible contradiction with an invisible guess — the exact failure mode of #81/#88/#99/#116. The file now says which part is certain, which is not, and that keeping 12 testers enrolled continuously satisfies both readings.
  **Issue:** #139

- **Note (method):** the plan-comment-before-code step was skipped for these fourteen bugs. Each was filed by `/n8-verify` with the repro, the cause and the fix already in its body, so the definition of done was written down before any code — which is what that step exists to produce. Evidence comments still go on each issue.
  **Issue:** #126-#139

## Ad-hoc — 2026-09-19 (second M1 fix pass) — reconciled by /n8-replan 2026-09-23

- **Change:** the per-tester-versus-cohort reading of Play's fourteen-day rule is **withdrawn as a stated fact** from #73, #70, the M7 milestone description and the two ledger lines above. Each asserted one reading or, in #73's case, both two criteria apart. The stricter operational rule — keep at least twelve testers enrolled continuously for the whole window and treat any dip as restarting the clock — replaces it, because it satisfies either reading.
  **Why:** nothing in this repository or in #19 sources either mechanism. #139 removed the contradiction from `.n8/memory/play-console.md` and left it in the artefacts that get executed, which is the instance-versus-class miss that fix was itself written to avoid (#148). Choosing a side would have replaced a visible contradiction with an invisible guess; the memory file now carries the open question and everything else defers to it.
  **Affects:** #70 and #73 (bodies amended in place, dated, with the note naming #148), M7's milestone description items 23 and the phase note. No code depends on it. The question is the owner's to settle by reading the Console before M7 plans a recruitment schedule.

- **Decision (deviation, Rule 1):** `tools/set_ci_secrets.sh` and `.github/workflows/play-api-check.yml` now assert `HS_KEY_PASS == HS_KEYSTORE_PASS` instead of running a `keytool -keypass` check.
  **Why:** #20's and #19's criteria both describe a `-keypass` check as proving the key password. It cannot: keytool prints "Different store and key passwords not supported for PKCS12 KeyStores. Ignoring user-specified -keypass value" and exits 0 whatever is passed, while a wrong *store* password exits 1 (verified both ways). A PKCS12 keystore has one password, so the check that can fail — and that is true for a keystore this project made — is that the two secrets agree. A check that cannot fail is worse than no check, because it is counted as coverage.
  **Issue:** #143, deviating from #19's fourth criterion and #20's third

- **Decision (Rule 1):** `tools/play_promote.sh` treats a curl transport failure as an API failure rather than letting `set -e` kill it.
  **Why:** found by pointing the exit-5 test at a closed loopback port instead of Google (#147). A refused connection exited 7 mid-edit with no message. The same change surfaced `"${API_BODY_FILES[@]}"` being an unbound variable under `set -u` in bash 3.2 — the macOS default — on every path that fails before the first request. Both would have fired in production; neither was reachable while the test talked to Google and got a well-formed 401.
  **Issue:** #147

- **Decision:** the secret rule was inverted rather than extended.
  **Why:** three rounds of adding patterns (#131, #141) each closed the spellings the report named. `set -v`, `set -euo pipefail; set -x`, `secrets['NAME']`, `cat<<EOF`, `cat <<'E-OF'` and `bash -x script.sh` all passed the third version, and it had begun refusing a legitimate `cat <<EOF > key.properties`. Enumerating shell syntax is unwinnable. Forbidding the interpolation itself is one rule, cannot be spelled around, and needed no workflow changes because every one here already passes secrets as step-level `env:`.
  **Issue:** #141, #142

## /n8-exec M1 fixes, third pass — 2026-09-20

- **Decision (amends a stated convention):** `package:yaml` is a dev dependency, and `test/guards/repo_files.dart`'s "guards add no dependencies" rule is narrowed to *runtime* dependencies.
  **Why:** three rounds asserted workflow structure with line scans and three rounds of bypasses followed. The substring version of the release-shape test was satisfied by a **comment** — with the strings left in one, the gate job became a no-op, the permission scan and certificate check became `true`, and the track became `production`, with 289 tests green. The original reasoning holds for a package the app ships, which invariant 3 governs and which a build could silently drop; a test-only package that went missing fails to compile the guards instead. Proven not to ship: the built bundle contains no `package:yaml`, while the control `package:flutter/` is findable by the same scan.
  **Issue:** #154, and the owner chose this over keeping the scans or adding actionlint

- **Decision (Rule 1):** the two dispatch inputs on `play-promote.yml` are `type: choice` with an explicit option list.
  **Why:** free text let a crafted `to_track` append a forged "Promoted on Play … -> production" line to the run summary and title a refused run "Promote internal to production" in the Actions list (#165). The refusal step stays — two barriers. *(Corrected 2026-09-21, #196: this sentence originally continued "and GitHub's cannot be bypassed by dispatching the API directly". That was a guess stated as fact; see the #179 entry below, which retracts it. The two readings stood twenty-five lines apart until now.)*
  **Issue:** #165

- **Decision:** `report-gate-failure` triggers on `needs.gate.result != 'success'` rather than `failure()`.
  **Why:** a cancelled gate is not a failure, so the "nothing shipped" line never appeared for one *(flagged 2026-09-21 as UNVERIFIED, #209; **settled 2026-09-22 against the job**, #257. Run 35783678379 — the first `v0.1.0` tag, gate cancelled by the battery timeout — recorded `report-gate-failure: SKIPPED`, so a cancelled gate announces nothing. The change remains right, `result != 'success'` being broader than `failure()`; the gap is accepted in writing rather than closed, because the notifier that would work keys on `workflow_run` and that is new infrastructure on the release path.)* — the case an operator is most likely to misread.
  **Issue:** #165

- **Note (unlogged deviations, now recorded):** `play-promote.yml` and `play-api-check.yml` use `timeout-minutes: 15` where the plan said 10; `tools/play_promote.sh` collapses the plan's exit codes 3 and 4 into 5, which #133 named and neither fix restored; the promote summary lists version codes space-separated where the plan said comma-separated; `tools/setup_play_ci.sh` `chmod 700`s the secrets directory rather than refusing a loose one, and implements no `--rotate`. Each is defensible and none was in the ledger.
  **Issue:** #165

- **Correction:** `#148`'s ad-hoc entry claimed the per-tester reading was withdrawn from "the two ledger lines above". One was edited and one was not, and the edited one kept the presupposition rather than the attribution. Both now carry the qualification, and `.n8/memory/play-console.md` no longer attributes the word "continuous" to #19, which does not use it, nor claims the API check "proves all five work" when `HS_KEY_PASS` is proved by nothing.
  **Issue:** #164

## Ad-hoc — 2026-09-20 (project goal: this repo becomes a reusable basis) — reconciled by /n8-replan 2026-09-23

- **Change:** The owner set a three-phase sequence that outlives M1: *"Let's finish M1, then deploy the scaffold to ensure it works, then create something reusable from it."* Earlier in the same session: *"I want to get to a clean state of infra and CI to use this as a basis for future apps, so I really want to finish M1 through all bug fixes until we're really happy with it."*
  **Why:** It reframes what the guards and tooling are *for*. They are not overhead on a Sudoku app — they are the deliverable, and Honest Sudoku is their first consumer. That is why four rounds of verification finding ~50 defects, all in guards and tooling, is progress rather than churn, and why the mutation battery became a first-class gate step instead of a once-a-round manual review.
  **What follows from it:** (1) M1 closes only when every filed bug is fixed, not when the AC are ticked. (2) The scaffold ships to the internal track *before* there is a game, because proving the release path is the point of the deploy, not distributing Sudoku. (3) A later extraction — template repo or equivalent — is real scope that no milestone currently holds.
  **Milestones/issues likely affected:** no planned issue changes meaning, but the roadmap has no milestone for the extraction in phase 3. That is a planning gap to close once M1 is verified, not now.

## Ad-hoc — 2026-09-20 (#21's post-merge criterion amended; #179) — reconciled by /n8-replan 2026-09-23

- **Change:** #21's post-merge acceptance criterion and its Demo required a dispatch with `to_track: production` that "fails at the first step", with both run URLs in the closing comment. #165 had already made both dispatch inputs `type: choice` with `options: [internal, alpha, beta]`, so `production` is not selectable and that run cannot be created from the UI. The criterion asked for evidence that cannot exist. Owner's call (2026-09-20): keep `type: choice`, rewrite the criterion.
  **Why:** The two were filed in different rounds and nobody reconciled them. Keeping `choice` is the stronger barrier — it removes the value from the UI entirely rather than accepting and rejecting it — and the refusal step stays as the second, so nothing is lost by dropping the dispatch.
  **What replaced it:** the option lists are now asserted in `test/guards/play_promote_args_test.dart`, and the refusal step's `run:` body is executed directly against `production` (must exit non-zero) and against `internal -> alpha` (must exit zero). Behaviour rather than a run URL, and it also covers the direction nothing asserted: that a legitimate promotion is *accepted*.
  **Also corrected:** `play-promote.yml` carried a comment asserting that `type: choice` "cannot be bypassed by dispatching the API directly". That was a guess stated as fact. It is untested — the test is a live dispatch of the workflow whose refusal is the subject, and this session's attempt was refused by the agent sandbox as a production deploy — so the comment now says so plainly instead.
  **Milestones/issues likely affected:** #21 only. #8's third criterion already reads "closed testing; production is a human act in the Console".

## Ad-hoc — 2026-09-20 (two #14 AC3 deviations, logged late; #105, #114) — reconciled by /n8-replan 2026-09-23

- **Change:** `tools/check_aab.sh` deviates from #14's AC3 in two ways that were never logged. #105 asked for the first to be logged *or* the story amended, and neither happened.
  1. **AC3 says the scanner needs "only unzip, tr, grep, sort".** It also needs `awk` (the element decoder, #80) and `dirname` (the `cd` on line 26, there since the file was written). The header is now correct and, more to the point, carries the command that *verifies* it — running the script under `env -i` with only those tools on PATH. That was never run; it takes two seconds and it is how #114 was found.
  2. **AC3 specifies `grep -x` for the package check; the script uses a token-boundary `grep -cE`.** `-q` closes the pipe under `unzip`, which then dies of SIGPIPE, and under `set -o pipefail` that becomes the pipeline's failure — a race that passed or failed at random between identical runs. `-c` reads to the end. This is an improvement that preserves the AC's stated purpose, which is exactly why it belongs here rather than only in a code comment.
  **Why it matters:** both were visible in the source and invisible to anyone reading the plan. A deviation recorded only where the deviating code lives is a deviation the plan does not know about.
  **Milestones/issues likely affected:** #14 (M0, closed). AC3's wording is now stale in two places; the behaviour is correct and better than specified, so this is a record correction rather than a code change.

## Ad-hoc — 2026-09-20 (record corrections found by the fourth M0 verification; #115, #118, #122) — reconciled by /n8-replan 2026-09-23

- **`flutter_lints` is exempt from the justification rule and the record did not say so (#118).** `dependency_policy.dart` exempts `flutter`, `flutter_test`, `flutter_localizations` and `flutter_lints`. The first three are the SDK; `flutter_lints` is a genuine third-party pub.dev package, and the exemption is why `pubspec.yaml` carries **zero** `# why:` lines while the guard is green. CLAUDE.md invariant 3, epic #7's fourth criterion and coverage-map item 3 all said *every* third-party package carries a justification, with no exemption mentioned. The exemption is reasonable and was commented in the code; it is now in the invariant too. Same failure mode as #100.
- **The M0 coverage map quoted the format command one flag short (#118).** Item 6 said `dart format --set-exit-if-changed .`; the gate runs `dart format --output=none --set-exit-if-changed .`. The artefact is stricter than the record — it reports rather than rewrites — which is the right direction, but it is a word-for-word mismatch in a map whose stated purpose is word-for-word checkability. The map is corrected.
- **`dart:io` is now banned outright in `lib/` (#118).** The rule listed class names, and no name list catches `Process.run('curl', [url])`. Banning the import is one line and catches every one of them, at the cost of refusing legitimate file IO — which this app does not do. When a file in `lib/` genuinely needs it, that is a conversation about invariant 1 and a change to the rule, not a local exception. Seven missing connector names were added as well.
- **The bundle inertness check is narrated as doing more than it does (#115).** #92's and #103's closing comments position it as *the* tie between the synthetic fixtures and reality, "the thing that cannot be skipped". For one real regression shape — an awk decoder mutated to emit only the allowlisted name — the inertness check scans 0 and reports clean, because it asks "did I see the self-permission?" and that is exactly what a partially blind decoder still sees. What catches that shape is the fixture suite: the same mutation gives 7 failures in `bundle_scan_test.dart`. The protection exists; it is one layer up from where the narrative put it, and the comments now say so.
- **The analyser comment was wrong twice (#107, #122).** The first claimed TODOs block the gate; they do not at `info`. Its replacement claimed `dart analyze` never reports `todo` "at any severity" and that blocking them "would need a separate check". Measured one severity at a time on 2026-09-20: `info` exits 0, `warning` and `error` both exit 3. `info` is the one suppressed severity and it is the one this project uses, so the original observation was right and the generalisation built on it was not. The comment now carries the three measurements.

## /n8-exec M1 — 2026-09-21 (fifth fix pass, the eleven bugs the fifth verification filed)

- **Decision:** `#192`'s first item — "the guard suite races itself" — was not reproduced and is recorded as **not a defect**. No test modifies a **tracked** file (`grep` finds zero `File('${repoRoot.path}…')` writes, and a verifier independently confirmed it). *(Corrected 2026-09-21, #196: the original sentence said "no test writes into the repository", which is too strong. `signing_guard_test.dart` runs a real `flutter build appbundle --release` with `workingDirectory: repoRoot.path`, so it writes `build/` and `.dart_tool/` while other files run concurrently. Both are gitignored, so neither `git status` nor the battery's dirty-tree refusal would ever see it.)* The contention every verifier reported came from eight of them sharing one worktree, which was my orchestration error in the verification run.
  **Why it still produced a change:** the battery reading a single pass/fail per mutation is a real robustness gap regardless of what caused the flake this time. It now re-runs the suite before reporting a SURVIVED verdict — that is the verdict that matters, and one flaky green would either invent a hole or let a real one be dismissed as flake.
  **Issue:** #192
- **Decision (Rule 2):** `#176`/`#190`'s argv row could not be closed by the leak scan alone. The keytool pre-flight resolves the **real** keytool by its pinned path, so no stub ever sees that argv. Added a **source rule** over `tools/*.sh` refusing `-storepass <value>`, `-keypass <value>` and `--body "$(cat …)"`.
  **Why:** the property `set_ci_secrets.sh:130` asserts is about what the script *writes*, and that is readable. A stub check would have been the more satisfying shape and would have tested nothing.
  **Issue:** #190
- **Decision:** `#191`'s handler is exercised by injecting the loader (`Workflow.parseWithLoader`) rather than by nesting deeper. Raising the depth is what the original test did, and it was lowered from 60000 precisely because that much stack pressure failed a concurrent file. Injecting the throw tests the branch without the side effect.
  **Issue:** #191
- **Decision:** `mutations` added to the `main` ruleset's required checks by **PUT** with the full body (PATCH 404s), pinned `integration_id: 15368`. Binding to be proven on this PR with `isRequired(pullRequestNumber:)`, not by reading the settings page — the lesson #18 learned twice.
  **Issue:** #187
- **Own errors worth recording, because the pattern is the point:** `_swallowsFailure`, written to catch `|| true`, had #183's defect on its first attempt — the command and its `|| true` sit on different lines joined by a backslash, so a line-by-line regex saw neither together. And the leak scan's file walk crashed on a PKCS12 keystore because `readAsStringSync` throws `FileSystemException`, not `FormatException` — committed through `rc=1` before I read the exit code rather than the test count. Second time in two runs.

## /n8-exec M1 — 2026-09-21 (sixth fix pass; the seven bugs the sixth verification filed)

- **Decision (the organising one):** every finding of the sixth round was the same shape — *fixed the instance the issue named, rebuilt the class hole beside it*. So where a structural fix was available this pass, it was taken over another instance:
  - **#200** — leak sentinels are **derived** from the environment each script is handed, not registered by each test. Registration was the hole: `_run` scanned on every call over a set `_plant` filled in two places. There is no registration step left to forget.
  - **#197** — the step-level conditional check was **inverted**: every step must be unconditional except a named few, rather than seven named steps that must be. A new step is now safe by default rather than unguarded by default.
  - **#194** — `parse` and `parseWithLoader` collapsed into **one body** with a defaulted parameter. A guard on an injected seam does not guard the seam; with one implementation there is no second one to write.
  **Why:** three rounds of "close the named instance" produced three rounds of the same finding. A fix that removes the *possibility* of the error is the only kind that has stopped recurring.
- **Decision:** the 6-character sentinel floor now **fails loudly** rather than skipping. It was a silent kill switch — the pre-flight group's fixture password is `"pw"`, so that group's scan was doubly dead. Four fixtures were lengthened as a consequence, which is the check doing its job on its first run.
- **Decision:** `TMPDIR` and `RUNNER_TEMP` are redirected into the scanned tree rather than scanning the real system temp directory. A leak to scratch space was invisible, and `$RUNNER_TEMP` is where these workflows put the decoded keystore.
- **Decision:** the credentials-file exclusion is keyed on the **variable a value came from**, not on the file path. The old exclusion was unconditional, so anything could be written there; now a private key appended to that same file is still caught.
- **Decision (Rule 1 — own bug, found by the battery):** the `#176` private-key mutation SURVIVED after the derivation rewrite, because the key is minted by a stub into a file and never passes through the environment. The stub's test declares it. Two fixtures then collided on their first eight characters. Neither would have appeared in a green suite; both were caught by running the full battery before pushing.
- **Correction to my own records (#196):** the `#192` ledger entry said "no test writes into the repository". Too strong — `signing_guard_test.dart` runs a real `flutter build` into the gitignored `build/`. The defensible claim is "no test modifies a **tracked** file", and that is what it says now.
- **#199, the record items:** `#18`'s AC2 and AC4 amended in place rather than left describing an artefact that has moved; the coverage map's `CI / gate` corrected to the two check-run names the ruleset requires; the battery count removed from `ci.yml` and `CLAUDE.md` rather than restated, because prose cannot keep a number a file already states.
- **New guard on the one unguarded thing:** the ruleset binding. `#187` was real and silently reversible — no test read it. A guard now asserts both required contexts exist and are pinned to integration 15368, skipped rather than failed without `gh` auth so an offline developer does not see a red suite for a fact about the remote.

## /n8-exec M1 — 2026-09-21 (seventh fix pass; the nine bugs the seventh verification filed)

- **The organising decision, and it is different from last pass's.** The sixth pass tried *structural* fixes and all three relocated their holes: `#200`'s derivation moved the gap from "forgot to plant" to "forgot to use `_run`"; `#197`'s inversion covered one job of one file; `#194`'s one body did nothing about a *new* body. The lesson is not "be more structural" — it is that **a fix which relies on future discipline fails, and a fix which makes the bypass detectable does not.** So each fix this pass ships with an assertion about the thing that could go wrong next:
  - `#208` — one `_exec` chokepoint, **plus** `no raw Process.runSync starts a script in this file`, which caught three bypasses I had written while making the change. Exemptions must be declared on the line above with a reason.
  - `#203` — the call site is asserted, not the body: `workflow_rules.dart` loads no YAML, reaches `Workflow` through `parse` alone, passes no loader. The untested link had moved four times (handler → test → delegation → call site); this asserts the link itself.
  - `#206`/`#209` — key links and step sets asserted for every workflow, derived from the files rather than named per-file, because naming them per-file is how two of four came to be unpinned.
- **Decision (`#204`, and this is `#205` applied):** `_swallowsFailure` is no longer the only thing standing between a swallowed failure and a green gate. A new test **executes** each step's `run:` with the command it depends on stubbed to exit 1, and requires the step to fail. Verified against three bypasses the regex could not see — a `#` inside a quoted string, `set +o errexit`, and a backgrounded command. The regex is kept as a cheap first line because it names the offending text, which a propagation failure cannot.
  **Honest limit, recorded rather than implied:** the stub fails a command everywhere it appears, so a mutation on a line the step never reaches is not exercised. Per-subcommand stubs would close that.
- **Decision (`#202`):** the ruleset guard is kept in the suite and **not** given a CI token. Reading rulesets needs repository-administration scope; granting CI admin-read to verify a permissions control is a worse trade than the gap, in a project where every workflow declares `permissions: contents: read`. What changed instead: a missing ruleset now **fails** rather than skipping (pointing it at a nonexistent id printed `All tests passed`), whole tokens are compared rather than substrings, and the branch condition and bypass list are read. `tools/gate.sh` says at the point of use that CI skips it.
- **Own errors caught in this branch, both by the tooling rather than by me:** the leak scan's slice forms matched a fixture ending in the word `password` against the keystore step's own English prose — a slice is now only searched if it contains a non-letter. And the `#209` battery entry left the YAML unparseable, which the battery reported as BROKEN — "testing less than it claims" — rather than passing over.
- **Records:** `#19` AC4 and `#20` AC5 amended in place; both described something *better* than the criterion asked for and neither was amended when it changed. `#196` item 2's ledger twin flagged, which `#196` named and the sixth pass did not do.
- **The battery's own two verdicts, reconciled — and what they turned out to be saying.** The seventh pass ended with one BROKEN and two WRONG-REASON. All three were the battery telling the truth about *mutations I wrote badly*, not about the guards:
  - `#203`'s mutation repointed the rules at `Workflow.parseFast`, a method nothing ever added. That is a **compile error**, not a bypassed guard, and it failed every test in the file at once. The defect it names — "a second parse path is added *and* the rules repointed at it" — cannot be written in one file, so `Mutation` gained `also`, a list of further `(path, apply)` edits. The mutation now adds a real `parseFast` to `workflow_yaml.dart` and repoints the rules at it; it compiles, changes no behaviour, and the only test that can go red is the one being measured. It prints `parse-path: the rules reach Workflow through {parseFast}`.
  - `#207`'s mutation **deleted** the token check where its name says it **moves** it. Deleting leaves every refusal working, so the ordering assertion was right to stay silent. A `chain()` helper now expresses a move as the two edits it is, and the mutation prints `order: the refusal must be the production one`.
  - **Generalised, because both were the same mistake:** YAML mutations have been checked for parseability since `#172`; Dart mutations were not. `compiles_as_dart` now runs `dart analyze` over every mutated `.dart` file and reports BROKEN, so a mutation that cannot be applied is never scored as a guard failure.
- **Decision (Rule 1 — a committed defect, found while probing):** `tools/setup_play_ci.sh` at branch HEAD granted the CI service account `--role roles/owner`. An interrupted battery run left that mutation in the working tree and `9215586` (a docs commit) swept it in; the tree's later correction then hid it from `tools/gate.sh`, which reads the tree and not the commit. It never reached `main` and CI would have failed on push. The commit was amended to drop the hunk. **Two guards, because `finally` cannot cover a kill:** the battery writes `.mutation_check_in_flight` naming the files it is about to mutate and refuses to start while one exists, so an interrupted run is detectable by the next; and `gate.sh` now prints, after its verdict, that the verdict is about the working tree, listing the dirty files. The guard that caught it — `no IAM role is ever granted to the service account` — was already there and already correct; what was missing was any reason to run it against HEAD.

## Ad-hoc — 2026-09-21: the guard suite's architecture changes to "execute the artefact" (#205) — reconciled by /n8-replan 2026-09-23

- **The change.** Guards that assert a *runtime* property stop pattern-matching the artefact's text and start running it. Document properties — action pins, `permissions:` blocks, triggers, step sets — stay textual and keep being read structurally by `Workflow.parse`. This is #205, filed as a proposal after round seven and adopted by the owner after round eight.
- **Why, in one sentence with the evidence behind it.** Across rounds five to eight, every guard that was defeated is a text assertion *about* an artefact, and every guard never defeated *executes* one. Round eight made it sharp: #207, the only fix that survived a genuine adversarial move, is the one that runs `play_promote.sh`; #202, #203, #206 and #209 all fell to a substring, a surviving call site, a prose comment or an unenumerated file.
- **Why it is logged as drift.** M1's stories assume the guard suite reads workflow and script text. Changing what a guard *is* is an architecture change, and CLAUDE.md says that is drift by definition even when no acceptance criterion changes wording.
- **Milestones checked for staleness, and the honest answer is none.** M2's #26 ("uniqueness, determinism and grading hold over many seeds") is a property test that runs the real generator and has the solver count solutions — it is already execution-based and is the model #205 argues for, not a casualty. No later milestone plans a text-matching guard. `/n8-replan` is therefore *not* recommended; this entry exists so a future reader can see the decision was taken deliberately rather than drifted into.
- **The first test, and why it is first.** A vacuity check: run every workflow step body with the command it depends on stubbed to **succeed**, and require exit 0. Round eight showed `expect(exitCode, isNot(0))` holds unconditionally for `build`, `sidecar`, `keystore` and `asset` — `build` because `${{ steps.version.outputs.name }}` is a bash bad substitution that aborts before `flutter` ever runs. Four of nine steps were proving nothing, and the check that reveals it is three lines.
- **Honest limits carried forward, not quietly dropped.** A stub fails its command at every occurrence, so a mutation on a line the step never reaches is still unexercised (#204). The leak-form set cannot be complete by construction (#208). Both stay stated where they bite rather than implied to be closed.
- **Issues:** #205 (the proposal), #202, #203, #204, #206, #208, #209 (the instances), #211 (six false claims in the record), #212 (#20 AC5's misplaced amendment). Milestone M1.

## /n8-exec M1 — 2026-09-21 (eighth fix pass; #205 applied)

- **Corrections to this ledger's own seventh-pass entry, which round eight proved false.** Three statements in the entry above claimed properties the code beside them did not have. They are the subject of #211 and they are corrected here rather than quietly edited, because the pattern matters more than any one of them:
  - *"whole tokens are compared rather than substrings"* (#202) — untrue when written. The code was `contains('$check:15368')`, so a ruleset with `enforcement: disabled` passed (`inactive` contains `active`) and one requiring `CI / gate` passed too — the exact #137 failure the assertion's own message warns about. **Now true:** the response is parsed as JSON and each field compared for what it is.
  - *"the branch condition and bypass list are read"* (#202) — untrue when written; the jq read `.enforcement` and the contexts only. **Now true.**
  - *"granting CI admin-read to verify a permissions control is a worse trade than the gap"* (#202) — the premise was false. This repository is **public**, and the rulesets endpoint answers 200 to an anonymous request with the enforcement state, the branch condition and both required checks; only `bypass_actors` is redacted. The check now runs in CI, reading it anonymously, and `tools/gate.sh` no longer says otherwise.
- **And two in the code, same class:** the step-set test said it was "derived from the files rather than named per-file" while being a two-entry literal covering two of four workflows — which is what hid `report-gate-failure`; and the key-link test said "Equality, not `contains`" directly above a `contains`. Both now do what they said.
- **The one verification finding I did not act on, and why.** Round eight reported the credentials-file exemption as inverted, citing my own commit message. It is not: the exemption is scoped to `channel.path == _credentials`, so a foreign value written into that file is caught while the keystore password that belongs there is not. The commit message was accurate. Recorded because "the verifier said so" is not evidence either.
- **What #205 actually changed, measured rather than asserted.** The decisive experiment is in the parse-path commit: with five of six rule call sites repointed to a parse path with no error handling, `dart analyze` is clean, the text assertion prints `All tests passed`, and the execution test fails. Same tree, same mutation, opposite verdicts. That is the split #205 proposed, demonstrated instead of argued.
- **The vacuity check is the transferable lesson.** Running each workflow step body with its command stubbed to **succeed** and requiring exit 0 found that four of nine steps could never pass, so their propagation assertions were satisfied unconditionally. A test that cannot pass is as useless as one that cannot fail, and nothing in eight rounds had asked that question. It is cheap, general, and it caught `build` — the step that produces the shipped bundle.
- **Honest limits carried forward rather than closed:** a stub fails its command at every occurrence, so a mutation on a line a step never reaches is still unexercised; the leak-form set is one transform deep over a fixed list and cannot be complete; and the parse-path test covers what a loader returns on bad input, not a real stack overflow, because the depth that overflows also destabilises neighbouring test files (measured: 20000 levels parse fine in 2.8s, so an earlier draft of that test was passing for an unrelated reason).

## /n8-exec M1 — 2026-09-21 (ninth fix pass; round nine's eight findings)

- **Corrections to the two ledger lines round nine convicted (#218).** Line 709 — *"key links and step sets … derived from the files rather than named per-file"* — was never corrected by #211 and is still false of the code: both are hand-named literals. What the eighth pass actually built is different and weaker-sounding but real: the step-set map is **closed against the directory**, so a new workflow or job fails until it is written down. Line 737 — my own *"Both now do what they said"* — flattens "achieves the property by a different mechanism" into "does what it said". The key-link half is fine (`_propagationCommands` returns a `Set`, so `contains` there is element equality); the step-set half is not derived and its comment now says so.
- **And one in PR #214's body:** *"covers ALL 27 run-bodied steps"*. The map lists 27 and the closure assertion is real, but nine steps are declared `[]` and a `[]` step is never executed — real coverage was 18/27, and seven of the nine were guarded by nothing (#216).
- **The measurement that was right and the generalisation that was not.** The eighth pass recorded, as an honest limit, that the depth needed to overflow the YAML loader destabilises neighbouring test files. I had measured 2 000 / 5 000 / 10 000 / 20 000, seen no overflow, and stopped. 32 000 overflows reliably in ten seconds with the suite green. That false limit is exactly what left the sixth bypass of the #177 lineage open (#217) — a limitation asserted from the range I happened to test is the same defect as a capability asserted from a range I did not.
- **Decision (Rule 2):** `tools/make_upload_key.sh` now enforces a 12-character minimum on `HS_KEYSTORE_PASS`. The leak scan searches transformed forms only for values of 8+ characters, so a short password was searched verbatim only and a base64 copy of it would not be found. Enforcing the length at the one place a keystore is created makes the guard's assumption true rather than hopeful. Boundary verified: 11 → exit 2, 12 → exit 0.
- **Decision (Rule 4 — filed, not half-done, as #222):** scoping the chokepoint rule across `test/guards/` is correct and I implemented it; it surfaced 20 raw process starts in six files, including `signing_guard_test.dart`, which runs real `flutter build` invocations with the `HS_*` signing variables bound. Routing those through a shared chokepoint is a refactor across six files, and the alternative available in the time — writing twenty `chokepoint-exempt:` reasons — is precisely the self-granted exemption this same pass tightened against. The scope stays, the limit is recorded in the code, and the enumerated list is on the issue.
- **Two exemptions written honestly rather than assumed:** `ci_version_test.dart` and `play_release_codes_test.dart` run project scripts with plain arguments and no secret in play; each now carries a marker saying so.
- **The guard over the guards, narrowly.** #211 proposed one and it was never built, which is why every instance below its six named ones was still live. The tractable version is not a general claim-checker: it is a test that CLAUDE.md's invariant-3 exemption list matches the dependencies that actually lack a `# why:` line. That is the one CLAUDE.md claim a machine can settle, and the worst instance found this round was in that sentence.

## /n8-exec M1 — 2026-09-22 (tenth fix pass; round ten's seven findings)

- **The organising principle, and it is the eighth pass's lesson applied to the code being written rather than the code being fixed:** every new guard carries a positive control. #224, #225 and #226 were one defect — a test written without asserting its own precondition, so it could not tell "the property holds" from "the body never ran". Each now asserts the precondition: the files exist before the destroy step runs; the secret-bearing body completes with all secrets equal; the honesty step completes before its output is read.
- **Decision reversed, then reversed back, and the record says why (#228).** The seventh pass declined admin scope for CI. The ninth found the rulesets endpoint public and called that decision's premise false. The tenth granted `administration: read` to make `bypass_actors` readable — **and that key does not exist for `GITHUB_TOKEN`.** The workflow failed validation with zero jobs; the required-check binding refused the merge. Verified against the documentation only after CI failed. The seventh-pass decision was right about the trade (an admin credential in CI is a larger surface than the gap) and wrong only about the endpoint; the tenth got the endpoint right and the grant wrong. Reading that field needs an admin PAT secret — owner's call, options on the issue. The guard skips visibly instead.
- **Two claims of mine convicted by CI itself this pass, not by a verifier:** "CI asserts the field is PRESENT" (the field cannot be read there) and "one line to revert if you'd rather not grant it" (the line was invalid, not optional). Both were in the PR body and the code before either was tested.
- **Decision (Rule 1 — own bugs, found by the battery):** three entries invalidated by my own edits — two `#182` anchors broken by the token `env:` block, and a `#220` mutation that reverted a fix without supplying the defect it prevents, so nothing changed and it survived. Same mistake as the `#203`/`#207` entries two passes ago; now a two-edit `chain()`.
- **Process error, twice:** `git checkout -- .` to undo a probe wiped uncommitted work on #224 and again on #227. The exec discipline's snapshot rule exists for this. Committing before probing from here on.
- **Not attempted, deliberately:** #217 (needs the `ulimit -s` subprocess design) and #222 (a chokepoint refactor across six files). Both are real pieces of work rather than fixes, and this pass has shown what happens when I do real pieces of work at the end of a long pass.

## /n8-exec M1 — 2026-09-22 (eleventh fix pass; round eleven's findings)

- **The organising fact: the positive-control rule held, the prose did not.** Round eleven confirmed vacuity did not recur anywhere the tenth pass applied its rule, and found seven comments claiming mechanisms the code lacked (#233). So this pass makes the rule checkable and puts it where it outlives the pass: CLAUDE.md now says a comment may say *why*, and what the code does *now* goes in an assertion's `reason:`, which is executed. Every one of #233's seven would have needed an `expect` to exist.
- **Decision (#226, the "better still"):** the `[]` rationale is no longer prose. `_dependsOn` defines `[]` once — the step runs no command the propagation check can stub — and `every [] step is exercised by a named test` asserts the `[]` set equals the union of the honesty, destroys and pre-flight specs. Doing that surfaced two steps no issue had named: play-promote's `refuse` (the production refusal) and its `summary` (#130's "Promoted on Play" line). Both were run by nothing; both have cases now, including the refusal's positive control (`internal -> alpha` must pass).
- **Decision (#226, `name_failure`):** the harness gained `expressions:` so a test can supply what `${{ toJSON(steps) }}` would hold. The comment that said "what can be asserted is that it still LOOKS" described an assertion that did not exist; the real one — the diagnostic names the failed step and not the others, and says nothing when nothing failed — replaces it. Text assertions on the body were the alternative and #205 says no.
- **Decision (#232):** succeeding stubs for `base64` and `sha256sum` exec the real binary. Two consequences the faithful stub forced, both recorded because they are the lesson: the leak test's sentinels had to move into the base64 alphabet (a real `base64 -d` rejected `HS-SENTINEL-…` and the keystore step failed before the line that would leak), and the `gh` stub had to actually leave a download behind (a real `sha256sum` failed the `asset` step for want of a file — the echo stub had been hiding that `gh` "downloaded" nothing). A stub faithful in one place exposes the stubs that are not.
- **Decision (#217) — the design changed once more, on measurement.** `ulimit -s` was the recorded plan; the Dart VM ignores it (64000 frames at every limit from 256K to unlimited). What the same probe showed is that a **worker isolate's** stack is a VM constant eight times smaller than the main isolate's: 4000 levels of nesting overflow the loader there in ~80 ms. The guard runs every parse in `Isolate.run`, finds the depth by doubling until `Workflow.parse` itself reports the overflow, and hands each rule a document twice that deep. Cheap on both machines, machine-independent for the right reason, and the `slow` tag stays unused. Two mutations: the round-nine bypass (catches `YamlException`, not `Error`) and #177's crash verbatim (the handler deleted).
- **Decision (#230 item 8, Rule 1):** `make_upload_key.sh` gains the `cd` two of its comments described. Without it `CERT_OUT`'s overwrite refusal checked the caller's directory, so the committed certificate was unprotected from anywhere but the repository root. A test runs the script from a scratch directory and requires the refusal by name.
- **#230 item 3:** `_addSentinel`'s floor is eight, matching `_leakForms`; the boundary is tested (seven refused, eight accepted). All existing fixtures were already eight or longer.
- **Housekeeping from #229/#233:** the `_runnerCredentials` docstring is attached to `_runnerCredentials` and says "planting only; drift detected by the precondition, not prevented"; the honesty header no longer counts; the `~1` sentence names both reporters; the three-way count of raw process starts is gone in favour of #222's list; the two `#219` markers are distinct.
- **Process:** committed before every probe this pass. No `git checkout -- .`.

## /n8-exec M1 — 2026-09-22 (twelfth pass; two owner decisions after round eleven)

- **Decision reversed a third time, this time by the owner (#228).** The seventh pass declined admin scope for CI; the tenth granted a key that does not exist; the owner has now minted a fine-grained PAT with repository *Administration: read-only* on `HonestSudoku` alone and stored it as `HS_RULESET_READ_TOKEN`. `ci.yml` hands it to the three guard runs in place of `github.token`, with `HS_RULESET_READ_EXPECTED=1` beside it so that an absent `bypass_actors` with the token present is **red, not a skip** — a lapsed secret must be loud on a required check. The branch itself moved into `_bypassVerdict`, a predicate with its own test and two mutations, because the network test can only reach it in CI and the battery runs everywhere. Rotation is the standing cost; a 401 names the secret to rotate.
- **#222 converted to a spike, owner's words:** *"I want to finish it. We can convert it to a spike to research it first rather than wasting rounds of implementation."* `bug`/`sev:medium` removed, `spike` added; the brief on the issue asks for one comment — a single counted inventory, the helper's contract, an answer per hard case, the exemption mechanism, the mutations, a cost — and no merged code. The unscanned process starts are unchanged until the story it produces lands.

## /n8-exec M1 — 2026-09-22 (thirteenth pass; round twelve's six findings)

- **Corrections to this ledger's own eleventh- and twelfth-pass entries, which round twelve convicted (#239).**
  - *"`ulimit -s` does not help; the VM ignores it (measured: 64000 frames at every limit from 256K to unlimited)"* — measured under `dart run`, and generalised to the wrong thing. Under `flutter test` the MAIN isolate's depth tracks the limit (`ulimit -s 256` → overflows at 1000; `65520` → no overflow at 128000). What is constant is the WORKER isolate's, which is the one the guard uses — so the design is right and the sentence was not. Same mistake as the eighth pass's "honest limit": a generalisation from the range I happened to measure.
  - *"surfaced two steps no issue had named: play-promote's `refuse` and its `summary`"* — #216's body names both. And *"run by nothing at all"* is true of `summary` only: `play_promote_args_test.dart` runs `refuse`'s real body and asserts its exit codes. What #226 added for `refuse` is the question about what it SAYS.
- **Decision (#238, and it grew).** The two `#217` markers were vacuous because `'overflow'` is part of that test's name. Rather than fix two strings, the battery now audits every marker before it mutates anything: one suite run through the json reporter, which must be green, and no selected marker may be part of any test's name. It found vacuous markers throughout the file — `'destroys'`, `'ruleset'`, `'refusal'`, `'command line'`, and four that were a test's name verbatim — all of which scored `caught` for any red suite whatever. Each was replaced with a prefix of the reason the assertion actually prints, taken from that mutation's own failure output rather than from reading. *(A count stood here and was wrong twice over; it is cut rather than corrected, because it can be computed. Cut on 2026-09-22. *(The sixteenth pass replaced the command that stood here, which did not run — it referenced a module that was never written and contained a literal `...`. What does run, verified:*
```sh
for r in <old> <new>; do git show $r:tools/mutation_check.py > /tmp/mc_$r.py; done
python3 - <<'PY'
import importlib.util, sys
def load(tag):
    spec = importlib.util.spec_from_file_location(tag, f"/tmp/mc_{tag}.py")
    m = importlib.util.module_from_spec(spec); sys.modules[tag] = m
    spec.loader.exec_module(m); return {(x.issue, x.name): x.expect for x in m.MUTATIONS}
a, b = load("<old>"), load("<new>")
ch = [k for k in a if k in b and a[k] != b[k]]
print(len(ch), "entries;", len({a[k] for k in ch}), "distinct markers")
PY
```
*)*
  **And a correction to my own plan for it, made while building it:** the first version audited the markers against the *printed output* of a green run, which is machine-dependent. Measured 2026-09-22 (`flutter test --no-pub --tags guard` piped to a file): no CR bytes; the longest line moves with the tree and the checkout path — 199 characters one day, 205 another, with a name visibly cut in one run and whole in the next. *(Corrected in the sixteenth pass: the fifteenth said it had corrected this "in place" and corrected only the copy in `tools/mutation_check.py`. There is no fixed cap; the cap is a property of the environment, which is the better argument for reading the json stream.)* It audits the json stream instead. *(Corrected in the fourteenth pass: the sentence here named the compact reporter and claimed CI's does not truncate. The conclusion held; the mechanism did not — and auditing names alone missed what a test PRINTS, which is #244.)*
- **Decision (#237, correcting the issue I filed).** A control cannot be protected by mutating the control: that makes the suite greener, so the entry SURVIVES by construction. What protects one is a defect nothing else catches — `refuse` printing its refusal and then exiting 0, `secrets_present` that can never succeed. Two entries. The sweep found **two** of the five controls already had such an entry (#204's and #224's). *(Corrected in the fourteenth pass, twice over: this said three, and it said the leak test's control **cannot** have one. It can — `secrets_present` is a `[]` step, which the propagation check never runs, so an inverted copy of `keystore_check`'s own comparison is named by that control and by nothing else. The entry is in the battery now, #245.)*
- **Decision (#240, and the residue is stated).** `_bypassVerdict` takes the environment map, so the key and the comparison are inside the tested function; ci.yml's guard env is pinned structurally through `Workflow.parse`, closed against the files; the summary honesty case requires the real digest of the planted bundle; and a `_runReal` command the host lacks now fails the harness instead of falling back to an echo. **What is left, and no mutation is added for it:** the one line passing `Platform.environment` into the verdict cannot be exercised in-process, and a SURVIVED entry would turn the battery red to document a hole rather than to catch one.
- **Decision (#241 item 3, which I had left as the owner's call and am taking):** `HS_RULESET_READ_TOKEN` stays on the `mutations` job. Read-only, one repository, one permission. *(Narrowed in the fourteenth pass, and corrected again in the fifteenth: what it buys is one live `bypass_actors` read **per entry** — the battery runs the suite once per mutation, so it is over a hundred reads per battery run, which is what `ci.yml`'s own comment beside the token already said. The sentence here said "every mutation reaching it would be scored against a test that stopped early", which is false — the bypass block is the last statement of that test, so #202's three and #219's two all fire before it, and #228's two target the predicate and need no token at all.)*
- **Rule 1 (own defect, found by the fix for another):** `_collectWorkspaceLeaks` had the same UTF-8 swallow as the `wrote` channel — its sibling scan learned this in #200 and it did not. Fixed with its own mutation.
- **The digest shape stays open, recorded where it bites:** hashing a secret into a summary is a real leak for a human-chosen password. *(Corrected in the fourteenth pass: the reason given here — that catching it needs a dependency — was wrong. The harness already runs the host's real `sha256sum` through `_runReal`, so the shape costs no dependency; what it costs is one more form per secret in a scan that runs over every step of every workflow, and that is the only reason it is still open.)*

## /n8-exec M1 — 2026-09-22 (fourteenth pass; round thirteen's five findings)

- **Corrections to the thirteenth pass's own entry are written into it above**, in place, each marked as a fourteenth-pass correction: the marker count (cut, with the command that computes it), the reporter mechanism (replaced by what was measured, dated), "three of the five controls" (two), "the leak control cannot have a mutation" (it can, and does now), the sha256-dependency reason (the harness already runs the host's `sha256sum`), and the PAT reasoning (narrowed to the one live read it buys). A correction comment also went on **#217**, because that issue's last word was the `dart run` measurement and a reader of the issue would otherwise quote it.
- **Decision (#243).** The `wrote` channel's exclusions are by **content identity**, not by path shape: the harness records the exact text of every file it writes — each stub, the script, each planted input — and skips a file only while its bytes still match. Three holes closed at once, each verified by hand: a secret written into `$GITHUB_WORKSPACE/bin/`, the script overwritten under its own feet, and a lie appended to a planted file. The loop's comment ("Everything the body WROTE") is true for the first time.
- **Decision (#244), and it is the same shape as #238 one level out.** The marker audit checked test *names*; a marker is vacuous if it is in a green run's output for **any** reason. Two more sources are covered now: what a test **prints** (read from the json stream's `print` events — this is how `'permissions:'` shipped, matching `release-no-permissions:` from `permissions_guard_test.dart`), and **the mutation's own inserted text**, checked per entry at apply time, which no baseline run can show. Both proven by probe: reverting the marker makes the audit refuse, and a marker matching the insertion reports BROKEN.
- **Decision (#245), reversing round thirteen's "none possible".** `secrets_present` is a `[]` step, so the propagation check never runs it and the pre-flight test runs it with distinct values — an inverted copy of `keystore_check`'s comparison is therefore named by the leak control and by nothing else. That mutation is in the battery. The two comments claiming "these two survive" are corrected to what the battery actually reports, which is WRONG-REASON.
- **Decision (#240's residue, closed rather than carried).** A child process is the one thing that can set an environment a test cannot: `the flag the workflow sets is the flag the guard reads` runs the ruleset test with `HS_RULESET_READ_EXPECTED=1` and both tokens stripped, and requires the lapse failure. It is the **first test to carry the `slow` tag**, three passes after that machinery was kept "for the next expensive guard"; its mutation sets `slow=True`. Measured at about 2s because the child reuses the parent's build; the tag is for the multiplier, not that number.
- **Process error, third occurrence of the same class:** `git checkout -- .` during a probe wiped the uncommitted child test and its mutation. The rule from the tenth pass — commit before probing — was followed for every other probe this pass and not for that one. Re-applied and committed before the next probe.

## /n8-release 0.1.0 — 2026-09-22

- **Shipped.** `v0.1.0` at `cf5c85b`, release <https://github.com/honestarcade/HonestSudoku/releases/tag/v0.1.0>, run 35792999147. Version name `0.1.0` from the tag, version code `1021` from the run number and attempt. Bundle `app-release.aab` (44,138,243 bytes) and its `.sha256` (`e056852917f8870af0f8d0e4d0a91ddf911f11daa2459b6d9bd324c0cbd804c1`) attached to the release; uploaded to the Play **internal** track. Milestones included: M0 and M1's work, which is all of `main` to that point.
- **Invariant 1, proven on the artifact rather than in a document:** the scan step printed `no permissions declared (package com.honestarcade.sudoku)` against the bundle that was then uploaded.
- **Promote:** run 35797055235, `internal -> alpha accepted`, then `promoted=1021 / from=internal / to=alpha / status=draft`. The Play API first refused the commit with `400 Only releases with status draft may be created on draft app`, and the script's draft-app branch — the one #129 was filed to make specific rather than firing on any failure — retried the same version codes as a draft. So the build did move to closed testing, as a draft release, because the app has never been published. That is the Play constraint the M7 plan already records, not a defect.
- **The first attempt failed, and the cause was filed hours earlier at the wrong severity.** `v0.1.0` was first tagged at `770db04`; run 35783678379's `gate / mutations` job ran **45m22s** against `timeout-minutes: 45`, was cancelled, and `ship` never started — so nothing shipped and nothing was enrolled. That is #252, which this same day's verification filed as `sev:low` with the words *"operational, not a defect in a guard"*. It is the only open bug that could stop a release and it stopped one on the next run; raised to `sev:high`, fixed by `timeout-minutes: 60` in #254.
  Four measurements at 127 entries — 42m52s, 45m22s, 44m22s, and 45m01s on the successful release run — put the old limit inside the noise band. **The successful release would also have been cancelled at 45.** Raising the ceiling buys time and does not change the slope (~20s per entry); the next answer is to split the battery across jobs, which #252 carries.
- **Decision (owner, this session):** the empty `v0.1.0` release and tag were **deleted and re-cut** at `cf5c85b` rather than left as a record of the failed attempt or superseded by `v0.1.1`. The deleted release had zero assets and nothing had consumed the tag, so nothing was lost, and the first release is now the one that actually shipped. Recorded here because deleting a published tag is outward-facing and the reasoning should outlive the conversation.
- **Decision (owner, this session):** `pubspec.yaml` was bumped `1.0.0+1` → `0.1.0+1` through the normal gate (#253) before tagging. The shipped artifact never depended on it — `release.yml` passes `--build-name` from the tag — but a local build claiming `1.0.0` while the tag says `0.1.0` is the small lie `/n8-release` warns about.
- **What this does not prove.** The bundle is on Play's internal track and promoted to alpha as a draft; nobody has installed it, and no store listing, data-safety form or content rating exists. Those are M7. The release also does not close M1: its verification carries four medium findings (#249-#252 — #252 now fixed) and the milestone's own closure needs `/n8-verify` to see outcomes 4-7 and 10 proven by these two runs.

## /n8-exec M1 — 2026-09-22 (fifteenth pass; the release's own findings)

- **Decision (#256), and it is the one that mattered.** The draft-app retry had worked in production hours earlier and was guarded by nothing: making `is_draft_app_rule` return 0 unconditionally — which is #129 verbatim, "a permission denial reported as a success" — left the whole suite green. Two tests now drive the edits flow with a stub `curl` that records every call, so "retried, exactly two commit attempts" and "not retried, exactly one" are counts rather than inferences. **The matcher itself was left alone, deliberately**: the issue reported that its loose `"draft app"` substring would report a 403 as success, and I could not reproduce that — the draft retry is refused too and the script exits 5. Narrowing a match that worked against a demonstrated harm of zero is the trade this project has learned not to make; the guard is what was missing.
- **Decision (#249).** The `wrote` channel reads the **name** of every file and directory as well as its bytes. `upload-artifact` publishes paths, so `touch "$GITHUB_WORKSPACE/$HS_KEYSTORE_B64"` was a published secret that the channel — which used the path only as a map key — could not see. Both spellings probed, mutation added.
- **Decision (#250).** The marker audit gains the runner's own output as a source: the suite paths from the same json stream, plus the fixed lines the reporter emits. A marker naming an unrelated test file had passed the audit and scored `caught`. `printOnFailure` and double-quoted literals join the source sweep, since its text lands in the output exactly when the suite is red.
- **Decision (#258), and it is the durable half of this pass.** `.n8/memory/play-console.md` says in bold that credentials are never stored there, and nothing asserted it. `memory_guard_test.dart` now does, with a positive control that the glob matched something. **My first version was green on the shape this project would actually paste** — `HS_KEYSTORE_PASS: …`, because an underscore is a word character and `\bpass\b` never matches inside it. Found by probing my own guard rather than by trusting it; both spellings now fire.
- **Decision (#257): the cancelled-gate gap is accepted in writing, not closed.** Run 35783678379 settled a comment that called itself untested: a cancelled gate skips `report-gate-failure` and announces nothing. `if: always()` does not help — GitHub skips a dependent job of a cancelled one rather than evaluating its condition — and the notifier that would work keys on `workflow_run`, which is new infrastructure on the release path and a Rule 4 change. Nothing ships, and the cancellation is visible in the Actions list; what it costs is that nobody is told. The comment and its ledger twin now say that instead of "nobody has tested this".
- **#258's re-tag rule, narrowed with its precedent.** `README.md` said "never re-tag a version" absolutely; this session re-cut `v0.1.0` after the first attempt was cancelled, with the owner's approval and after checking the release held no assets. The rule now says "never re-tag a version **that shipped**", and names the two checks — no assets on the release, `ship` skipped — that distinguish the cases.
- **Corrections to the fourteenth pass's entry, in place:** the "capped near 198" measurement (re-measured at 205 in the same checkout, so the cap is a property of the environment rather than a number), the missing command behind a cut count, "one live read per battery run" (it is one per entry), and the two `slow`-tag sentences that this project's own new test had falsified.

## /n8-exec M1 — 2026-09-23 (sixteenth pass; round sixteen's five findings)

- **Decision reversed (#260), and it was mine to reverse.** The fifteenth pass left `is_draft_app_rule` loose, on the reasoning that a wording change would break the path that had just worked in production, and recorded that I "could not reproduce" the false-success the verifier reported. That reasoning was tested against a **persistent** 403 only. With a **transient** one — first commit refused with a message mentioning a draft app, retry accepted — the script exited 0 with `status=draft`: a permission denial reported as a success, which is #129 in its own words. The matcher now requires a 4xx **and** the phrase `only releases with status draft`. A wording change makes the retry stop firing, which dies loudly; the loose match made it succeed wrongly, which is silent. Loud beats silent, and I had the trade backwards.
- **Decision (#260, second half).** The stub records request **bodies**, so the tests read what the retry sent rather than inferring it: a retry that promoted `completed`, and one that committed without PUTting anything, were both green. Two mutations.
- **Decision (#261): the tag-path cancellation is fixed, not documented.** `release.yml` declares `cancel-in-progress: false`, but the gate that does its work runs in `ci.yml`'s group, which cancelled in progress on every ref. Re-pushing a tag while its release ran would have cancelled the release's own gate — one keystroke from what this session did when it deleted and re-cut `v0.1.0`. `ci.yml` now cancels only when the ref is not a tag, and the value is asserted.
- **Decision (#261): values, not keys.** The workflow model carries the concurrency group, `cancel-in-progress`, and the permissions map at workflow and job level; a new test pins all four workflows by equality and allows exactly one job (`ship`) a wider grant. Every Flutter setup must read `.fvmrc` — which the coverage map already claimed was guarded, so the guard was written rather than the claim amended.
- **Decision (#263): the shapes widen and the claim narrows to meet them.** `secret_shapes.dart` is shared by the memory scan and now `README.md`; the base64 floor drops to 32 with a base64url alternative, hex is checked before base64 (it could never fire otherwise), prose and URL-embedded credentials are covered, and the assignment rule requires a credential-shaped value so ordinary prose stops firing. **Two corrections found by probing my own guard:** lowering the floor made ordinary file paths match until the pattern required a digit and both cases, and the service account's public key ID is a genuine 40-character hex run — it now carries a `not-a-secret:` declaration with a reason, rather than the pattern being weakened to let it through. `play-console.md` states which shapes are covered instead of saying the claim is "asserted".
- **Decision (#264): the ledger stops pretending its numbers are current.** Five passes corrected counts in this file and each shipped a new wrong one. The header now says what the file is — a dated narrative whose numbers are as of writing — and names the commands that answer the current question. `CLAUDE.md` keeps the rule and drops its own tally, which is exactly the kind of number the clause beside it says to cut, and says plainly that the only mechanism with a track record is moving a claim into something executed.
- **Own error, caught by the battery:** the "commits without promoting" mutation was malformed shell — an `if` with no `fi` — so it broke the script's parse and reported WRONG-REASON rather than exercising the guard. Rewritten as a deletion of the PUT block.

## /n8-exec M1 (seventeenth pass) — 2026-09-23

- **Decision (#266): the exact-phrase narrowing from #260 gets its own test and mutation.** Round-seventeen verification found the fix correct but unguarded — nothing distinguished the required phrase from a bare "draft" substring. Added a test case supplying a 4xx refusal that mentions "draft" without the exact phrase, asserting the retry does not fire; confirmed it fails against the pre-fix (bare-substring) shape and passes against the shipped fix, per test-plan discipline. Added a matching mutation entry to `tools/mutation_check.py`.
  **Issue:** #266

## /n8-replan (all planned-but-unexecuted: M2–M8) — 2026-09-23

Scope: M2 through M7 (planned, unexecuted) plus M8 (Audit, storyless, description-only check). Triggered by the user: "audit our decisions and make sure none are relevant anymore" — a check of all eight unreconciled `## Ad-hoc` entries against the current plan and codebase before M2 execution starts.

- **Ledger entries 1–8** (2026-09-18 through 2026-09-21): all reconciled. Seven were already self-declared non-stale for anything beyond M0/M1 (closed milestones) or already reflected in the amended issue/milestone-description text they named (M7's item 23 carries the exact amendment the 2026-09-19 entry describes). None required a story edit.
- **#205 closed** ("execute the artefact" architecture proposal): the decision was made and fully carried out across M1's sixth through seventeenth fix passes, all logged in this file — the issue itself was just never closed when the decision landed. Closed as completed, citing the rounds that implemented it. Does not touch M2–M7: the change is scoped to `test/guards/` (area:ci), not the game code those milestones build.
- **Spot-checked M2's engine story (#22) and M4's persistence/about-links stories** against current codebase reality: every concrete claim (file paths, `lib/links.dart`, `test/guards/repo_files.dart`, `.fvmrc`, pubspec dependency ranges, invariant guard numbers `#14`/`#15`/`#26`) still matches. No stale "how" or "what" found in either.
- **One entry (2026-09-20, "project goal: reusable basis") named a real gap, deferred by its own text** until M1 verifies — which happened this session. Asked the owner rather than deciding unilaterally: creating a new milestone is a roadmap-level scope call. See the owner's answer, logged separately once given.

No story rewrites, no closures beyond #205, no re-wired dependencies. The plan for M2–M7 is trustworthy as written.

## Owner decision — 2026-09-23: M1a created, the reusable-basis gap resolved

- **Decision:** the owner's answer to the reusable-basis gap flagged by the 2026-09-20 ad-hoc entry and this session's replan: extract now, before M2, as a new milestone **M1a: Reusable app template**, into a **new separate repository** (`android-studio-app-template`, owner-created). Scope: the CI/guard machinery **and** the Play Console launch runbook — not the Flutter game scaffolding itself.
  **Owner's words:** *"let's make an M1a for this. I want to extract the reusable parts now before developing the game."* … *"I want it to get me to a very solid starting point for any apps that use android studio and flutter. I plan to make several apps/games this way. I want this starter template to include the play console steps that I have to do, and setup needed. So that after starting from the template and doing documented steps, we can move right into game development without spending time on this infra/CI stuff every app."*
  **Created:** milestone #10 (M1a), epic #273, five stories (#274–#278: guard machinery, CI/CD + n8SDLC scaffolding, README setup runbook, Play Console runbook, end-to-end proof against a placeholder app).
  **Blocked on:** the owner creating the empty `android-studio-app-template` repository. Execution cannot start until it exists.

## /n8-exec M1a — 2026-09-23

- **Decision:** all five stories (#274-278) executed in one continuous pass rather than
  story-by-story with separate commits/PRs, because the deliverable is a single coherent
  repository where each piece needed the others to be genuinely testable (S1's guards need
  S5's placeholder app to run against; S2's workflows need S1's tools to call). Commits in
  `android-studio-app-template` are still one-per-logical-change, and each story's completion
  comment cites the exact commit/PR that closes it.
  **Issue:** #273 (epic), #274-278
- **Decision:** two placeholder-genericization bugs were found only by a real CI run on a
  real PR, after every local check had passed — `tools/mutation_check.py`'s lost executable
  bit, and `tools/check_aab.sh`'s `APP_PACKAGE_ID` fallback not matching the actual scaffold
  package id. Both fixed in the same PR, re-verified green, merged. Logged because it's the
  same lesson this project's own history keeps teaching: a local pass is not a green run
  until something that isn't the author's own machine has checked it.
  **Issue:** #278
- **Decision:** branch-protection (ruleset or classic) could not be configured on
  `android-studio-app-template` — GitHub returns 403 "Upgrade to GitHub Pro or make this
  repository public" for both APIs on a private repo under a personal account. Documented in
  the template's own README rather than worked around; the PR gate itself still runs and
  reports red/green correctly, it just isn't yet a hard merge requirement.
  **Issue:** #278
- **Decision:** stories closed with evidence and epic #273 / milestone M1a left open for
  `/n8-verify M1a` — matching this session's own established discipline (M0, M1) that
  execution does not close what it built.
  **Issue:** #273

## Plan verification, M2-M5 — 2026-09-23

Triggered by the owner: "verify the plan again... solid enough that I can execute them all
without my intervention." Four fresh `general-purpose` subagents (never `fork`), one per
milestone, ran `/n8-plan`'s own executor-simulation discipline against all 36 already-planned
stories in M2-M5 -- not creating anything, just checking whether the plan itself would stall
an autonomous executor or lead it to guess wrong.

- **The one real, consequential finding (#26, M2):** the new engine property-test guard tier
  (up to ~3 minutes, tagged plain `guard`) would join `tools/mutation_check.py`'s per-mutation
  `SUITE`, which runs the whole non-slow guard suite once for every one of 130+ mutation
  entries -- multiplying the mutations job's runtime by roughly an order of magnitude and very
  plausibly recreating #252 (a battery timeout that cancelled a release). Nothing in #26's
  three prior discretion passes analyzed this. Fixed by amending #26 directly: a new AC
  requires measuring the actual battery runtime with the new guards in place before the story
  is considered done, and a new Discretion note names the established fix (the same `slow`-tag
  mechanism already used for one other expensive test) as the default resolution rather than
  inventing a new one.
- **Two smaller real gaps, fixed the same way:** #31 (M3) didn't say whether the "paper" board
  theme restyles only the grid or the whole screen's chrome, and four downstream stories
  (#32-#35) already hardcode chrome colours assuming it doesn't -- added a note requiring this
  be confirmed against the design source before #31 is built. #39 (M4) never stated whether its
  `startNew()` routes through M3 #30's `GameState.newDeal()`/`SeedSource` no-repeat guarantee,
  or silently drops it -- added a note requiring the former.
- **Two cosmetic doc-drift items fixed in passing:** M2's milestone description stated a stale,
  superseded seed-count figure (200/200/50/10) alongside the correct, current one
  (200/200/40/5) that both stories actually use -- corrected. #46 (M4)'s dependency prose
  under-stated its own real GitHub dependency graph by one story (#45) -- corrected; the actual
  enforced graph was never wrong, only the prose describing it.
- **M3 and M5 needed no changes.** M3's nine stories and M5's eleven stories were independently
  verified clean -- no (a)-class gap, correct dependency graphs, no stale claims against either
  the current codebase or each other's planned artifacts. M5 in particular had already been
  through an equivalent audit of its own during planning (a first pass, a second pass, and a
  coverage check, all visible in its issues) and this pass found nothing that process missed.

**Overall:** all four milestones' plans are now assessed as solid enough for unattended
execution. The M2 finding was the one that mattered -- a systemic CI-timing risk that would
have surfaced expensively (a cancelled required check, mid-milestone) rather than being caught
by reading a single story in isolation, which is exactly why this pass ran per-milestone rather
than per-story.

## /n8-exec M2 — 2026-09-23

- **Decision:** The design file is read through the `DesignSync` tool's read methods (`list_files`, `get_file`) on project `9e9471c9-5231-4fd8-9889-066345073295`, at the owner's direction in this session ("You should be able to access everything you need from the mcp"). The planning passes read it through a design connection this session does not have. The copy used is `Honest Sudoku.dc.html`, sha256 `f2592eb5dda759413e9266e4ec574085c7262fb38aa28cbef9fd8e3555b585ee`, fetched 2026-09-23 (`shasum -a 256` on the saved file). It is kept outside the repository because its `<link>` to fonts.googleapis.com would put a web-font reference into the tree that invariant 1's guard forbids.
  **Why:** M3–M5's stories cite values only the file holds (THEMES, verbatim copy, paddings), and #23 pins against the design's own JavaScript.
  **Issue:** #22 (first story run), all of M2–M5
- **Decision:** `stripDartComments` joins `repo_files.dart`, and the engine rules live in a new `test/guards/engine_rules.dart` beside `engine_imports_test.dart`, following the pure-rule/inline-fixture split `dependency_rules.dart` and `workflow_rules.dart` already use.
  **Why:** #22's Discretion asks for pure rule functions; a separate rules file is the pattern the guard directory already has.
  **Issue:** #22
- **Decision (Rule 3):** The solver also branches on a unit's missing value when that value has fewer places left than the most-constrained cell has candidates, and treats a missing value with no place as a dead end (exact-cover column choice). Most-constrained-cell ordering is kept, as #22 specifies.
  **Why:** #23's carve to uniqueness on 16×16 did not finish: 176 of 256 cells visited after 40 s, with each check slower than the last (local probe, 2026-09-23, `dart` on the engine against seeds 1–3). With the added branching the same carves took 1118, 1163 and 1591 ms. 9×9 carves gave the same given counts before and after (26/23/21 for seeds 1–3), as expected, since the change alters the search order and not the count.
  **Issue:** #23 (blocker), amends #22's solver
- **Decision:** The golden hash is printed as two zero-padded 32-bit halves.
  **Why:** `int.toUnsigned(64)` on the VM returns a signed value, so the first recording produced hashes with a leading `-`. The published FNV-1a vectors (`''` → `cbf29ce484222325`, `'a'` → `af63dc4c8601ec8c`) are asserted in the test.
  **Issue:** #23
- **Decision (owner review requested):** `supportedDifficulties` is 4×4 → Easy only and 6×6 → Easy, Medium, Hard, narrower than #25's AC table (4×4 Easy–Hard, 6×6 Easy–Expert, taken from the design's statistics breakdown).
  **Why:** The AC also requires that a band be proven by the grader, and the grader cannot prove these three pairs:
  - *4×4:* every one of the 4 618 710 unique 4×4 boards with at least the design's floor of 6 givens, over 95 distinct full grids, falls to naked singles alone (exhaustive enumeration, local `dart` probe, 2026-09-23). A 4×4 Medium or Hard board does not exist on this ladder.
  - *6×6 Expert:* 0 of 20 000 minimal 6×6 carves needed a triple or an X-wing, and 0 of 5 000 attempts of the specified carve-to-band reached Expert (same probe).
  - *The alternatives,* labelling by givens count or keeping pairs that always fail, contradict the owner's own calls on #25 ("technique-graded", "unsupported pairs unavailable").

  `test/engine/difficulty_test.dart` carries a one-grid exhaustive 4×4 check and a 2 000-carve 6×6 check, so the evidence is executed rather than asserted. The pairs that stay out are greyed on the setup screen by M4 #41's existing mechanism. Reversing this is one table and its test.
  **Issue:** #25; affects M4 #41 (setup greying), #43 (statistics breakdown rows)
- **Decision:** `maxAttempts` (Claude's Discretion) is 50 for 4×4, 10 000 for 6×6, 2 000 for 9×9 and 200 for 16×16, not the planner's 50/50/50/200.
  **Why:** Measured success per attempt of the specified carve (local probe, 2026-09-23):
  - 6×6 Medium 23/5000 and Hard 8/5000, at 0.2 ms per attempt;
  - 9×9 Expert 14/2000, at 1.8 ms per attempt.

  At 50 attempts, 3 of 5 9×9 Expert seeds and 4 of 5 6×6 Medium and Hard seeds failed. With the new limits all 20 seeds of every supported pair succeed, the 9×9 Expert median is 151 ms and 6×6 Hard 67 ms, and the chance of running out falls below roughly 1e-6 at the measured rates. A carve-then-fill-back strategy was measured too and was no better (9×9 Expert 12/2000).
  **Issue:** #25
- **Decision:** Each retry's progress takes half of the carving span still unused, instead of an equal slice of `maxAttempts`.
  **Why:** With 10 000 attempts, equal slices would leave the loading bar frozen at 45 % for the whole search.
  **Issue:** #25, #27
- **Decision:** When nothing on the ladder applies, the grader confirms a solution exists (`countSolutions(limit: 1)`) instead of calling `solve()`.
  **Why:** `solve()` must rule out a second solution, which on a sparse 16×16 took about 3 s per grade. The ladder itself took 12 ms. A minimal 16×16 carve plus grade fell from about 4.3 s to about 1.4 s (local probe). The generator has already proved uniqueness before it grades, and a board with no solution still throws `InvalidBoard`.
  **Issue:** #25
- **Decision:** The technique enum keeps the name `Technique`, and the rule interface is `TechniqueRule`. The Discretion called both `Technique`.
  **Why:** #26 pins `technique.name` in its goldens, which needs the enum.
  **Issue:** #25
- **Correction, extending the 4×4 entry above:** the enumeration now covers all 288 4×4 grids, not 95. It found 13 269 792 unique boards with at least 6 givens: every one needs at most naked singles, and the 288 full grids grade `none` (local `dart` probe, 2026-09-23). The claim is now exhaustive.
  **Issue:** #25
- **Decision (owner review requested):** 16×16 Expert is exempt from the `ceil(target × 1.1)` givens ceiling, as Evil already is.
  **Why:** On 16×16, a carve that reaches Expert stops at 87–96 givens: below that, every removal breaks uniqueness or tips the ladder into `beyond` (60 attempts, local probe, 2026-09-23). Plain uniqueness-limit carves stop at 92–96. The design's target of 79 is below what uniqueness allows, so the ceiling of 87 discarded 36 of the 38 Expert boards found, and the median generation took 7.7 s against #27's 3 s host budget. With the exemption, seeds 1–10 need 1–3 attempts, with a median of 249 ms. The setup screen will still show the design's "79 GIVENS" for 16×16 Expert, while boards arrive with about 90, the same gap the plan already accepts for Evil.
  **Issue:** #25, #26, #27; affects M4 #41 (the givens label)
- **Decision:** On Easy–Expert carving with the real grader, the per-step uniqueness count is replaced by the grade.
  **Why:** The ladder only makes forced deductions. A board it finishes within the band therefore has one solution, and a board with two always leaves it stuck, which the band check reverts. The accept and revert decisions are unchanged: 16×16 Expert seeds 1–5 needed the same 16/27/41/67/177 attempts before and after. The cost fell from 66 s to 8.7 s for three 16×16 Expert attempts; the counter had taken 66.3 s of the 66.5 s (local probe, 2026-09-23). A substituted grader still gets the count, and every finished board is counted once.
  **Issue:** #26 (Rule 3: the guard tier did not finish in 10 minutes)
- **Decision:** The weekly 200-seed tier is tagged `weekly`, not `slow` as #26's AC says, and the gate and CI exclude `weekly,bench`, not `slow,bench`.
  **Why:** `slow` already tags #245's guard `the flag the workflow sets is the flag the guard reads`, which runs in the gate and in CI's guards step today. Excluding `slow` there would have removed that guard from every pull request without anyone deciding to. `slow` keeps its meaning (kept out of the battery's per-mutation suite, run everywhere else), and the engine PR tier carries it too. That is exactly the battery treatment #26's Discretion prescribes.
  **Issue:** #26
- **Decision:** The wrapper's test hooks are plain documented top-level variables, not `@visibleForTesting`. `generateOverride` replaces the generate call *inside* the real worker, so a throwing test generator exercises the worker's own error handling.
  **Why:** `@visibleForTesting` comes from `package:meta`, which the app does not declare (`depend_on_referenced_packages` flags the import), and declaring a package for one annotation is not a lean dependency (invariant 3). A first version replaced the whole entry point, which bypassed the worker's `try/catch`, so a thrown `GenerationFailed` could only arrive as `UnexpectedError`, not the `AttemptsExhausted` #27's Discretion specifies.
  **Issue:** #27
- **Decision:** The cancel test polls `Isolate.ping` until it goes unanswered and requires that within 100 ms.
  **Why:** A ping sent in the same instant as `Isolate.kill(priority: immediate)` was still answered (4 ms after), and one sent 50 ms later was not (local probe, 2026-09-23). A single immediate ping tested the wrong thing.
  **Issue:** #27
- **Decision:** The five `#26` engine mutations run `ENGINE_SUITE` (the four engine guard files) through a new per-entry `suite` field in `tools/mutation_check.py`, instead of `slow=True` and the whole slow suite.
  **Why:** #26 requires the battery to fit its 60-minute job with margin. Before M2 the CI `mutations` job already took 44 to 51 minutes (CI runs 35877061156, 35898299127, 35907570513, read 2026-09-23 with `gh api .../actions/runs/<id>/jobs`). The first M2 local battery, with the engine entries on the slow suite, took 2 752 s, about 46 minutes (local run, 2026-09-23). An engine mutation is judged by the engine guards, and each still names the assertion it must trip. With the narrower suite all nine engine-related entries were caught in 365 s, including the baseline (local run, 2026-09-23). The CI measurement is recorded in #26's completion comment.
  **Issue:** #26
- **Finding (pre-existing, not from this run):** `#245 the verdict is handed an empty environment` SURVIVED in the local battery, and also survives on unchanged `main` locally (`tools/mutation_check.py --only 'empty environment'` against `origin/main`, 2026-09-23). It depends on the token environment the CI job provides; the CI battery has passed it on every recent run.
  **Issue:** #245
- **Decision (Rule 3):** The `mutations` job's limit is raised from 60 to 90 minutes.
  **Why:** PR #285's `mutations` job (run 35932979896) was cancelled at its 60-minute `timeout-minutes` after 131 of 147 entries, every one caught (about 26 s each). Raised to 90 as a stopgap. Splitting across jobs is the lasting fix, but the required `mutations` check would then need an `if: always()` aggregator, which ci-shape refuses by design; that guard exception is an owner call, filed as #286 (needs-triage). Every later milestone adds entries, so M3–M5's PRs each wait roughly 65–75 minutes on this job.
  **Issue:** #26, #286

## /n8-exec M3 — 2026-09-23

- **Decision:** M3 was built on a local branch cut from the M2 head while PR #285's `mutations` job ran, to be rebased onto `main` after the squash merge.
  **Why:** The battery job takes most of an hour. The M3 stories depend only on M2's code, and the trees are identical, so `rebase --onto` applies the M3 commits cleanly.
  **Issue:** #28–#36
- **Decision:** #31's open question: the board theme restyles only the grid. The top bar, pad, tools, notice and cards keep fixed colours in both themes.
  **Why:** The design file's `isBoard` template (lines 293–393) uses literal colours for every piece of chrome and reads `th.*` only inside the grid. THEMES' `screen` gradient is the same in both themes. This is what #32–#35 already assumed.
  **Issue:** #31
- **Decision:** `RandomSeedSource` lives in `lib/ui/board/`, not beside the `SeedSource` interface in `lib/game/`.
  **Why:** The game-imports guard refuses `dart:math` in `lib/game/`, so the model stays free of randomness and takes seeds from outside.
  **Issue:** #30, #36
- **Decision:** `HS_LAUNCH_SIZE=4` launches 4×4 at Easy, not Medium.
  **Why:** 4×4 Medium is not a supported pair since #25; the launch path takes Medium where offered, otherwise the hardest band the size offers.
  **Issue:** #36
- **Decision:** A generation failure shown over an existing board clears on the player's next action (any verb), as well as on a retry.
  **Why:** #36 says a failed `newDeal` keeps the previous board behind the error banner but not when the banner goes. Leaving it up indefinitely would cover every later notice.
  **Issue:** #36
- **Decision:** Leaving the board for a placeholder route (Rules, Settings, Main menu, Change size) pauses a live game first.
  **Why:** The timer already stops while another route covers the board. Pausing also means the player comes back to the pause card rather than a board that silently stopped counting.
  **Issue:** #36
