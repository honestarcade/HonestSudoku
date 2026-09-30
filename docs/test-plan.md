# Honest Sudoku — device test plan

The manual pass run on a real phone before a release: every screen, every mode, and the checks only a person can make. What you tick here is the record of what was exercised; a line left unticked means nobody looked.

How to use it: install the build under test, open this file beside the phone, and work down it top to bottom — one action per line, tick each line as you see it hold, and fill in a run-log block (near the end) when you stop. When something is wrong, file it as described under "Reporting a bug" and keep going.

`test/docs/test_plan_test.dart` checks that nothing is missing from this plan: a section per screen, every mode in the table, every human-only subject, the run log and the bug-report fields. Whether the plan is any good is judged by the owner's pass in #64, not by that test.

Each section names the automated tests that already cover the same ground, so you can see what the manual step adds. A section with none says so.

## Loading

Two uses: the splash at launch, and the screen shown while a board is built.

- [ ] Force-stop the app, then open it from the launcher.
- [ ] See the mark, the Honest Sudoku wordmark and "BY HONEST ARCADE" on navy, with a bar that fills.
- [ ] See the splash stay up long enough to read (not a flash), then give way to the main menu.
- [ ] Start a 9×9 board from New puzzle and watch the label under the bar: it reads GENERATING, then CARVING GIVENS, then READY.
- [ ] See the bar grow and never go backwards.
- [ ] See the board replace the loading screen on its own once the bar is full.
- [ ] Start a 4×4 board and see the loading screen still show briefly rather than flicker.
- [ ] Start a 16×16 Evil board and press the phone's back while the bar is moving.
- [ ] See the bar stop and a "GENERATION CANCELLED" notice reading "Board building was cancelled." with TRY AGAIN and Back.
- [ ] Tap TRY AGAIN and see the bar start again from empty and a board arrive.
- [ ] Cancel another build, press the phone's back a second time, and land on New puzzle.

- Automated: `test/ui/screens/loading_screen_test.dart` — "the label follows the generation phase"
- Automated: `test/ui/screens/loading_screen_test.dart` — "back during generation cancels and shows the notice; back again leaves"
- Automated: `test/ui/screens/loading_screen_test.dart` — "launch: never before 800 ms, then the menu"

What the manual step adds: real generation time on this phone's CPU, and whether the splash feels like a splash rather than a stall.

## Main menu

- [ ] With no game in progress, see "New puzzle" as the big teal button and no time or size beside it.
- [ ] See the New puzzle card below it with the small grid glyph and "4×4, 6×6, 9×9 or 16×16 · Easy through Evil".
- [ ] See the Statistics, How to play, Settings and About the App buttons, then the About Honest Arcade row.
- [ ] Tap each of those buttons and the About Honest Arcade row in turn and see its own screen open; come back with `‹` each time.
- [ ] Start a board, pause it, tap Main menu on the pause card.
- [ ] See the big button now read "Continue puzzle" with the size, difficulty and time played, e.g. `9×9 · MEDIUM · 1:23`.
- [ ] Tap Continue puzzle and land on the same board, paused, with the same time.
- [ ] Go back to the menu, force-stop the app from the phone's app settings, and open it again.
- [ ] See Continue puzzle still offered, and tap it: the board, your entries, notes, mistakes and time are all as you left them, paused.
- [ ] Win or lose a board, then go to the menu: see "New puzzle" again with no time beside it.
- [ ] On the menu, press the phone's back: the app closes.

- Automated: `test/ui/screens/menu_routes_test.dart` — "each menu entry reaches its screen"
- Automated: `test/ui/screens/menu_routes_test.dart` — "Main menu from the pause card keeps the game; Continue returns to the same board, paused"
- Automated: `test/ui/game_controller_store_test.dart` — "kill and relaunch restores the board, notes, history, time and mistakes, paused"

What the manual step adds: a real process death and relaunch from the phone's own storage, not a simulated one.

## New puzzle

- [ ] Open New puzzle from the menu card.
- [ ] See the Grid size, Difficulty, Mistakes allowed and Announce mistakes panels, then Start puzzle.
- [ ] Tap each grid size (4×4, 6×6, 9×9, 16×16) and see it highlighted and the header's meta line change to match.
- [ ] With 9×9 chosen, see every difficulty card from Easy to Evil, each with a description and an "N GIVENS" count.
- [ ] Choose 9×9 Evil, then tap 4×4: see Easy selected, and Medium, Hard, Expert and Evil greyed with "NOT ON 4×4".
- [ ] Tap a greyed card and see nothing change.
- [ ] Tap 6×6 and see Expert and Evil greyed with "NOT ON 6×6".
- [ ] Tap each of Zen, 3, 5 and No limit, and each of Immediately and At the end, and see the choice highlighted.
- [ ] Go back to the menu and reopen New puzzle: every choice you made is still there.
- [ ] With a game in progress, open New puzzle and see "Keep playing the current puzzle" under Start puzzle.
- [ ] Tap it and land on that board, paused.
- [ ] Tap `‹` or press the phone's back from New puzzle and land on the menu.

