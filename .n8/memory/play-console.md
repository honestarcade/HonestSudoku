---
name: play-console
description: The Play Console app entry, the CI service account, and the constraints a personal developer account puts on getting to production
metadata:
  type: project
---

# Play Console (Honest Sudoku)

**Never store credentials here.** This file holds identifiers, constraints and
the permission set. Secret values live in the repository's Actions secrets and
in the owner's password manager, nowhere else.

## The app entry

| | |
|---|---|
| name | Honest Sudoku |
| package | `com.honestarcade.sudoku` |
| type | Game, free |
| default language | English (US) |
| Console app id | _pending — the owner creates the entry (#19)_ |

The package id is immutable after the first upload. It is asserted against the
build and against the privacy policy by `test/guards/docs_consistency_test.dart`.

## The CI service account

| | |
|---|---|
| Cloud project | `honestsudoku-ci` |
| service account | `sudoku-ci@honestsudoku-ci.iam.gserviceaccount.com` |
| Cloud IAM roles | none, deliberately |
| created by | `tools/setup_play_ci.sh` (idempotent) |

A project per app, matching Frog Across's `frogacross-ci`, so revoking one
app's automation never touches the other. The account holds **no Cloud IAM
roles**: Play access is granted in the Play Console, not in Cloud IAM, and a
role here would be authority nobody needs.

### The permission set granted in the Console

App-level, for Honest Sudoku only:

- Release to testing tracks
- View app information and download bulk reports

**And nothing else.** No production release. No store-listing edit. This is the
barrier that stops the automation reaching production even if a workflow were
changed to try — and it is the one barrier a human can alter without leaving a
diff, which is why `tools/play_promote.sh` refuses `production` independently.

## Secrets the workflows read

Names only:

- `PLAY_SERVICE_ACCOUNT_JSON` — set by `tools/setup_play_ci.sh`
- `HS_KEYSTORE_B64`, `HS_KEYSTORE_PASS`, `HS_KEY_ALIAS`, `HS_KEY_PASS` — set by
  `tools/set_ci_secrets.sh`

`.github/workflows/play-api-check.yml` proves all five work, on demand, without
changing anything on Play.

## What a personal developer account means for launch

This is a personal Google Play developer account, not an organisation one, and
the rules are different:

- **Closed testing with at least 12 testers, for 14 continuous days**, before
  production access is granted.
- The 14 days are **per tester**, not an aggregate. A tester who opts out
  restarts their own clock, and a dip below 12 restarts the requirement.
- Plan the recruitment before the countdown, not during it.

That constraint is why M7's plan starts the tester recruitment early, and why
nothing in this repository automates a production release.

## The draft-app rule

Until the first release is **published**, Play refuses a `completed` release on
a testing track. `tools/play_promote.sh` retries as a `draft` release when it
sees that refusal, and says so in its output rather than substituting silently.
