#!/usr/bin/env python3
"""Synthesise the four placeholder sounds (#49), deterministically.

Python 3 standard library only. Each clip is 44.1 kHz mono 16-bit PCM,
peaking at -6 dBFS:

  place    40 ms   1400 Hz sine, 5 ms attack, exponential decay
  mistake  140 ms  110 Hz square (70 %) plus seeded white noise (30 %),
                   faded out over the last 40 ms
  solve    450 ms  660, 880, 1100 Hz, 120 ms each with 40 ms gaps
  lose     500 ms  440, 330 Hz, 200 ms each with a 60 ms gap

Every tone has a 5 ms linear attack and a 20 ms release; each total includes
trailing silence to its round figure.

The files are MIT-covered like the code. Real clips replace them by dropping
`<clip>.wav` beside them, deleting the placeholder and adding a licence row
(`tools/sfx.py --install` does all three). This script also rewrites the
placeholder digests in assets/audio/LICENSES.md, which the audio guard checks.

Usage:  tools/make_placeholder_sfx.py [--out DIR] [--check]
Exit:   0 written (or, with --check, the committed files are byte-identical)
        1 --check found a difference
"""
from __future__ import annotations

import argparse
import io
import math
import pathlib
import re
import sys
import tempfile
import wave

RATE = 44100
PEAK = 10 ** (-6 / 20)
ROOT = pathlib.Path(__file__).resolve().parent.parent
AUDIO = ROOT / "assets" / "audio"
LICENSES = AUDIO / "LICENSES.md"


def ms(n: float) -> int:
    return round(n * RATE / 1000)


def tone(freq: float, length_ms: float) -> list[float]:
    """A sine with a 5 ms linear attack and a 20 ms linear release."""
    n, attack, release = ms(length_ms), ms(5), ms(20)
    out = []
    for i in range(n):
        env = min(1.0, i / attack, (n - i) / release)
        out.append(env * math.sin(2 * math.pi * freq * i / RATE))
    return out


def silence(length_ms: float) -> list[float]:
    return [0.0] * ms(length_ms)


def pad(samples: list[float], total_ms: float) -> list[float]:
    return samples + [0.0] * (ms(total_ms) - len(samples))


def place() -> list[float]:
    n, attack = ms(30), ms(5)
    out = []
    for i in range(n):
        env = i / attack if i < attack else math.exp(-(i - attack) / ms(6))
        out.append(env * math.sin(2 * math.pi * 1400 * i / RATE))
    return pad(out, 40)


def mistake() -> list[float]:
    n, fade = ms(140), ms(40)
    state = 20260824
    out = []
    for i in range(n):
        # A 32-bit LCG (Numerical Recipes' constants): the same noise on
        # every machine, unlike `random`, whose algorithm is not promised.
        state = (1664525 * state + 1013904223) & 0xFFFFFFFF
        noise = state / 0x7FFFFFFF - 1.0
        square = 1.0 if math.sin(2 * math.pi * 110 * i / RATE) >= 0 else -1.0
        env = min(1.0, i / ms(5), (n - i) / fade)
        out.append(env * (0.7 * square + 0.3 * noise))
    return out


def solve() -> list[float]:
    out: list[float] = []
    for k, freq in enumerate((660, 880, 1100)):
        if k:
            out += silence(40)
        out += tone(freq, 120)
    return pad(out, 450)


def lose() -> list[float]:
    return pad(tone(440, 200) + silence(60) + tone(330, 200), 500)


CLIPS = {"place": place, "mistake": mistake, "solve": solve, "lose": lose}


def encode(samples: list[float]) -> bytes:
    top = max(abs(s) for s in samples) or 1.0
    scale = PEAK * 32767 / top
    pcm = b"".join(
        max(-32768, min(32767, round(s * scale))).to_bytes(2, "little", signed=True)
        for s in samples
    )
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm)
    return buf.getvalue()


def fnv1a64(data: bytes) -> str:
    """The golden fixtures' 64-bit FNV-1a (test/helpers/board_hash.dart)."""
    h = 0xCBF29CE484222325
    for b in data:
        h ^= b
        h = (h * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return f"{h:016x}"


def write(out: pathlib.Path) -> dict[str, str]:
    out.mkdir(parents=True, exist_ok=True)
    digests = {}
    for name, make in CLIPS.items():
        if out.resolve() == AUDIO.resolve() and (AUDIO / f"{name}.wav").exists():
            continue  # the real clip has landed; its placeholder stays gone
        data = encode(make())
        (out / f"placeholder-{name}.wav").write_bytes(data)
        digests[f"placeholder-{name}.wav"] = fnv1a64(data)
    return digests


def record(digests: dict[str, str]) -> None:
    """Rewrites the placeholder table in LICENSES.md, for the files present."""
    text = LICENSES.read_text()
    rows = "".join(
        f"| `{f}` | `{d}` | tools/make_placeholder_sfx.py |\n"
        for f, d in digests.items()
        if (AUDIO / f).exists()
    )
    table = "| File | FNV-1a | Source |\n|---|---|---|\n" + rows
    new, n = re.subn(
        r"<!-- placeholders:begin -->\n.*?<!-- placeholders:end -->",
        f"<!-- placeholders:begin -->\n{table}<!-- placeholders:end -->",
        text,
        flags=re.S,
    )
    if n != 1:
        sys.exit("make_placeholder_sfx: LICENSES.md has no placeholders markers")
    LICENSES.write_text(new)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=pathlib.Path, default=AUDIO)
    ap.add_argument("--check", action="store_true",
                    help="regenerate to a temp dir and compare with the committed files")
    args = ap.parse_args()
    if args.check:
        with tempfile.TemporaryDirectory() as tmp:
            write(pathlib.Path(tmp))
            differs = []
            for name in CLIPS:
                f = f"placeholder-{name}.wav"
                committed = AUDIO / f
                if committed.exists() and committed.read_bytes() != (pathlib.Path(tmp) / f).read_bytes():
                    differs.append(f)
        for f in differs:
            print(f"make_placeholder_sfx: {f} differs from a fresh synthesis", file=sys.stderr)
        return 1 if differs else 0
    digests = write(args.out)
    if args.out.resolve() == AUDIO.resolve():
        record(digests)
    for f, d in digests.items():
        print(f"  {f}  {d}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
