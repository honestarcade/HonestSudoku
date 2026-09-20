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
| developer account id | _pending — the owner records it with the app id_ |
| owner account | _pending — the Google account that owns the Console_ |

Record all three together: the developer id and the owning account are what
tell a later session which Console and which login this project lives under,
and neither is recoverable from the repository.

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

`.github/workflows/play-api-check.yml` exercises them on demand, without
changing anything on Play.

## What a personal developer account means for launch

This is a personal Google Play developer account, not an organisation one, and
the rules are different:

- **Closed testing with at least 12 testers, for 14 days**, before
  production access is granted. That much is what #19 states; #19 does not
  say **continuous**, so that word is not sourced here — it belongs to the
  open question in the next bullet (#164).
- **Unresolved, and to be confirmed in the Console before M7 plans around it:**
  whether the 14 days are counted per tester or across the cohort. This file
  previously asserted both in consecutive sentences — "the 14 days are **per
  tester**, not an aggregate" followed by "a dip below 12 restarts the
  requirement", which is an aggregate rule (#139). Nothing in this repository
  or in #19 sources either. The safe plan is the stricter reading: keep at
  least 12 testers enrolled continuously for the whole 14 days, so that both
  readings are satisfied. Do not encode the looser one anywhere until the
  Console's own wording has been read.
- Plan the recruitment before the countdown, not during it.

That constraint is why M7's plan starts the tester recruitment early, and why
nothing in this repository automates a production release.

## The draft-app rule

Until the first release is **published**, Play refuses a `completed` release on
a testing track. `tools/play_promote.sh` retries as a `draft` release **only
when the API's response names that rule** — matched case-insensitively on the
response body, at the track PUT or at the commit, since Play can refuse at
either. It says so on stderr rather than substituting silently.

Any other refusal — a 403, a quota error, a 5xx — fails the run with the
response that caused it. It used to retry on any failure at all, so a
permission denial was reported as "the app is not yet published", the release
was quietly downgraded to draft, and the run exited 0 (#129).

## For M7, to be filled in as the launch proceeds

Pre-seeded so the answers land here rather than being re-derived. Empty is an
honest state; a guess is not.

### Data safety

_pending._ The app collects nothing and has no network access, so every answer
is "no data collected". Record the exact form once submitted, because the
declaration must match `docs/privacy.md` and the manifest.

### Content rating

_pending._ IARC questionnaire answers, and the ratings they produced.

### Closed-test log

_pending._ Tester count by date, the 14-day window's start, and any dip — the
evidence for production access. See the unresolved counting rule above before
treating a dip as harmless.

### Service-account key id

_pending._ `tools/setup_play_ci.sh` prints the `private_key_id` when it sets
`PLAY_SERVICE_ACCOUNT_JSON`. Record it here: it is public, it names the key
rather than being the key, and it is what tells the owner which key to revoke
when rotating.

## Releasing

The mechanics live in the README's Release section; this records only what is
Console-side and not obvious from the repository.

- A release is a **tag**. `git tag v0.1.0 && git push origin v0.1.0` runs
  `.github/workflows/release.yml`, which re-runs the PR gate, builds signed,
  scans the bundle for permissions, checks it against the committed upload
  certificate, and uploads to the **internal** track. Nothing is published by
  hand and nothing reaches production.
- **Never re-tag a version.** Play refuses a version code it has already seen,
  and a moved tag would produce a second build claiming to be the same
  release. Ship the next version instead.
- Version codes are `1000 + run_number * 10 + run_attempt`
  (`tools/ci_version.sh`), so they rise strictly across runs and a re-run of a
  failed run outranks the attempt it replaces.
- Promotion to closed testing is a separate manual dispatch
  (`.github/workflows/play-promote.yml`); it refuses `production` in its first
  step, before any credential is minted.
- **Play App Signing** is enrolled by the first upload. The upload certificate
  this repository commits is `android/signing/upload_certificate.pem`; the app
  signing key is Play's and never leaves it.
