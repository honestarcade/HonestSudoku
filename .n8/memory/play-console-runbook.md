# Play Console runbook — click by click

Everything the owner must do by hand, with every field value filled in. Each
step says who does it. Where a value is fixed, it is given verbatim — do not
retype it from memory, copy it.

Written 2026-09-20 for M1 #19. The agent-side steps are automated and tested;
the Console steps are not automatable (there is no API for them).

---

## Before you start

You need a **Google Play developer account**. If you do not have one, that is
the real blocker for everything below and for M1's closure:

- <https://play.google.com/console/signup>
- One-off **$25** registration fee, personal account is fine.
- Identity verification can take a few days. Nothing else here works until it
  completes, so start it first if it is not already done.

---

## Step 1 — Create the app entry  *(owner, ~2 minutes)*

Play Console → **All apps** → **Create app**.

| Field | Value |
|---|---|
| App name | `Honest Sudoku` |
| Package name | `com.honestarcade.sudoku` |
| Default language | `English (United States) – en-US` |
| App or game | **Game** |
| Free or paid | **Free** |
| Declarations | tick both (Developer Program Policies; US export laws) |

Click **Check availability** under the package name before continuing. It must
come back available — the string is a one-time, permanent choice, and a typo
here cannot be corrected later, only abandoned along with the app entry.

Then **Create app**.

> Copy `com.honestarcade.sudoku` rather than retyping it. It must match
> `applicationId` in `android/app/build.gradle.kts` exactly; a guard asserts
> that value, and the release upload is rejected outright if the two differ.

**Record two things and paste them to me:**

1. The **app id** — the long number in the URL while the app is open:
   `https://play.google.com/console/u/0/developers/<developer-id>/app/<APP-ID>/...`
2. The **developer id** — the other number in that same URL.

Both are recorded in `.n8/memory/play-console.md`, which currently has them as
`_pending_`. Neither is a secret.

---

## Step 2 — Sign in to Google Cloud  *(owner, ~1 minute)*

In this session, type:

```
! gcloud auth login
```

A browser opens. **Sign in with the same Google account that owns the Play
Console**, or the service account lands under the wrong account and the invite
in step 4 will not find it.

`tools/setup_play_ci.sh` now prints the account it found and asks you to
confirm before creating anything, so a wrong login is caught rather than
silently used.

---

## Step 3 — Create the service account  *(me, ~1 minute)*

I run `tools/setup_play_ci.sh`. It is idempotent and grants **no IAM roles**.

It creates:

| | |
|---|---|
| Cloud project | `honestsudoku-ci` |
| Service account | `sudoku-ci@honestsudoku-ci.iam.gserviceaccount.com` |
| Enabled API | `androidpublisher.googleapis.com` |
| Repository secret | `PLAY_SERVICE_ACCOUNT_JSON` |

The key is written with `umask 077`, uploaded, and deleted through a `trap` so
it does not survive a failure. It prints the key **id** — public, and what you
need later to revoke the right key — and never the key itself.

---

## Step 4 — Invite the service account  *(owner, ~3 minutes)*

Play Console → **Users and permissions** → **Invite new users**.

| Field | Value |
|---|---|
| Email address | `sudoku-ci@honestsudoku-ci.iam.gserviceaccount.com` |
| Account permissions | **none** — leave every box unticked |

Then **Add app** → select **Honest Sudoku** → grant exactly these two, and
nothing else:

- ☑ **Release to testing tracks**
- ☑ **View app information and download bulk reports**

Explicitly **not**:

- ☐ Release to production, exclude devices, and use Play App Signing
- ☐ Manage store presence
- ☐ Manage orders and subscriptions

**Send invitation.** The service account accepts automatically — there is no
inbox to check.

> This permission set is why the promote workflow cannot reach production even
> if every code-level barrier failed. It is the one control that does not live
> in this repository, which is why the repository has its own.

---

## Step 5 — Set the signing secrets  *(me, ~1 minute, needs your go-ahead)*

I run `tools/set_ci_secrets.sh`, which reads
`~/HonestArcadeApps/secrets/sudoku-signing-credentials.txt` and sets four
repository secrets: `HS_KEYSTORE_B64`, `HS_KEYSTORE_PASS`, `HS_KEY_ALIAS`,
`HS_KEY_PASS`.

I have deliberately not run this before now. It is the moment your real
keystore password moves into a repository secret, and it should happen while
you are watching. It needs no credential from you — only your say-so.

The script parses that file rather than sourcing it, verifies the password and
alias actually open the keystore before uploading anything, and prints only
the secret names.

---

## Step 6 — Prove it works  *(me, ~2 minutes)*

I dispatch `.github/workflows/play-api-check.yml`. It opens and deletes a
throwaway edit, lists the tracks and checks the keystore secrets. It publishes
nothing and changes nothing on Play.

A brand-new app has no tracks yet; that is a pass, and the summary says so.

Expected afterwards: `gh secret list` shows five, and that run is green.

---

## Step 7 — The first release  *(me, after 1–6)*

`/n8-release 0.1.0` tags `main`. The tag runs the full PR gate again, builds a
signed bundle, scans it for Android permissions, checks it against the
committed upload certificate, and uploads to the **internal** track.

Play App Signing is enrolled by that first upload. After it, the upload key
cannot be regenerated — only reset through the Console — which is why
`tools/make_upload_key.sh` refuses to overwrite either of its outputs.

---

## What is still yours alone, later

Production access on a **personal** developer account requires a closed test
with at least 12 testers for 14 days. Whether those days are counted per
tester or across the cohort is **unresolved** — see the note in
`.n8/memory/play-console.md`. Work to the stricter reading: keep twelve
testers enrolled continuously for the whole window.
