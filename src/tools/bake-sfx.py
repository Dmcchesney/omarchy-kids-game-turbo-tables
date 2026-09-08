"""Turbo Tables sound effects -- synthesised from this file, never downloaded.

THIS SCRIPT IS THE ASSET. The same doctrine as the car and prop bakes: the
sounds under assets/sfx/ are produced by running this, so what is reviewable is
text rather than a binary somebody fetched from a web page with an unknown
licence. Nothing is downloaded, nothing is sampled, and there is no dependency
beyond the Python standard library -- `wave` writes plain PCM and `math` does
the rest.

  python3 src/tools/bake-sfx.py --out assets/sfx
  python3 src/tools/bake-sfx.py --out DIR --only wrench-clang,hit

Driven by `npm run sfx`; `npm run check:sfx` holds the committed files to
assets/sfx/manifest.json. Deterministic: every cue is a fixed function of the
constants below and of one seeded LCG, so a rebake reproduces the committed
bytes exactly and the check can prove it.

WHAT THE CUES ARE. One per line of the "Sound" rows of docs/design.md v4's
"Power-up feel" section, quoted in the table at the bottom of this file. The
design is the specification for the SHAPE of each sound -- "spool up, bang,
sustained rush", "four metallic clicks", "thud, rattle, hubcap ring" -- and the
envelopes below are built to those shapes, beat by beat.

NOBODY HAS HEARD THESE. No agent in the build loop can hear, and the check that
ships with them measures format, duration and envelope, not sound. That is
stated here, in the file that makes them, so it cannot be lost between a report
and a README: what is verified is that the files exist, are PCM WAV of the
declared rate and depth, are the declared length, and have the peak-and-decay
shape their cue asks for. Whether a child would call any of them a clang is
unmeasured and unclaimed.
"""

import argparse
import hashlib
import json
import math
import os
import struct
import wave

RATE = 22050
DEPTH = 16
CHANNELS = 1


# --------------------------------------------------------------------------
# The primitives
# --------------------------------------------------------------------------

class Noise:
    """A seeded linear congruential generator, so a bake is reproducible.

    Python's `random` is seedable too, but its Mersenne Twister stream is a
    promise the standard library does not make across versions, and a bake that
    changes bytes when Python is upgraded cannot be held to a manifest. This is
    thirty-one bits of Lehmer, whose stream is fixed by its own arithmetic.
    """

    def __init__(self, seed):
        self.state = (seed * 48271 + 11) % 2147483647 or 1

    def next(self):
        self.state = (self.state * 48271) % 2147483647
        return self.state / 2147483647.0 * 2.0 - 1.0


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def mix(base, other, at):
    """Add `other` into `base` starting at `at` seconds, growing `base`."""
    start = int(RATE * at)
    need = start + len(other)
    if need > len(base):
        base.extend([0.0] * (need - len(base)))
    for i, v in enumerate(other):
        base[start + i] += v
    return base


def env_ad(n, attack, decay, curve=2.0):
    """Attack-decay envelope, both in samples, decay shaped by `curve`."""
    out = []
    for i in range(n):
        if i < attack:
            out.append((i / max(1, attack)) ** 0.6)
        else:
            u = (i - attack) / max(1, decay)
            out.append(max(0.0, 1.0 - u) ** curve if u < 1 else 0.0)
    return out


def osc(seconds, f0, f1, amp, shape="sine", curve=1.0, attack=0.004, decay=None):
    """One swept oscillator with an attack-decay envelope.

    `shape` is "sine", "saw" or "square"; the two harmonic-rich shapes are what
    an engine and a siren want, and the sine is what a tick and a ring want.
    """
    n = int(RATE * seconds)
    decay = seconds if decay is None else decay
    env = env_ad(n, int(RATE * attack), int(RATE * decay), curve)
    out = []
    phase = 0.0
    for i in range(n):
        u = i / max(1, n - 1)
        f = f0 + (f1 - f0) * (u ** curve)
        phase += 2 * math.pi * f / RATE
        if shape == "sine":
            v = math.sin(phase)
        elif shape == "saw":
            v = 2.0 * ((phase / (2 * math.pi)) % 1.0) - 1.0
        else:
            v = 1.0 if math.sin(phase) >= 0 else -1.0
        out.append(v * env[i] * amp)
    return out


