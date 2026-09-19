---
name: pages
description: How the privacy policy is published, and what that makes public
metadata:
  type: project
---

# GitHub Pages

- **URL:** <https://honestarcade.github.io/HonestSudoku/> — the policy is at
  `/privacy`, which is the URL entered in the Play Console.
- **Source:** the `main` branch, `/docs` folder. Jekyll with the primer theme;
  `docs/privacy.md` carries `permalink: /privacy`, which is what makes the URL
  path independent of the file name.
- **Everything under `docs/` is public.** That is the point, and it is also the
  hazard: anything committed there is served. Nothing but the site belongs in
  that folder.

## How it was enabled

Enablement is a **post-merge** step and cannot be done from a branch — the
Pages API needs `docs/` to exist on `main` and returns 404 otherwise. Intended
method, run immediately after the M0 pull request merges:

```sh
gh api -X POST repos/honestarcade/HonestSudoku/pages --input - <<'JSON'
{"source":{"branch":"main","path":"/docs"}}
JSON
```

If the API refuses, the fallback is one manual click: Settings → Pages → Deploy
from a branch → `main` / `/docs`.

Recorded at the same time: the repository `homepage` is set to the Pages URL
and the `description` to "Fully offline Sudoku for Android. No ads, no
tracking, no permissions."

**Status: enabled 2026-09-19, by the API call above — no manual click was
needed.** The response confirmed `"source":{"branch":"main","path":"/docs"}`,
`"public":true` and `"https_enforced":true`. The first build took a few minutes;
`/privacy` returned 404 until it finished, then 200 with the policy text, the
package id and the effective date. The repository `homepage` and `description`
were set in the same step.

Pages builds are asynchronous: the first request after enabling can 404 for a
minute or two. Poll up to five minutes before concluding anything is wrong.
