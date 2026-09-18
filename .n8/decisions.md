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
