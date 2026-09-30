#!/usr/bin/env python3
"""Sound-effect generation (#49): ElevenLabs text-to-sound-effects into the
game's four clip names, post-processed to the lengths the game expects.

Ported from Frog Across's ArtSource/pipeline/sfx.py; its music and relevel
branches are dropped. It is NOT reproducible -- the model returns something
new on every call -- so the committed WAVs are the artifact of record. The
script exists to audition candidates and install the owner's pick. It is never
run by CI and needs the owner's key.

Usage:
  source ~/HonestArcadeApps/secrets/elevenlabs.env
  python3 tools/sfx.py /tmp/audition [--variants 3] [--only place,mistake]
  python3 tools/sfx.py --audition place [--dir build/sfx-audition] [--device SERIAL]
  python3 tools/sfx.py --install place /tmp/audition/place-v2.wav [--plan Creator]

`--audition` (#63) hears the candidates where the player will: each
<clip>-v<N>.wav in turn is staged as assets/audio/<clip>.wav at the clip's mix
level, and the app is built and launched with `flutter run --release` on the
attached phone; Enter moves to the next. The owner's pick is written to
<dir>/selections.json, and assets/audio/ is put back exactly as it was
however the loop ends.

The swap from a placeholder to a real clip is `--install`: it writes
assets/audio/<clip>.wav at the clip's mix level, deletes
assets/audio/placeholder-<clip>.wav, and adds the clip's row to the Licensed
table in assets/audio/LICENSES.md with today's date. No Dart changes; the app
prefers the real clip whenever it is bundled.

Writes <out_dir>/<clip>-v<N>.wav (44.1 kHz, mono, 16-bit), prompts.txt and
audition.html.
"""
import argparse
import datetime
import json
import os
import re
import ssl
import struct
import subprocess
import sys
import urllib.request
import wave
from pathlib import Path

API = "https://api.elevenlabs.io/v1/sound-generation?output_format=pcm_44100"
RATE = 44100
# pcm_44100 comes back as INTERLEAVED STEREO 16-bit (Frog Across found this
# against `afinfo` on 2026-09-16); effects are written mono.
CHANNELS = 2
ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "assets" / "audio"
LICENSES = DEST / "LICENSES.md"
AUDITION_DIR = ROOT / "build" / "sfx-audition"


def _peak(pcm: bytes) -> int:
    """Largest absolute 16-bit sample."""
    hi = 0
    for i in range(0, len(pcm) - 1, 2):
        v = struct.unpack_from("<h", pcm, i)[0]
        if v == -32768:
            return 32768
        hi = max(hi, abs(v))
    return hi


def _scale(pcm: bytes, factor: float) -> bytes:
    """Multiply every sample, clamped to the 16-bit range."""
    out = bytearray(len(pcm))
    for i in range(0, len(pcm) - 1, 2):
        v = int(struct.unpack_from("<h", pcm, i)[0] * factor)
        struct.pack_into("<h", out, i, max(-32768, min(32767, v)))
    return bytes(out)