def hiss(seconds, amp, rng, low=0.0, high=1.0, curve=2.0, attack=0.002):
    """Filtered noise: a one-pole low pass and a one-pole high pass in series.

    `low` and `high` are 0..1 fractions of the Nyquist. It is the cheapest
    filter there is and it is enough: every noise in this file is a whoosh, a
    hiss, a rattle or a crash, and none of them needs a resonant filter.
    """
    n = int(RATE * seconds)
    env = env_ad(n, int(RATE * attack), n, curve)
    lp, hp, prev = 0.0, 0.0, 0.0
    a_lp = max(0.001, min(1.0, high))
    a_hp = max(0.0, min(0.999, low))
    out = []
    for i in range(n):
        x = rng.next()
        lp += a_lp * (x - lp)
        hp = a_hp * (hp + lp - prev)
        prev = lp
        out.append((lp - hp) * env[i] * amp)
    return out


def clang(seconds, base, amp, rng, partials=(1.0, 2.76, 5.40, 8.93)):
    """A struck-metal hit: inharmonic partials over a short noise transient.

    The ratios are a circular membrane's, which is what makes a bell or a
    wrench on a body panel read as metal rather than as a musical note.
    """
    out = [0.0] * int(RATE * seconds)
    for k, ratio in enumerate(partials):
        part = osc(seconds * (1.0 - 0.14 * k), base * ratio, base * ratio * 0.985,
                   amp / (1.6 + k), "sine", 1.0, 0.001, seconds * (0.8 - 0.12 * k))
        for i, v in enumerate(part):
            out[i] += v
    transient = hiss(0.020, amp * 0.8, rng, 0.30, 0.95, 3.0, 0.0005)
    for i, v in enumerate(transient):
        out[i] += v
    return out


def normalise(samples, peak=0.86):
    high = max((abs(v) for v in samples), default=0.0)
    if high <= 0:
        return samples
    k = peak / high
    return [v * k for v in samples]


