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
