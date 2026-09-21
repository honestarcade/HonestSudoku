# Signing

`upload_certificate.pem` is the **public** certificate of the upload key, and
is committed on purpose. A certificate is the public half of a key pair: it
identifies the signer and verifies signatures, and it can do nothing on its
own. Play App Signing needs it at enrolment (M7), and having it in the
repository means the enrolment does not depend on anyone's laptop.

The private key it belongs to is **not** here and never will be. It lives at
`~/HonestArcadeApps/secrets/sudoku-upload.keystore`, outside this repository,
and `.gitignore` refuses every extension it could arrive under. See
`.n8/memory/android-signing.md` for the procedure and the rotation runbook.

## What this certificate is

| | |
|---|---|
| alias | `upload` |
| owner | `O=Honest Arcade, CN=Honest Sudoku` |
| SHA-256 | `03:FB:31:8B:4C:09:9C:59:EA:6E:67:33:46:46:D5:E5:E7:50:13:25:61:9D:6A:D4:94:B6:57:81:AD:95:B2:2D` |
| valid until | 2054-02-04 |

The alias matters because the release build signs **by alias**: a keystore
holding the right key under a different name fails at signing time, and
`HS_KEY_ALIAS` must be this value. The fingerprint is here so it can be
compared without a keystore, a build, or this file's own tooling — all three
of these were named in #13's discretion and none was recorded (#108, #123).

## Check that a bundle was signed with this key

```sh
tools/verify_upload_cert.sh
```

That is the supported way: it resolves `keytool` the way the rest of the
project does, compares the bundle's fingerprint with the PEM above, and exits
0 on a match, 1 on a mismatch printing both, 2 for a missing input and 3 when
`keytool` cannot be found. It takes an optional bundle path and honours
`HS_UPLOAD_CERT`.

By hand, if you prefer:

```sh
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
keytool -printcert -file android/signing/upload_certificate.pem
```

The SHA-256 fingerprints must match.
