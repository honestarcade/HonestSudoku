# Fonts

The app's two typefaces, bundled so nothing is ever downloaded at run time
(invariant 1): **Outfit** (300, 400, 500, 600, 700) and **IBM Plex Mono**
(400, 500, 600). Both are licensed under the SIL Open Font License 1.1, whose
texts sit beside them (`OFL-Outfit.txt`, `OFL-IBMPlexMono.txt`). They are not
covered by this repository's MIT licence.

`tools/fetch_fonts.sh` fetched every file below from a pinned upstream commit
and recorded its SHA-256 in `SHA256SUMS`; `tools/fetch_fonts.sh --check`
verifies them without the network, and the fonts guard runs that check.

<!-- fonts:begin -->
| File | Source | Commit | Committed | Downloaded | SHA-256 |
|---|---|---|---|---|---|
| `Outfit-Light.ttf` | Outfitio/Outfit-Fonts | `902773808eb3` | 2023-03-26 | 2026-09-24 | `181c6867345960e0fbd807131624d092accb5f87185910f9496ba8b188aa2730` |
| `Outfit-Regular.ttf` | Outfitio/Outfit-Fonts | `902773808eb3` | 2023-03-26 | 2026-09-24 | `3b64ac4f6ab6a8eebddd4b0bc03c811c43602e11e176382ab0ee6be615ab861b` |
| `Outfit-Medium.ttf` | Outfitio/Outfit-Fonts | `902773808eb3` | 2023-03-26 | 2026-09-24 | `dc8d9212fc57556a55d01e863071f727cd6264b748e28885d853807aeb186142` |
| `Outfit-SemiBold.ttf` | Outfitio/Outfit-Fonts | `902773808eb3` | 2023-03-26 | 2026-09-24 | `bf2e1d2a6ec2a67952e8b36edd2b2bb9f340c0cdd10b0ad5145b4dbbc1339608` |
| `Outfit-Bold.ttf` | Outfitio/Outfit-Fonts | `902773808eb3` | 2023-03-26 | 2026-09-24 | `f620b69582e06d7e1b3bbde74ed8c5876eadabb038390780db2a3414a1490197` |
| `OFL-Outfit.txt` | Outfitio/Outfit-Fonts | `902773808eb3` | 2023-03-26 | 2026-09-24 | `c676351bf8576b9aba743cd5eaa8c0e7ee0d51f805d720447b4df4ddb6a2e416` |
| `IBMPlexMono-Regular.ttf` | google/fonts | `b5efa9c32e8f` | 2026-09-23 | 2026-09-24 | `6a3412f058c7d8dfd9170c41e85ade48e5156ecb89356110ca57a0a27734af46` |
| `IBMPlexMono-Medium.ttf` | google/fonts | `b5efa9c32e8f` | 2026-09-23 | 2026-09-24 | `a9b4c49bb299e05b5f6c481e7fb5e78943d2793249a0c8874ab574a2d1ea6755` |
| `IBMPlexMono-SemiBold.ttf` | google/fonts | `b5efa9c32e8f` | 2026-09-23 | 2026-09-24 | `d3c38e55c78f5b0f28009fddba4834ec503278936a5986032424c9bd2d23aa46` |
| `OFL-IBMPlexMono.txt` | google/fonts | `b5efa9c32e8f` | 2026-09-23 | 2026-09-24 | `7e6b2818edbd8f6a01ae80641cc8f16a51080d08fb4e532be3a0b6f74adb07da` |
<!-- fonts:end -->