- Automated: `test/ui/screens/setup_screen_test.dart` — "4×4 greys what it cannot offer; taps on them change nothing; picking 4×4 from Evil moves to the hardest it offers"
- Automated: `test/ui/screens/setup_screen_test.dart` — "choices are remembered; Start generates the chosen board with the chosen modes; Keep playing returns to it paused"
- Automated: `test/ui/screens/menu_routes_test.dart` — "setup opened from the board: ‹ lands on the menu"

What the manual step adds: whether a greyed card reads as unavailable at a glance on this screen.

## Board

- [ ] See the pause pill at the top reading `❚❚` with the size and difficulty, the timer chip, and the strike chip (or ZEN).
- [ ] Tap an empty cell: its row, column and box shade, and the cell is ringed.
- [ ] Tap a number on the pad: it lands in the cell. Tap the same number again: the cell clears.
- [ ] Tap a given (printed) number and try to change it: nothing changes.
- [ ] Place a wrong number with Immediately announce: a MISTAKE banner appears, the strike chip counts it, the pad moves down to make room.
- [ ] Tap NOTES, then numbers: small pencil marks appear in the cell. Tap NOTES again to go back to placing.
- [ ] Tap UNDO and REDO and see your last change go and come back; with nothing to undo or redo, tapping them does nothing.
- [ ] Tap ERASE on a cell with a value or notes: it empties.
- [ ] Tap HINT: a cell is selected, ringed yellow, and a banner names the rule (or, with Explain hints off, just the cell).
- [ ] Tap CHECK with a wrong entry on the board: it turns red and underlined, and the banner says how many are wrong.
- [ ] Watch the timer count up; tap the pause pill: the board is hidden, the card reads Paused with the size, difficulty, time and how much is filled.
- [ ] On the pause card, see Resume, Restart this puzzle, New puzzle, same settings, Rules, Settings and Main menu.
- [ ] Tap Resume: the timer picks up where it stopped.
- [ ] Press the phone's back while playing: the game pauses. Press it again: you land on the menu.
- [ ] Switch to another app and back: the game is paused and stays paused until you tap Resume.
- [ ] Tap Restart this puzzle: the same givens come back with no entries, no strikes and the timer at zero.
- [ ] Tap New puzzle, same settings: the loading screen runs and a different board of the same size and difficulty arrives.
- [ ] Open Settings from the pause card, change Mistakes allowed from 3 to 5 and Announce from Immediately to At the end, then tap `‹`: the paused board's strike chip now shows the new limit, and a wrong entry no longer shows a banner. *(owner amendment #320, `.n8/decisions.md` "Ad-hoc — 2026-09-29 (device-UAT fixes on fix/bugs-from-verification: #320, #322)")*
- [ ] Finish or leave that board and start the next one from Next puzzle or New puzzle, same settings: it keeps 5 strikes and At the end. *(owner amendment #320, `.n8/decisions.md` "Ad-hoc — 2026-09-29 (device-UAT fixes on fix/bugs-from-verification: #320, #322)")*
- [ ] Solve a board: the card reads PUZZLE SOLVED, "Grid complete", with TIME, ENTRIES, MISTAKES and STREAK tiles, and Next puzzle, Change size or difficulty and Main menu.
- [ ] With a 3-strike limit, make three wrong entries: the card reads OUT OF STRIKES, "That was the last strike", "You set a limit of 3. Retry this puzzle from the start, or take a fresh one.", with TIME, FILLED, MISTAKES and DIFFICULTY tiles. *(owner amendment #322, `.n8/decisions.md` "Ad-hoc — 2026-09-29 (device-UAT fixes on fix/bugs-from-verification: #320, #322)")*
- [ ] See Retry as the first, filled teal button, then New puzzle, Change size or difficulty and Main menu. *(owner amendment #322, `.n8/decisions.md` "Ad-hoc — 2026-09-29 (device-UAT fixes on fix/bugs-from-verification: #320, #322)")*
- [ ] Tap Retry: the same puzzle comes back from the start — same givens, no entries, no strikes, timer at zero. *(owner amendment #322, `.n8/decisions.md` "Ad-hoc — 2026-09-29 (device-UAT fixes on fix/bugs-from-verification: #320, #322)")*
- [ ] Open Statistics for that size's difficulty: the loss you retried is still counted as started and not solved. *(owner decision #322, `.n8/decisions.md` "/n8-replan — 2026-09-29")*
- [ ] On a 16×16 board, see the pad and cells use 1–9 then A–G.

- Automated: `test/ui/board_screen_test.dart` — "menu, setup, board; place, tick, pause, resume, back, background"
- Automated: `test/ui/board_screen_test.dart` — "Retry on the out-of-strikes card restarts the same puzzle"
- Automated: `test/ui/game_controller_store_test.dart` — "losing a restarted puzzle again records no second loss"
- Automated: `test/ui/game_controller_store_test.dart` — "mode changes mid-game carry into the next new game"
- Automated: `test/ui/screens/settings_screen_test.dart` — "during a game, strike and announce changes reach it and become the next board's"
- Automated: `test/ui/board/overlays_test.dart` — "each pause-card button calls back once"

What the manual step adds: whether a finger hits the cell it means to on a real screen, and whether the board reads at arm's length.

## Statistics

- [ ] Open Statistics from the menu and see a tab for each of Easy, Medium, Hard, Expert and Evil.
- [ ] Tap each tab and see its own cards: SOLVED, SOLVE RATE, BEST TIME, AVERAGE, CURRENT STREAK and TIME PLAYED.
- [ ] On a difficulty you have never played, see dashes in the cards and no size rows.
- [ ] On a difficulty you have played, see BY GRID SIZE rows with a coloured bar and a percentage per size.
- [ ] After a win, see SOLVED and CURRENT STREAK go up by one and BEST TIME set if it was your fastest.
- [ ] Tap Reset statistics: a card asks "Reset statistics?" with Cancel and Reset.
- [ ] Tap Cancel: every number is still there.
- [ ] Tap Reset statistics, then Reset: every card reads a dash.
- [ ] Tap `‹` or press the phone's back and land on the menu.

- Automated: `test/ui/screens/stats_screen_test.dart` — "a populated difficulty reads in the design formats"
- Automated: `test/ui/screens/stats_screen_test.dart` — "Reset then Cancel keeps the numbers; Reset then Reset wipes them"

What the manual step adds: numbers built from real play over several boards, checked against what you remember playing.

## How to play

- [ ] Open How to play from the menu and see the rule cards THE GOAL, ENTERING A NUMBER, PENCIL MARKS, MISTAKES and HINTS.
- [ ] Scroll down and see the CONTROLS panel: TAP CELL, TAP NUMBER, TAP AGAIN, ERASE and CHECK.
- [ ] Read each rule and control and confirm the app behaves the way it says.
- [ ] Tap `‹` and land on the menu.
- [ ] Pause a board, tap Rules on the pause card, then press the phone's back: you land on the paused board.

- Automated: `test/ui/screens/about_screens_test.dart` — "How to play: every rule and gesture, verbatim"
- Automated: `test/ui/screens/about_screens_test.dart` — "How to play: ‹ and the phone back return to the paused board when opened from the pause card, and to the menu otherwise"

What the manual step adds: whether the words match what the app actually does — the suite only proves the words are there.

## Settings

- [ ] Open Settings from the menu and see Board theme with two previews, NAVY FELT and PAPER.
- [ ] Tap PAPER: the selection moves to it. Open a board: the grid is light paper; the rest of the app stays navy.
- [ ] Switch back to NAVY FELT and see the board follow.
- [ ] See Mistakes allowed (Zen, 3, 5, No limit) and Announce mistakes (Immediately, At the end).
- [ ] Under ASSISTS, DISPLAY and SOUND, flip every toggle off and on, and see each knob move and stay where you left it.
- [ ] Turn Show timer off and see the timer chip leave the board; turn it back on.
- [ ] Turn Large digits on and see the board's numbers get heavier.
- [ ] Force-stop the app and reopen it: every toggle and the theme are as you left them.
- [ ] See the STORED ON DEVICE ONLY note and, at the bottom, the version line `vX.Y.Z · BUILD N` matching the build you installed.
- [ ] From the menu, tap `‹` and land on the menu; from the pause card's Settings, tap `‹` and land on the paused board.
- [ ] Change the strike limit and announce mode mid-game from the pause card and confirm the next board keeps them (the Board section's pause-card Settings lines).

- Automated: `test/ui/screens/settings_screen_test.dart` — "every toggle flips"
- Automated: `test/ui/screens/settings_screen_test.dart` — "Paper moves the selection to its preview and becomes the board theme"
- Automated: `test/ui/screens/settings_screen_test.dart` — "back goes to the board when opened from the pause card, and to the menu otherwise"
- Automated: `test/ui/game_controller_store_test.dart` — "a theme picked mid-game survives the game ending, a new board and a relaunch"

What the manual step adds: the version line checked against the build actually installed, and settings surviving a real relaunch.

## About the App

- [ ] Open About the App from the menu and see the boxed mark, Honest Sudoku and `vX.Y.Z · OFFLINE`.
- [ ] See the paragraph, the WHAT'S IN IT features, and THE HONEST PROMISES with its chips.
- [ ] Tap HONEST ARCADE ↗: the phone's browser opens honestarcade.app, outside the app. Come back.
- [ ] Tap SOURCE ON GITHUB ↗: the browser opens the source repository. Come back.
- [ ] Tap Honest Arcade Promises: About Honest Arcade opens.
- [ ] Tap `‹` on About the App and land on the menu.
- [ ] Press the phone's back on About the App and land on the menu.

- Automated: `test/ui/screens/about_screens_test.dart` — "About the App: features, chips, version; links open the right places"
- Automated: `test/ui/screens/about_screens_test.dart` — "About the App: ‹ and the phone back go to the menu, even when it was opened over the board"
- Automated: `test/ui/widgets/screen_header_test.dart` — "the ‹ is 26 pt, and system text size does not grow it"

What the manual step adds: the links really leaving for the browser on this phone.

## About Honest Arcade

- [ ] Open About Honest Arcade from the menu row and see the two paragraphs, the SUPPORT HONEST ARCADE card, OUR PROMISES and the chips.
- [ ] Tap the support card: the browser opens honestarcade.app/contribute. Come back.
- [ ] Tap HONEST ARCADE.APP ↗ and SOURCE ON GITHUB ↗: each opens in the browser. Come back.
- [ ] Tap a promise (not a link): nothing opens.
- [ ] Opened from the menu, tap `‹`: you land on the menu. *(owner amendment #321, `.n8/decisions.md` "Ad-hoc — 2026-09-29")*
- [ ] Open About the App, tap Honest Arcade Promises, then tap `‹`: you land back on About the App, not the menu. *(owner amendment #321, `.n8/decisions.md` "Ad-hoc — 2026-09-29")*
- [ ] Do the same with the phone's back instead of `‹`: About the App again. *(owner amendment #321, `.n8/decisions.md` "Ad-hoc — 2026-09-29")*
- [ ] Look at the `‹` in the header: it is the 26-pt glyph the owner chose, filling most of its round button and centred in it. *(owner amendment #323, `.n8/decisions.md` "Ad-hoc — 2026-09-29")*
- [ ] Set the phone's font size to its largest and come back: the header titles grow, the `‹` stays the same size and inside its button. *(owner amendment #323, `.n8/decisions.md` "Ad-hoc — 2026-09-29")*

- Automated: `test/ui/screens/about_screens_test.dart` — "About Honest Arcade: paragraphs, promises, chips; links; a non-link tap opens nothing"
- Automated: `test/ui/screens/about_screens_test.dart` — "About Honest Arcade opened from"
- Automated: `test/ui/screens/about_screens_test.dart` — "About Honest Arcade with nothing beneath it: ‹ lands on the menu"
- Automated: `test/ui/widgets/screen_header_test.dart` — "the ‹ ink is centred in the 34-pt button"

What the manual step adds: how the back glyph looks and lands under a real thumb.

---

### Modes

Play at least one board per row, with the modes that row names, and tick it. The rule that keeps this finite: every size and every difficulty at least once, every strike and announce mode at least once, both themes at least once, note mode and auto candidates each on and off at least once — not every combination. Set the modes on New puzzle and in Settings before you start the row's board. Put the build (version and code) and the phone's model in the last two cells.

| Size | Difficulty | Strikes | Announce | Theme | Note mode | Auto candidates | Done | Build | Device |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 4×4 | Easy | Zen | Immediately | Navy | on | off | - [x] | 0.9.0-rc.1 (1041) | sudoku-min emulator, Android 7.0 (API 24) |
| 6×6 | Easy | 3 | Immediately | Paper | off | on | - [x] | 0.9.0-rc.1 (1041) | sudoku-min emulator, Android 7.0 (API 24) |
| 6×6 | Medium | 5 | At the end | Navy | on | off | - [x] | 0.9.0-rc.1 (1041) | sudoku-min emulator, Android 7.0 (API 24) |
| 6×6 | Hard | No limit | Immediately | Paper | off | off | - [x] | 0.9.0-rc.1 (1041) | sudoku-min emulator, Android 7.0 (API 24) |
| 9×9 | Easy | 3 | At the end | Navy | off | on | - [x] | 0.9.0-rc.1 (1041) | sudoku-min emulator, Android 7.0 (API 24) |
| 9×9 | Medium | 3 | Immediately | Paper | on | off | - [x] | 0.9.0-rc.1 (1041) | sudoku-min emulator, Android 7.0 (API 24) |
| 9×9 | Hard | 5 | Immediately | Navy | off | off | - [x] | 0.9.0-rc.1 (1041) | sudoku-min emulator, Android 7.0 (API 24) |
| 9×9 | Expert | No limit | At the end | Paper | on | off | - [x] | 0.9.0-rc.1 (1041) | sudoku-min emulator, Android 7.0 (API 24) |
| 9×9 | Evil | Zen | At the end | Navy | off | on | - [x] | 0.9.0-rc.1 (1041) | sudoku-min emulator, Android 7.0 (API 24) |
| 16×16 | Medium | 5 | At the end | Paper | on | off | - [x] | 0.9.0-rc.1 (1041) | sudoku-min emulator, Android 7.0 (API 24) |
| 16×16 | Evil | 3 | Immediately | Navy | off | off | - [x] | 0.9.0-rc.1 (1041) | sudoku-min emulator, Android 7.0 (API 24) |

"Note mode on" means you place pencil marks with NOTES during the board; "Auto candidates on" means the Auto candidate notes toggle in Settings is on, and the NOTES tool then reads AUTO.

- Automated: `test/ui/board_screen_test.dart` — "every strike and announce mode"
- Automated: `test/ui/board_screen_test.dart` — "manual notes: NOTES then a key leaves a pencil mark"
- Automated: `test/ui/board_screen_test.dart` — "auto notes: candidates are there, the tool reads AUTO"
- Automated: `test/ui/game_controller_store_test.dart` — "the grid restyles when the theme changes"

### Not offered

These pairs are greyed on New puzzle and are not rows above, because the generator cannot prove a board of that grade at that size:

- 4×4 Medium
- 4×4 Hard
- 4×4 Expert
- 4×4 Evil
- 6×6 Expert
- 6×6 Evil

### Sound

**What the suites cannot prove:** that anything comes out of the speaker. The tests run a silent player and check which cue is asked for; the clips themselves are placeholders until #63.

**Instead:**

- [ ] Turn the phone's media volume up (inside the app the volume keys set media volume).
- [ ] Place a right number: hear the soft placement click.
- [ ] With Immediately announce and a strike limit, place a wrong number: hear the mistake thud, and no click with it.
- [ ] Solve a board: hear the solve cue on the last number, and nothing else.
- [ ] Use up the last strike: hear the out-of-strikes cue, and nothing else.
- [ ] Turn media volume down to nothing: hear nothing.
- [ ] Turn Sound effects off in Settings: hear nothing on any of the four; turn it back on and hear one click.

- Automated: `test/feedback/game_feedback_test.dart` — "a correct placement clicks"
- Automated: `test/feedback/game_feedback_test.dart` — "with Sound effects off nothing plays, but the event is still derived"
- Automated: `test/guards/audio_assets_guard_test.dart` — "audio-assets: every file under assets/audio/ is accounted for"

### Haptics

**What the suites cannot prove:** that the phone buzzes, or that the two ticks feel different. The tests record which tick is asked for.

**Instead:**

- [ ] Place a right number: feel a light tick.
- [ ] Place a wrong number with Immediately announce: feel a firmer tick.
- [ ] Solve a board, and use up a last strike: a firmer tick each time.
- [ ] Turn Haptics off in Settings: feel nothing on any placement.
- [ ] Turn Haptics back on, then turn off the phone's own touch feedback (vibration and haptics in the phone's settings): feel nothing, as the phone asked.

- Automated: `test/feedback/haptics_test.dart` — "a correct placement: one light tick"
- Automated: `test/feedback/haptics_test.dart` — "the win and the last strike: medium"
- Automated: `test/feedback/flutter_haptics_test.dart` — "light and medium are the platform's light and medium impacts"

### Launcher icon and cold-start splash

**What the suites cannot prove:** how the phone's own launcher crops and draws the icon, and what the system splash looks like before the app's first frame.

**Instead:**

- [ ] Find the app in the launcher's app drawer: the icon is the Honest Arcade mark, not cut off, with the name Honest Sudoku under it.
- [ ] Long-press the home screen and add the icon; look at it on your wallpaper.
- [ ] If the phone offers themed (monochrome) icons, turn them on and see a clean single-colour mark.
- [ ] Force-stop the app and open it: the first thing on screen is navy, with no white flash, before the app's own splash.

- Automated: `test/guards/launcher_icon_guard_test.dart` — "launcher-rasters: every mipmap and the store icon, at size, RGBA"
- Automated: `test/guards/launcher_icon_guard_test.dart` — "launcher-splash: Android 12+ themes splash on navy"

### TalkBack

**What the suites cannot prove:** what TalkBack actually says, in what voice and order, and whether a person can play by it.

**Instead:**

- [ ] Turn on TalkBack.
- [ ] On every screen, swipe through everything: each control says what it is, nothing says "button" with no name, and no arrows or symbols are read aloud as symbols.
- [ ] On the board, swipe through: the top bar, then the cells row by row, then the banner, the pad and the tools.
- [ ] Select a cell and place a number by double-tapping a pad key, then swipe back to the cell: it reads the new value.
- [ ] Make a mistake with Immediately announce: the banner is spoken without you moving to it.
- [ ] Pause, win and lose a board: each card's title is spoken as it appears.
- [ ] Turn TalkBack off.

- Automated: `test/ui/board/semantics_test.dart` — "traversal: top bar, then cells in row order, then banner, pad and tools"
- Automated: `test/ui/screens/screens_semantics_test.dart` — "setup: one selected option per group, headings, Back"

### Largest system font

**What the suites cannot prove:** the phone's largest font size, which is beyond the 1.3× the suites render at, and the phone's own font.

**Instead:**

- [ ] Set the phone's font size (and display size, if it has one) to the largest.
- [ ] Visit every screen: no text is cut off, overlaps another line, or runs off the screen; scroll where a screen scrolls.
- [ ] Open a board: the grid's numbers stay the size of their cells, and the rest of the board's text grows only a little.
- [ ] Put the font size back.

- Automated: `test/ui/screens/menu_routes_test.dart` — "large text: nothing overflows at 360×640 with 1.3× text"
- Automated: `test/ui/board/text_scale_test.dart` — "the timer chip grows with the font size"

### Remove animations

**What the suites cannot prove:** that the phone's own setting reaches the app.

**Instead:**

- [ ] Turn on the phone's Remove animations (in accessibility settings).
- [ ] Move between screens: each appears at once, with no fade.
- [ ] Win a board: the card is there at once rather than rising in.
- [ ] Flip a Settings toggle: the knob jumps rather than slides.
- [ ] Start a board: the loading bar still moves, because it shows progress.
- [ ] Turn Remove animations off.

- Automated: `test/ui/motion_test.dart` — "a pushed screen is fully there after one frame"
- Automated: `test/ui/motion_test.dart` — "the loading bar still tweens to each progress step"
- Automated: `test/ui/widgets/toggle_test.dart` — "the knob lands in one frame with animations removed"

### Greyscale

**What the suites cannot prove:** that a person can tell the marks apart without colour on a real screen.

**Instead:**

- [ ] Turn on the phone's greyscale (colour correction or bedtime mode, depending on the phone).
- [ ] Place a wrong number and tap CHECK: the wrong entry is underlined, not only red.
- [ ] With Highlight conflicts on, place a clashing number: the clashing cells carry dots.
- [ ] See which cell is selected, and whether NOTES is on, without relying on colour.
- [ ] Do the same on the PAPER theme.
- [ ] Turn greyscale off.

- Automated: `test/ui/board/board_grid_test.dart` — "a correct entry is never underlined"
- Automated: `test/ui/board/board_grid_test.dart` — "the conflicting peers are dotted, and none with conflicts off"

### Run log

One block per pass, newest at the bottom. Copy the template below, fill every field, and leave it here. `.n8/memory/device-testing.md` links to this log rather than copying it.

### Pass — YYYY-MM-DD

- Date:
- Build version:
- Build code:
- Device (model, Android version):
- Ran by:
- Sections completed:
- Issues filed:

### Pass — 2026-09-30

- Date: 2026-09-30
- Build version: 0.9.0-rc.1 — the release build of tag `v0.9.0-rc.1` (0d229c1), built locally with `flutter build apk --release --build-name=0.9.0-rc.1 --build-number=1041 --dart-define=HS_VERSION=0.9.0-rc.1+1041` and no `HS_*` signing variables, so signed with the debug key (build.gradle.kts's documented fallback); Settings read `v0.9.0-rc.1 · BUILD 1041`.
- Build code: 1041 (the code the tag's Release run, number 4 attempt 1, computes with `tools/ci_version.sh`).
- Device (model, Android version): `sudoku-min` emulator from `tools/matrix_avds.sh` — Android 7.0 (API 24), google_apis arm64-v8a, 720×1280 at 320 dpi. Defects re-checked on `sudoku-big` — Android 14 (API 34), google_apis arm64-v8a, 1080×2400 at 400 dpi.
- Ran by: Claude (agent, #61), driving the emulator with `adb shell input` and judging screenshots.
- Sections completed:
  - [x] Loading — every line on `sudoku-min`, except that the GENERATING label was never on screen long enough to capture; CARVING GIVENS and READY were seen, and the bar never went backwards.
  - [x] Main menu — every line, including a force-stop and relaunch that restored the 4×4 paused at the same time and entries.
  - [x] New puzzle — every line.
  - [x] Board — every line, including the owner amendments (#320 mid-game Settings carry-over, #322 Retry and the loss still counted in Statistics).
  - [x] Statistics — every line.
  - [x] How to play — every line.
  - [x] Settings — every line; all eleven toggles and the Paper theme survived a force-stop.
  - [x] About the App — every line; links open the system's only browser (WebView Browser Tester on this image).
  - [x] About Honest Arcade — every line; the largest-font step run at Android 7's largest font scale (1.3).
  - [x] Modes — all eleven rows (table above).
  - [x] Launcher icon and cold-start splash — the legacy launcher PNG in the drawer and on the home screen; API 24 offers no themed icons; no Android 12 splash; on-device frame captures of two cold starts (from the white app drawer and from the home screen) show the launcher, then a navy window, then the app's own splash, with no white frame.
  - Not run: Sound (emulator started with `-no-audio`), Haptics (no vibrator on the emulator), TalkBack, Largest system font beyond the header check, Remove animations, Greyscale.
  - Bundled fonts: Outfit and the mono face render on every screen; the system's Roboto appears only in the launcher and the browser.
  - 16×16 Evil generation on `sudoku-min`, timed 2026-09-30 by polling screenshots from the host (each sample one screencap round-trip, about 0.5 s) from the Start tap to the board's first frame, three random seeds: 6.1–6.6 s, 7.4–8.1 s, 11.5–12.0 s. The board's timer read 0:01 on arrival, so generation time is not counted as play. For #65.
  - Timeout path, bracketed: the release build was uninstalled, a debug build with the ceiling lowered to one second installed, a 16×16 Evil requested, "GENERATION FAILED / Couldn't build a board in time. Try again." shown with TRY AGAIN, and TRY AGAIN produced a board; then the debug build was uninstalled and the release build reinstalled. The isolate does not read `HS_GENERATION_CEILING_MS`, so that debug build carried a throwaway local edit of `kGenerationCeiling` rather than the define.
- Issues filed: two defects found on `sudoku-min`, both re-checked on `sudoku-big`: the loading screen's failure notice and Back button span the full 360-dp width with no margin (did not reproduce on `sudoku-big`, where they sit inside a margin); the 16×16 selection ring covers the selected cell's outer pencil marks (reproduced on `sudoku-big`, less severely). Issue numbers to be added when filed.

### Pass — 2026-09-30 (sudoku-min, device suites)

- Date: 2026-09-30
- Build version: 0.1.0 (pubspec.yaml) — profile builds of `801c148` (`milestone/m6-device-testing`), built by `flutter drive --profile` inside `tools/soak.sh` and `tools/e2e.sh`, signed with the debug key.
- Build code: 1 (pubspec.yaml's `+1`; no `--build-number` passed).
- Device (model, Android version): `sudoku-min` emulator (`emulator-5590`, booted with `tools/matrix_avds.sh --boot sudoku-min`) — "Android SDK built for arm64", Android 7.0 (API 24), arm64-v8a, 720×1280 at 320 dpi.
- Ran by: Claude (agent, #65 and #66), running the two device suites unattended.
- Sections completed:
  - [x] Engine soak (#65) — `tools/soak.sh --device min`, seeds 1..20 per pair, no reduction: exit 0, whole run 242 s (the script's own timer, 2026-09-30). Every pair within the 15 s ceiling; every board had exactly one solution and graded to the band requested; the golden fingerprints computed on the device equal the committed host values. Table as `tools/soak.sh` wrote it to `build/soak-sudoku-min-2026-09-30.md`:

    | shape | difficulty | median ms | worst ms | best ms | median attempts | worst attempts | ceiling |
    |---|---|---|---|---|---|---|---|
    | 4x4 | easy | 1 | 10 | 0 | 1 | 1 | within 15 s |
    | 6x6 | easy | 1 | 3 | 1 | 1 | 1 | within 15 s |
    | 6x6 | medium | 87 | 389 | 23 | 128 | 774 | within 15 s |
    | 6x6 | hard | 240 | 461 | 27 | 314 | 666 | within 15 s |
    | 9x9 | easy | 2 | 2 | 2 | 1 | 1 | within 15 s |
    | 9x9 | medium | 16 | 74 | 3 | 3 | 13 | within 15 s |
    | 9x9 | hard | 65 | 422 | 4 | 9 | 59 | within 15 s |
    | 9x9 | expert | 627 | 5067 | 76 | 70 | 660 | within 15 s |
    | 9x9 | evil | 9 | 20 | 4 | 2 | 5 | within 15 s |
    | 16x16 | easy | 17 | 20 | 17 | 1 | 1 | within 15 s |
    | 16x16 | medium | 36 | 170 | 25 | 1 | 2 | within 15 s |
    | 16x16 | hard | 164 | 3778 | 64 | 1 | 2 | within 15 s |
    | 16x16 | expert | 463 | 6313 | 271 | 1 | 3 | within 15 s |
    | 16x16 | evil | 5435 | 13278 | 572 | 1 | 1 | within 15 s |

    Phases, summed over each pair's seeds:

    | shape | difficulty | GENERATING ms | CARVING GIVENS ms | READY ms | carving share |
    |---|---|---|---|---|---|
    | 4x4 | easy | 7 | 17 | 1 | 68% **over half** |
    | 6x6 | easy | 3 | 17 | 4 | 71% **over half** |
    | 6x6 | medium | 1 | 2551 | 8 | 100% **over half** |
    | 6x6 | hard | 1 | 4837 | 8 | 100% **over half** |
    | 9x9 | easy | 0 | 36 | 4 | 90% **over half** |
    | 9x9 | medium | 0 | 379 | 16 | 96% **over half** |
    | 9x9 | hard | 0 | 2235 | 12 | 99% **over half** |
    | 9x9 | expert | 3 | 27120 | 17 | 100% **over half** |
    | 9x9 | evil | 0 | 192 | 11 | 95% **over half** |
    | 16x16 | easy | 1 | 324 | 24 | 93% **over half** |
    | 16x16 | medium | 2 | 885 | 49 | 95% **over half** |
    | 16x16 | hard | 14 | 7404 | 84 | 99% **over half** |
    | 16x16 | expert | 11 | 21129 | 113 | 99% **over half** |
    | 16x16 | evil | 51 | 116739 | 2137 | 98% **over half** |

    16×16 Evil's worst case (seed 5) was 13,278 ms of the 15 s ceiling, so this run did not overrun; the phase check flagged all 14 pairs (CARVING GIVENS over half the wall clock), which is #65's copy question and is not decided here.
  - [x] End-to-end (#66) — `tools/e2e.sh min`: `e2e: PASSED on sudoku-min (play 23 s, restore 9 s)`, 16 of 16 steps ok (`build/e2e-sudoku-min-2026-09-30.md`). The first attempt that day never reached a step: `flutter drive` attached to the VM service address the soak's app process had logged earlier, and it retried that stale address until the attempt was stopped. The second attempt was run after `adb logcat -c` and passed:

    | phase | step | result | ms |
    |---|---|---|---|
    | play | launch lands on the menu, with no game to continue | ok | 701 |
    | play | New puzzle opens setup; pick 9×9 Medium | ok | 434 |
    | play | Start waits for a real 9×9 Medium board | ok | 698 |
    | play | entries from the solution win the game | ok | 3051 |
    | play | the win card shows a streak of 1 | ok | 2 |
    | play | Main menu: Continue is gone | ok | 166 |
    | play | Statistics shows the solve | ok | 347 |
    | play | Settings: Paper, and row/column/box highlight off | ok | 764 |
    | play | a new board renders Paper with no unit shading | ok | 917 |
    | play | a second game: six entries, one mistake, two notes | ok | 7871 |
    | restore | relaunch after the kill offers Continue | ok | 714 |
    | restore | settings survived the relaunch | ok | 2 |
    | restore | Continue restores board, notes, time and mistakes, paused | ok | 168 |
    | restore | the restored game plays on to a win | ok | 2947 |
    | restore | the win card shows a streak of 2 | ok | 2 |
    | restore | Statistics counts both solves | ok | 546 |

- Issues filed: none — no app defect found. The stale-VM-service hang on the first e2e attempt is a harness problem: `tools/e2e.sh` does not clear logcat before its first drive, while `tools/soak.sh` does.

### Reporting a bug

File every problem as a GitHub issue with the `bug` label, and fill in every field below so nobody has to come back to you with a question. The last field is the owner's bar for what must be fixed before release.

```text
Build version:
Build code:
Device (model, Android version):
Steps:
  1.
What happened:
What was expected:
Blocks play or misleads the player: yes / no — why
```

Add a screenshot or screen recording when it shows the problem.