def _to_mono(pcm: bytes) -> bytes:
    """Average interleaved stereo down to mono."""
    out = bytearray(len(pcm) // 2)
    for i in range(0, len(pcm) - 3, 4):
        left = struct.unpack_from("<h", pcm, i)[0]
        right = struct.unpack_from("<h", pcm, i + 2)[0]
        struct.pack_into("<h", out, i // 2, (left + right) // 2)
    return bytes(out)


def _ssl_context() -> ssl.SSLContext:
    """python.org builds on macOS ship without a CA bundle; certifi has one."""
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


# clip -> (prompt, target_seconds). A placement click must be over before the
# next tap lands; the solve and lose cues have the end card to play under.
SOUNDS = {
    "place": ("a single soft wooden click, very short", 0.15),
    "mistake": ("a short dull thud, low, muted", 0.30),
    "solve": ("a bright three-note ascending chime, short", 0.90),
    "lose": ("two descending muted tones, brief", 0.90),
}

# Relative level per clip, in dB below full scale, applied on install over a
# -1 dBFS normalise, so the click heard on every entry does not match the
# solve cue for loudness.
MIX_DB = {
    "place": -8.0,
    "mistake": -6.0,
    "solve": -4.0,
    "lose": -4.0,
}


def generate(prompt: str, seconds: float, key: str) -> bytes:
    """One call to the sound-effects endpoint; returns raw 16-bit PCM."""
    body = json.dumps({
        "text": prompt,
        # the API floor is 0.5s; anything shorter gets trimmed here instead
        "duration_seconds": max(0.5, round(seconds + 0.2, 2)),
        "prompt_influence": 0.6,
    }).encode()
    req = urllib.request.Request(API, data=body, method="POST", headers={
        "xi-api-key": key,
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req, timeout=120, context=_ssl_context()) as r:
        return r.read()


def polish(pcm: bytes, seconds: float) -> bytes:
    """Trim the silent head, cut to length, fade out, normalise to -1 dBFS.

    Leading silence is the one defect a player feels rather than hears: on
    the placement click it reads as input lag.
    """
    if not pcm:
        return pcm
    pcm = _to_mono(pcm)
    peak = _peak(pcm) or 1
    gate = max(int(peak * 0.02), 64)

    start = 0
    for i in range(0, len(pcm) - 1, 2):
        if abs(struct.unpack_from("<h", pcm, i)[0]) > gate:
            start = i
            break
    start = max(0, start - int(0.005 * RATE) * 2)  # 5ms of pre-roll
    pcm = pcm[start:]

    want = int(seconds * RATE) * 2
    if len(pcm) > want:
        pcm = pcm[:want]

    # 12ms fade-out so a hard cut never clicks
    fade = min(int(0.012 * RATE), len(pcm) // 4)
    if fade > 0:
        tail = bytearray(pcm[-fade * 2:])
        for n in range(fade):
            off = n * 2
            v = struct.unpack_from("<h", tail, off)[0]
            struct.pack_into("<h", tail, off, int(v * (1 - n / fade)))
        pcm = pcm[:-fade * 2] + bytes(tail)

    peak = _peak(pcm) or 1
    return _scale(pcm, min(8.0, (32767 * 0.89) / peak))  # -1 dBFS


def write_wav(path: Path, pcm: bytes, channels: int = 1) -> None:
    with wave.open(str(path), "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm)


def _leveled(clip: str, src: Path) -> bytes:
    """The samples of src at the clip's mix level: what install writes, and
    so what an audition must play."""
    with wave.open(str(src), "rb") as w:
        if (w.getnchannels(), w.getsampwidth(), w.getframerate()) != (1, 2, RATE):
            sys.exit(f"sfx: {src} is not 44.1 kHz mono 16-bit")
        pcm = w.readframes(w.getnframes())
    return _scale(pcm, 10 ** (MIX_DB[clip] / 20.0))


def install(clip: str, src: Path, plan: str) -> None:
    """The whole swap: the clip at its mix level, the placeholder gone, the
    licence row and generation date recorded."""
    pcm = _leveled(clip, src)
    write_wav(DEST / f"{clip}.wav", pcm)
    placeholder = DEST / f"placeholder-{clip}.wav"
    if placeholder.exists():
        placeholder.unlink()

    text = LICENSES.read_text()
    row = (f"| `{clip}.wav` | ElevenLabs text-to-sound-effects | "
           f"ElevenLabs {plan} plan, commercial licence |\n")
    text = re.sub(rf"^\| `{re.escape(clip)}\.wav` \|.*\n", "", text, flags=re.M)
    text = text.replace("| File | Source | Licence |\n|---|---|---|\n",
                        "| File | Source | Licence |\n|---|---|---|\n" + row, 1)
    text = re.sub(rf"^\| `placeholder-{re.escape(clip)}\.wav` \|.*\n", "", text,
                  flags=re.M)
    generated = (f"**Generated:** {datetime.date.today().isoformat()}, on an "
                 f"ElevenLabs **{plan}** subscription, model "
                 "`eleven_text_to_sound_v2` via `POST /v1/sound-generation`.\n")
    if "**Generated:**" in text:
        text = re.sub(r"^\*\*Generated:\*\*.*?\n(?=\n|$)", generated, text,
                      flags=re.M | re.S)
    else:
        text = text.replace("\n## Placeholders", "\n" + generated + "\n## Placeholders", 1)
    LICENSES.write_text(text)
    print(f"  {clip}.wav  {MIX_DB[clip]:+.1f} dB  {len(pcm) / 2 / RATE:.2f}s  "
          f"placeholder removed, licence row added")


# What to do in the app to hear each clip.
HEAR = {
    "place": "place a number",
    "mistake": "enter a wrong number with mistakes shown",
    "solve": "solve a puzzle (4x4 is quickest)",
    "lose": "run out of strikes",
}


def candidates(clip: str, folder: Path) -> list:
    """The clip's takes in folder, in variant order (v10 after v9)."""
    takes = []
    for path in folder.glob(f"{clip}-v*.wav"):
        m = re.fullmatch(rf"{re.escape(clip)}-v(\d+)\.wav", path.name)
        if m:
            takes.append((int(m.group(1)), path))
    return [path for _, path in sorted(takes)]


def _ask(prompt: str):
    """One line from the owner, or None once stdin has closed."""
    try:
        return input(prompt)
    except EOFError:
        print()
        return None


def _pick(answer: str, heard: list):
    """The take the answer names -- `2`, `v2` or the file name -- or None."""
    a = answer.strip().lower()
    for take in heard:
        n = take.stem.rsplit("-v", 1)[1]
        if a in (n, f"v{n}", take.name.lower(), take.stem.lower()):
            return take
    return None


def audition(clip: str, folder: Path, device: str) -> int:
    """Play each candidate for clip through a release build on the phone, one
    at a time, then record the owner's pick.

    assets/audio/ is snapshotted first and restored in `finally`, so a failed
    build, Ctrl-C or a closed stdin leaves no candidate staged and the
    placeholder untouched.
    """
    takes = candidates(clip, folder)
    if not takes:
        print(f"sfx: no {clip}-v<N>.wav candidates in {folder}", file=sys.stderr)
        return 2
    staged = DEST / f"{clip}.wav"
    placeholder = DEST / f"placeholder-{clip}.wav"
    before = {p: (p.read_bytes() if p.exists() else None)
              for p in (staged, placeholder)}
    cmd = ["flutter", "run", "--release", "--no-resident"]
    if device:
        cmd += ["-d", device]
    heard = []
    try:
        for n, take in enumerate(takes, 1):
            write_wav(staged, _leveled(clip, take))
            print(f"\n[{n}/{len(takes)}] {clip}: now playing {take.name} "
                  f"({MIX_DB[clip]:+.1f} dB) -- building and launching",
                  flush=True)
            # stdin closed to flutter, so it cannot eat the owner's keypress.
            if subprocess.run(cmd, cwd=ROOT, stdin=subprocess.DEVNULL).returncode:
                print(f"sfx: flutter run failed on {take.name}; stopping",
                      file=sys.stderr)
                return 1
            heard.append(take)
            print(f"  {take.name} is on the phone: {HEAR[clip]} to hear it.")
            more = "for the next candidate" if n < len(takes) else "to choose"
            answer = _ask(f"  Enter {more}, q to stop: ")
            if answer is None or answer.strip().lower() == "q":
                break
        answer = (_ask(f"Winner for {clip} "
                       f"({', '.join(t.stem for t in heard)}; blank for none): ")
                  or "").strip()
        if not answer:
            return 0
        winner = _pick(answer, heard)
        if winner is None:
            print(f"sfx: {answer!r} is not a candidate you heard; "
                  "nothing recorded", file=sys.stderr)
            return 1
        record = folder / "selections.json"
        chosen = json.loads(record.read_text()) if record.exists() else {}
        chosen[clip] = winner.name
        record.write_text(json.dumps(chosen, indent=2, sort_keys=True) + "\n")
        print(f"{clip}: {winner.name} recorded in {record}")
        print(f"  install it with: tools/sfx.py --install {clip} {winner}")
        return 0
    finally:
        for path, data in before.items():
            if data is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(data)
        print(f"assets/audio/ restored: {staged.name} "
              f"{'as it was' if before[staged] is not None else 'removed'}, "
              f"{placeholder.name} "
              f"{'as it was' if before[placeholder] is not None else 'absent'}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir", nargs="?")
    ap.add_argument("--variants", type=int, default=3)
    ap.add_argument("--only", default="")
    ap.add_argument("--install", nargs=2, metavar=("CLIP", "FILE"),
                    help="install FILE as CLIP, replacing its placeholder")
    ap.add_argument("--plan", default="Creator",
                    help="the ElevenLabs plan the clip was generated on")
    ap.add_argument("--audition", metavar="CLIP",
                    help="play CLIP's candidates through the app on the phone")
    ap.add_argument("--dir", default=str(AUDITION_DIR),
                    help="where --audition finds <clip>-v<N>.wav")
    ap.add_argument("--device", default="",
                    help="the adb serial --audition runs on (default: the "
                         "one attached device)")
    args = ap.parse_args()

    if args.audition and args.install:
        ap.error("--audition and --install are separate steps")
    if args.audition:
        if args.audition not in SOUNDS:
            print(f"unknown clip: {args.audition}", file=sys.stderr)
            return 2
        return audition(args.audition, Path(args.dir), args.device)

    if args.install:
        clip, src = args.install
        if clip not in SOUNDS:
            print(f"unknown clip: {clip}", file=sys.stderr)
            return 2
        install(clip, Path(src), args.plan)
        return 0

    if not args.out_dir:
        ap.error("out_dir is required unless --install is given")
    # --install makes no network call, so the key is only required past here.
    key = os.environ.get("ELEVENLABS_API_KEY", "")
    if not key:
        print("ELEVENLABS_API_KEY is not set -- source the env file first", file=sys.stderr)
        return 2

    wanted = [k.strip() for k in args.only.split(",") if k.strip()] or list(SOUNDS)
    unknown = [k for k in wanted if k not in SOUNDS]
    if unknown:
        print(f"unknown clip(s): {', '.join(unknown)}", file=sys.stderr)
        return 2

    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    notes = []
    for name in wanted:
        prompt, seconds = SOUNDS[name]
        notes.append(f"{name}  ({seconds:.2f}s)\n    {prompt}")
        for v in range(1, args.variants + 1):
            try:
                pcm = polish(generate(prompt, seconds, key), seconds)
            except Exception as exc:  # noqa: BLE001 - report and continue
                print(f"  {name} v{v}: FAILED ({exc})")
                continue
            path = out / f"{name}-v{v}.wav"
            write_wav(path, pcm)
            print(f"  {name} v{v}: {len(pcm) / 2 / RATE:.2f}s  {path.name}")
    (out / "prompts.txt").write_text("\n".join(notes) + "\n")
    write_audition_page(out, wanted, args.variants)
    print(f"\n{len(wanted)} clips x {args.variants} variants -> {out}")
    print(f"audition: open {out / 'audition.html'}")
    return 0


def write_audition_page(out: Path, names: list, variants: int) -> None:
    """A local page for picking winners by ear, with each clip's prompt and
    length budget in view."""
    rows = []
    for name in names:
        prompt, seconds = SOUNDS[name]
        players = "".join(
            f'<div class="v"><span>v{v}</span>'
            f'<audio controls preload="none" src="{name}-v{v}.wav"></audio></div>'
            for v in range(1, variants + 1)
            if (out / f"{name}-v{v}.wav").exists()
        )
        rows.append(
            f'<section><h2>{name} <em>{seconds:.2f}s</em></h2>'
            f'<p>{prompt}</p><div class="row">{players}</div></section>'
        )
    (out / "audition.html").write_text(
        "<!doctype html><meta charset=utf-8><title>Honest Sudoku - SFX audition</title>"
        "<style>"
        "body{font:15px/1.5 system-ui,sans-serif;background:#05285F;color:#fff;margin:0;padding:32px}"
        "h1{font-size:26px;margin:0 0 4px}h1+p{color:#9FC3EE;margin:0 0 28px}"
        "section{background:rgba(255,255,255,.06);border-radius:14px;padding:16px 20px;margin:0 0 14px}"
        "h2{font-size:19px;margin:0 0 2px}h2 em{color:#00D6B4;font-style:normal;font-size:14px;margin-left:8px}"
        "section p{color:#9FC3EE;font-size:13px;margin:0 0 12px}"
        ".row{display:flex;flex-wrap:wrap;gap:16px}"
        ".v{display:flex;align-items:center;gap:8px}.v span{color:#6E93C4;font-size:13px;width:20px}"
        "audio{height:34px}"
        "</style>"
        "<h1>Honest Sudoku &mdash; sound audition</h1>"
        "<p>Takes per clip. Install the winner with "
        "<code>tools/sfx.py --install &lt;clip&gt; &lt;file&gt;</code>.</p>"
        + "".join(rows)
    )


if __name__ == "__main__":
    raise SystemExit(main())
