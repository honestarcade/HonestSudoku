---
name: android-signing
description: Where the Android upload keystore lives, how builds consume it, and how to rotate it
metadata:
  type: project
---

# Android upload signing

- **Keystore:** `~/HonestArcadeApps/secrets/sudoku-upload.keystore` — outside
  the repository, chmod 600. PKCS12, alias `upload`, RSA 2048,
  SHA256withRSA, validity 10000 days, dname `O=Honest Arcade, CN=Honest Sudoku`.
  Created 2026-09-19 by `tools/make_upload_key.sh`.
- **JDK:** `/opt/homebrew/opt/openjdk@21/bin/keytool`. The macOS `/usr/bin/java`
  is a stub with no runtime — see [[android-toolchain]].
- **Password:** generated at creation and written to
  `~/HonestArcadeApps/secrets/sudoku-signing-credentials.txt` (chmod 600).
  **Owner action: move it into your password manager and delete that file.**
  Until then the file doubles as an env template — every line is a comment or an
  `export`. **Parse it, do not source it** — `tools/set_ci_secrets.sh` does,
  and that is the tested path; the values are escaped so a dot-source is
  inert, but sourcing was how #119 handed back a password that did not open
  the keystore. PKCS12 has one password, so
  `HS_KEY_PASS` equals `HS_KEYSTORE_PASS` by format design.
- **Certificate fingerprint (SHA-256):**
  `SHA256:03:FB:31:8B:4C:09:9C:59:EA:6E:67:33:46:46:D5:E5:E7:50:13:25:61:9D:6A:D4:94:B6:57:81:AD:95:B2:2D`
  The public certificate is committed at `android/signing/upload_certificate.pem`.
- **Build consumption:** `android/app/build.gradle.kts` reads
  `HS_KEYSTORE_PATH`, `HS_KEYSTORE_PASS`, `HS_KEY_ALIAS`, `HS_KEY_PASS` with
  `System.getenv` at configuration time. Nothing is written to any file in the
  tree; there is no `key.properties`.
  - all four set → signed with the upload key
  - none set, `HS_RELEASE` unset → debug key, with a warning printed
  - `HS_RELEASE=1` and any missing → configuration fails naming the variable
  - partly set, in any mode → configuration fails (almost always a typo, and
    silently debug-signing would hide it)
- **CI secret names for M1 (#20):** `HS_KEYSTORE_B64` (`base64 < the keystore`),
  `HS_KEYSTORE_PASS`, `HS_KEY_ALIAS`, `HS_KEY_PASS`.

## Never regenerate silently

Once Play App Signing is enrolled at the first upload, this certificate **is**
the app's identity. Play will reject a bundle signed with anything else. If the
keystore or its password is lost after enrolment, do **not** run
`make_upload_key.sh` again and hope — the script refuses to overwrite for this
reason. Use the Play Console's upload-key reset instead:

Play Console → the app → Test and release → Setup → App integrity → App signing
→ request upload key reset. Generate a new keystore with the script, export the
new certificate, upload it to the Console, and replace the CI secrets.

Before enrolment (today), regenerating is harmless: move the old file aside and
re-run the script.
