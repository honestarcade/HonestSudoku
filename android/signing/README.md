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

Check that a bundle was signed with this key:

```sh
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
keytool -printcert -file android/signing/upload_certificate.pem
```

The SHA-256 fingerprints must match.