def write_wav(path, samples):
    data = b"".join(
        struct.pack("<h", max(-32768, min(32767, int(round(v * 32767)))))
        for v in samples
    )
    with wave.open(path, "wb") as w:
        w.setnchannels(CHANNELS)
        w.setsampwidth(DEPTH // 8)
        w.setframerate(RATE)
        w.writeframes(data)


# --------------------------------------------------------------------------
# The cues. One function per line of the design's Sound rows.
# --------------------------------------------------------------------------

def cue_nitro(rng):
    """Nitro: "short whoosh, four rising ticks"."""
    out = hiss(0.34, 0.7, rng, 0.10, 0.55, 2.4, 0.030)
    for k in range(4):
        mix(out, osc(0.070, 900 + k * 260, 1150 + k * 300, 0.42, "sine", 1.0, 0.001, 0.060),
            0.06 + k * 0.075)
    return out


def cue_turbo(rng):
    """Turbo: "spool up, bang, sustained rush"."""
    out = osc(0.26, 240, 1750, 0.34, "saw", 2.2, 0.05, 0.26)          # spool up
    mix(out, hiss(0.030, 0.95, rng, 0.02, 0.98, 3.0, 0.0005), 0.255)  # bang
    mix(out, osc(0.055, 150, 52, 0.75, "sine", 1.2, 0.001, 0.055), 0.255)
    mix(out, hiss(0.95, 0.45, rng, 0.06, 0.42, 1.4, 0.020), 0.29)     # sustained rush
    return out


def cue_oilslick(rng):
    """Oil Slick: "splat"."""
    out = hiss(0.16, 0.8, rng, 0.02, 0.30, 3.2, 0.002)
    mix(out, osc(0.10, 180, 60, 0.5, "sine", 1.6, 0.001, 0.10), 0.0)
    return out


def cue_squeal(rng):
    """Oil Slick: one of the "three squeals staggered by 120"."""
    out = osc(0.42, 1500, 980, 0.38, "saw", 1.5, 0.02, 0.42)
    mix(out, osc(0.42, 1512, 995, 0.28, "saw", 1.5, 0.02, 0.42), 0.004)
    mix(out, hiss(0.42, 0.18, rng, 0.40, 0.85, 1.6, 0.02), 0.0)
    return out


def cue_wrench_flight(rng):
    """Wrench: "whirr in flight" -- 500 ms, the length of the telegraph."""
    out = [0.0] * int(RATE * 0.50)
    # A whirr is a pitch that wobbles: a spinning wrench passing its own axis
    # about twelve times over the flight.
    n = len(out)
    phase = 0.0
    for i in range(n):
        u = i / max(1, n - 1)
        f = 300 + 120 * math.sin(u * 2 * math.pi * 12) + 260 * u
        phase += 2 * math.pi * f / RATE
        env = min(1.0, u * 12) * (1.0 - 0.25 * u)
        out[i] = math.sin(phase) * 0.34 * env
    mix(out, hiss(0.50, 0.12, rng, 0.25, 0.80, 0.8, 0.03), 0.0)
    return out


def cue_wrench_clang(rng):
    """Wrench: "clang on impact"."""
    return clang(0.46, 620, 0.55, rng)


def cue_pothole(rng):
    """Pothole: "thud, rattle"."""
    out = osc(0.17, 120, 42, 0.9, "sine", 1.5, 0.001, 0.17)           # thud
    mix(out, hiss(0.12, 0.55, rng, 0.02, 0.35, 3.0, 0.001), 0.0)
    for k in range(7):                                                # rattle
        mix(out, clang(0.075, 1500 + k * 90, 0.16, rng, (1.0, 2.4, 4.1)),
            0.13 + k * 0.048)
    return out


def cue_hubcap(rng):
    """Pothole: "hubcap ring" -- a ring that settles into a spin on the tarmac."""
    out = clang(0.80, 980, 0.42, rng, (1.0, 2.76, 5.40))
    for k in range(9):
        mix(out, clang(0.045, 900, 0.10 + 0.02 * k, rng, (1.0, 3.0)),
            0.45 + 0.075 * k - 0.0035 * k * k)
    return out


def cue_pileup(rng):
    """Pile-Up: "siren blip, crash with debris, a long hiss"."""
    out = osc(0.13, 760, 1180, 0.34, "square", 1.0, 0.01, 0.13)       # siren blip
    mix(out, osc(0.13, 1180, 760, 0.34, "square", 1.0, 0.01, 0.13), 0.14)
    mix(out, hiss(0.34, 0.95, rng, 0.02, 0.92, 2.0, 0.001), 0.30)     # crash
    mix(out, osc(0.26, 96, 34, 0.85, "sine", 1.4, 0.001, 0.26), 0.30)
    for k in range(11):                                               # debris
        mix(out, clang(0.10, 700 + k * 130, 0.15, rng, (1.0, 2.76, 5.4)),
            0.34 + 0.052 * k)
    mix(out, hiss(1.30, 0.34, rng, 0.35, 0.80, 1.1, 0.06), 0.62)      # long hiss
    return out


def cue_rollcage(rng):
    """Roll Cage: "four metallic clicks"."""
    out = [0.0] * int(RATE * 0.42)
    for k in range(4):
        mix(out, clang(0.085, 1750 + k * 210, 0.34, rng, (1.0, 2.9, 5.1)),
            0.010 + k * 0.075)
    return out


def cue_block(rng):
    """Roll Cage: "the clang when it earns its keep"."""
    out = clang(0.62, 460, 0.72, rng, (1.0, 2.76, 5.40, 8.93, 11.7))
    mix(out, hiss(0.30, 0.30, rng, 0.30, 0.95, 2.2, 0.001), 0.0)
    return out


def cue_towhook(rng):
    """Tow Hook: "winch, whip-crack, the rival's engine dopplering past"."""
    out = osc(0.40, 130, 210, 0.30, "saw", 1.0, 0.02, 0.40)           # winch
    for k in range(16):
        mix(out, osc(0.012, 620, 520, 0.10, "sine", 1.0, 0.0005, 0.012), 0.02 + k * 0.023)
    mix(out, hiss(0.045, 0.95, rng, 0.20, 0.98, 3.4, 0.0004), 0.40)   # whip-crack
    # the doppler: the rival's engine sweeping up and then falling away
    mix(out, osc(0.30, 190, 320, 0.34, "saw", 1.0, 0.03, 0.30), 0.44)
    mix(out, osc(0.42, 320, 120, 0.34, "saw", 1.0, 0.01, 0.42), 0.74)
    return out


def cue_hit(rng):
    """Being hit: the crunch under the engine-hit banner."""
    out = osc(0.20, 150, 46, 0.85, "sine", 1.4, 0.001, 0.20)
    mix(out, hiss(0.16, 0.70, rng, 0.02, 0.60, 2.6, 0.001), 0.0)
    mix(out, clang(0.30, 380, 0.32, rng), 0.02)
    return out


def cue_deal(rng):
    """The hand: "three cards that slide up from the bottom right with a deal sound"."""
    out = [0.0] * int(RATE * 0.42)
    for k in range(3):
        mix(out, hiss(0.085, 0.42, rng, 0.30, 0.90, 2.6, 0.006), 0.02 + k * 0.085)
        mix(out, osc(0.075, 520 + k * 150, 780 + k * 180, 0.24, "sine", 1.0, 0.004, 0.070),
            0.02 + k * 0.085)
    return out


def cue_slam(rng):
    """The hand: the chosen card "slams down and dissolves into the telegraph"."""
    out = osc(0.11, 300, 90, 0.55, "sine", 1.6, 0.001, 0.11)
    mix(out, hiss(0.075, 0.50, rng, 0.10, 0.70, 3.0, 0.001), 0.0)
    return out


# The catalogue. `event` is the cue name ui/parts/Sfx.qml routes to; `shape` is
# the design's own words for it, kept beside the code that makes it so the two
# can be compared without leaving the file.
CUES = [
    ("nitro",         cue_nitro,         "Nitro: short whoosh, four rising ticks"),
    ("turbo",         cue_turbo,         "Turbo: spool up, bang, sustained rush"),
    ("oilslick",      cue_oilslick,      "Oil Slick: splat"),
    ("squeal",        cue_squeal,        "Oil Slick: one of three squeals staggered by 120"),
    ("wrench-flight", cue_wrench_flight, "Wrench: whirr in flight"),
    ("wrench-clang",  cue_wrench_clang,  "Wrench: clang on impact"),
    ("pothole",       cue_pothole,       "Pothole: thud, rattle"),
    ("hubcap",        cue_hubcap,        "Pothole: hubcap ring"),
    ("pileup",        cue_pileup,        "Pile-Up: siren blip, crash with debris, a long hiss"),
    ("rollcage",      cue_rollcage,      "Roll Cage: four metallic clicks"),
    ("block",         cue_block,         "Roll Cage: the clang when it earns its keep"),
    ("towhook",       cue_towhook,       "Tow Hook: winch, whip-crack, the rival's engine dopplering past"),
    ("hit",           cue_hit,           "Being hit: the crunch under the engine-hit banner"),
    ("deal",          cue_deal,          "The hand: three cards dealt"),
    ("slam",          cue_slam,          "The hand: the chosen card slams down"),
]


def peak_at(samples):
    """Where the loudest sample is, as a fraction of the cue's length.

    The check tool asserts this against the shape the design asks for: a clang
    peaks at its front, a spool-up does not, and a cue whose peak has wandered
    to the wrong end is a cue whose envelope broke.
    """
    if not samples:
        return 0.0
    best, at = 0.0, 0
    for i, v in enumerate(samples):
        if abs(v) > best:
            best, at = abs(v), i
    return at / max(1, len(samples) - 1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--only", default="")
    args = parser.parse_args()
    only = [name for name in args.only.split(",") if name]
    os.makedirs(args.out, exist_ok=True)

    entries = {}
    for index, (name, make, shape) in enumerate(CUES):
        if only and name not in only:
            continue
        # One generator per cue, seeded from its position in the catalogue, so
        # `--only` reproduces exactly what a full bake produces.
        samples = normalise(make(Noise(1000 + index * 7919)))
        path = os.path.join(args.out, name + ".wav")
        write_wav(path, samples)
        digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
        entries[name + ".wav"] = {
            "sha256": digest,
            "ms": round(len(samples) / RATE * 1000),
            "peak": round(peak_at(samples), 3),
            "shape": shape,
        }
        print("baked %-16s %6d ms  peak at %.2f  %s"
              % (name, entries[name + ".wav"]["ms"], entries[name + ".wav"]["peak"], digest[:12]))

    manifest_path = os.path.join(args.out, "manifest.json")
    manifest = {"rate": RATE, "channels": CHANNELS, "depth": DEPTH, "files": {}}
    if only and os.path.exists(manifest_path):
        with open(manifest_path) as handle:
            manifest = json.load(handle)
    manifest["files"].update(entries)
    manifest["files"] = dict(sorted(manifest["files"].items()))
    with open(manifest_path, "w") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print("wrote %s with %d cue(s)" % (manifest_path, len(manifest["files"])))


if __name__ == "__main__":
    main()
