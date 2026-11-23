#!/usr/bin/env python3
"""Writes the test takes for assets/examples/sounds.json into <out-dir>/sfx/: synthetic, original
sounds with the faults generated takes really have.

  SwordHit_1  clean hit, loud at once                        (approved)
  SwordHit_2  the same hit after 450 ms of silence           (picked)    -> lag, fixed by trim
  SwordHit_3  builds up for 400 ms before it hits            (generated) -> hits too late, not fixable
  Footstep_1  short thud                                     (approved)
  Footstep_2  short thud, slightly different                 (uploaded)
  Footstep_3  thud driven into clipping, 8 dB too loud       (generated) -> clipping, loudness
  Pickup_1    chime that swells for 600 ms, 1.6 s long       (generated) -> build-up, too long
  UiHover_1   silence                                         (generated) -> empty
Usage: make_sounds.py <out-dir>
"""

import math
import os
import random
import sys
import wave
from array import array

RATE = 48000


def write(path, samples):
    data = array("h", (max(-32768, min(32767, int(s * 32767))) for s in samples))
    if sys.byteorder == "big":
        data.byteswap()
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data.tobytes())


def silence(seconds):
    return [0.0] * int(seconds * RATE)


def hit(seconds=0.6, ring=1400.0, seed=1, gain=0.5):
    rng = random.Random(seed)
    out = []
    for i in range(int(seconds * RATE)):
        t = i / RATE
        noise = rng.uniform(-1, 1) * math.exp(-t / 0.03)
        tone = math.sin(2 * math.pi * ring * t) * math.exp(-t / 0.18) * 0.6
        out.append(gain * (noise + tone))
    return out


def thud(seconds=0.25, seed=2, gain=0.55, freq=90.0):
    rng = random.Random(seed)
    return [gain * (math.sin(2 * math.pi * freq * i / RATE) + 0.3 * rng.uniform(-1, 1)) * math.exp(-(i / RATE) / 0.05) for i in range(int(seconds * RATE))]


def swell(rise, seconds, freq=1800.0, gain=0.4):
    out = []
    for i in range(int(seconds * RATE)):
        t = i / RATE
        envelope = (t / rise) ** 2 if t < rise else math.exp(-(t - rise) / 0.15)
        out.append(gain * envelope * math.sin(2 * math.pi * freq * t))
    return out


def main():
    out = os.path.join(sys.argv[1], "sfx")
    os.makedirs(out, exist_ok=True)
    takes = {
        "SwordHit_1": hit(),
        "SwordHit_2": silence(0.45) + hit(seed=3),
        "SwordHit_3": swell(0.4, 0.7, freq=700.0, gain=0.5),
        "Footstep_1": thud(),
        "Footstep_2": thud(seed=5, freq=100.0),
        "Footstep_3": [max(-1.0, min(1.0, s * 3)) for s in thud(seed=7)],
        "Pickup_1": swell(0.6, 1.6),
        "UiHover_1": silence(0.15),
    }
    for name, samples in takes.items():
        write(os.path.join(out, f"{name}.wav"), samples)
    print(f"wrote {len(takes)} takes to {out}")


if __name__ == "__main__":
    main()
