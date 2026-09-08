"""Measure the committed car sheets. The metrics a critic reproduced, plus the
ones round 3 did not have, each with its exclusions written into the code.

  python3 src/tools/carstats.py dims     [--bodies ...] [--cells ...]
  python3 src/tools/carstats.py glass    [--bodies ...] [--paint red]
  python3 src/tools/carstats.py rim      [--bodies ...] [--paint red]
  python3 src/tools/carstats.py matrix   [--cells stall192,road48,...] [--yaws all]
  python3 src/tools/carstats.py hue      [--bodies ...]
  python3 src/tools/carstats.py tailbar  [--bodies ...]

Why this file exists: round 3 reported a "rim" figure of 5.3 % that a critic
reproduced to the decimal and then took apart -- 47 to 93 % of the pixels it
counted were the fixed tail-lamp glow strip `ffb3a0`, a sheet colour with
nothing to do with rim light, and on the true body edge the same sprites had
0.0 %. A metric that cannot fail is worse than no metric, so every count here
names what it excludes, and the exclusions are constants at the top.

Sheet layout is read from pxart.py, never restated.

Definitions, once:

  body       pixels with alpha == 255. The contact shadow bakes at alpha 128
             and is therefore never a body pixel.
  perimeter  body pixels with at least one non-body 4-neighbour, or a body
             pixel on the cell border.
  outward    at a perimeter pixel, the normalised sum of the offsets to its
             non-body 8-neighbours: the direction that points out of the car.
  sun side   a perimeter pixel whose outward direction has a positive dot
             product with the screen-space sun direction for that camera
             (SUN_SCREEN below), which is derived from bake-cars.py's RIM_DIR
             projected through that camera's basis, not chosen by eye.
  rim        a sun-side perimeter pixel carrying the paint ramp's `high` step
             or the warm rim tone. Lamp, glow, headlamp and cream tones are
             excluded from BOTH the numerator and the denominator, because
             they are fixed sheet colours that no lighting decision moves.
"""
import json
import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pxart import (CAMERAS, CELL, ROW_Y, SCALES, SHEET_W, YAWS, hex2rgb,  # noqa: E402
                   paint_ramp, read_png)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# --karts DIR points every measurement at another tree's assets/karts, which is
# how a before/after is produced without two checkouts of this file.
KARTS = os.path.join(ROOT, "assets", "karts")
if "--karts" in sys.argv:
    KARTS = sys.argv[sys.argv.index("--karts") + 1]
BODIES = ["coupe", "hatch", "wedge", "saloon", "buggy", "pickup"]

# Fixed sheet tones that are never paint and never lighting. Excluded from the
# rim's numerator and denominator alike.
LAMP_HEX = ["f01a1a", "ffb3a0", "ffd489"]
CREAM_HEX = ["b09a6d", "d9c79a", "f2e6c4"]
INK_HEX = ["280e27"]
NEUTRAL_HEX = ["0b0c12", "1a1b26", "2a2b3d", "414868", "6b7291", "a9b1d6"]
RIM_HEX = ["f0b07a"]          # the warm rim tone, if the sheet ever carries one
GLASS_HEX = ["343a52", "4d5573"]   # the glass tones, used by nothing but windows
LAMP = {hex2rgb(h) for h in LAMP_HEX}
CREAM = {hex2rgb(h) for h in CREAM_HEX}
INK = {hex2rgb(h) for h in INK_HEX}
NEUTRAL = {hex2rgb(h) for h in NEUTRAL_HEX}
RIMTONE = {hex2rgb(h) for h in RIM_HEX}
GLASS = {hex2rgb(h) for h in GLASS_HEX}

# The screen-space sun comes from pxart.py, which is what the bake itself used
# to decide where the rim goes: one definition, so this file cannot flatter the
# sprite by measuring a different sun. The fallback exists only so that this
# same file can measure a tree baked BEFORE the rim existed, where pxart.py has
# no SUN_SCREEN -- that is how the before/after table in the evidence is made.
try:
    from pxart import SUN_SCREEN  # noqa: E402
except ImportError:                                      # pragma: no cover
    SUN_SCREEN = {"stall": (0.7181, -0.6960), "road": (0.5926, -0.8055)}

# The cells the game actually draws, and where.
DRAWN = {
    "stall192": ("stall", 0, "garage dais GarageStall.qml / Garage.qml, countdown Countdown.qml"),
    "stall96": ("stall", 1, "roster slot RosterSlot.qml -- the pick screen"),
    "stall48": ("stall", 2, "small stall"),
    "road192": ("road", 0, "countdown road camera"),
    "road96": ("road", 1, "road half"),
    "road48": ("road", 2, "track TrackView.qml"),
}


def arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def sheet(body, paint):
    return read_png(os.path.join(KARTS, body, f"{paint}.png"))


def meta(body):
    with open(os.path.join(KARTS, body, "meta.json")) as f:
        return json.load(f)


def cell(px, cam, scale_i, yaw):
    """One cell out of a sheet, as (w, h, rgba bytearray)."""
    div = SCALES[scale_i]
    cw, ch = CELL[0] // div, CELL[1] // div
    ox = yaw * cw
    oy = ROW_Y[CAMERAS.index(cam) * 3 + scale_i]
    out = bytearray(cw * ch * 4)
    for y in range(ch):
        s = ((oy + y) * SHEET_W + ox) * 4
        out[y * cw * 4:(y + 1) * cw * 4] = px[s:s + cw * 4]
    return cw, ch, out


def body_mask(w, h, c):
    return [c[(y * w + x) * 4 + 3] == 255 for y in range(h) for x in range(w)]


def tone(c, w, x, y):
    i = (y * w + x) * 4
    return (c[i], c[i + 1], c[i + 2])


def bbox(w, h, m):
    xs = [x for y in range(h) for x in range(w) if m[y * w + x]]
    ys = [y for y in range(h) for x in range(w) if m[y * w + x]]
    if not xs:
        return None
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


# ------------------------------------------------------------------ dims
def cmd_dims(bodies, paint):
    print("Silhouette bounding box of the alpha==255 body, per drawn cell, yaw 0.")
    print("Ink outline is part of the body here: it is what a cut-out sees.\n")
    head = "| body | " + " | ".join(DRAWN) + " |"
    print(head)
    print("|---" * (len(DRAWN) + 1) + "|")
    for b in bodies:
        _w, _h, px = sheet(b, paint)
        row = [b]
        for key, (cam, si, _note) in DRAWN.items():
            cw, ch, c = cell(px, cam, si, 0)
            bb = bbox(cw, ch, body_mask(cw, ch, c))
            row.append(f"{bb[2] - bb[0]}x{bb[3] - bb[1]}")
        print("| " + " | ".join(row) + " |")


# ------------------------------------------------------------------ glass
def cmd_glass(bodies, paint):
    """The glasshouse: what the top third of the body is made of.

    Band = the top third of the body bounding box, which is where a
    greenhouse lives on every one of these bodies. The ink outline is
    excluded (it is the silhouette, not the surface). Everything else is
    classed by its exact palette tone."""
    ramp = paint_ramp(open_paint_hex(paint))
    names = {tuple(ramp[0]): "deep", tuple(ramp[1]): "shade", tuple(ramp[2]): "base", tuple(ramp[3]): "high"}
    print(f"Glasshouse, paint {paint}: composition of the top third of the body.")
    print("`glass` is 343a52 and 4d5573, which nothing but a window uses; `ink` is the")
    print("outline tone 280e27; `dark` is 0b0c12 and 1a1b26. Round 3's windows WERE the")
    print("ink tone, so the ink column is the one that had to come down and the glass")
    print("column the one that had to exist at all.\n")
    print("| body | cell | paint base+high % | glass % | ink % | dark % | cream % |")
    print("|---|---|---:|---:|---:|---:|---:|")
    for b in bodies:
        _w, _h, px = sheet(b, paint)
        for key in ("stall192", "stall96", "road192", "road48"):
            cam, si, _n = DRAWN[key]
            cw, ch, c = cell(px, cam, si, 0)
            m = body_mask(cw, ch, c)
            bb = bbox(cw, ch, m)
            y1 = bb[1] + max(1, round((bb[3] - bb[1]) / 3))
            counts = {}
            total = 0
            for y in range(bb[1], y1):
                for x in range(bb[0], bb[2]):
                    if not m[y * cw + x]:
                        continue
                    t = tone(c, cw, x, y)
                    total += 1
                    k = names.get(t, "glass" if t in GLASS
                                  else "ink" if t in INK
                                  else "dark" if t in {hex2rgb("0b0c12"), hex2rgb("1a1b26")}
                                  else "cream" if t in CREAM else "other")
                    counts[k] = counts.get(k, 0) + 1
            if total == 0:
                continue
            pc = lambda k: 100.0 * counts.get(k, 0) / total  # noqa: E731
            print(f"| {b} | {key} | {pc('base') + pc('high'):.1f} | {pc('glass'):.1f} | "
                  f"{pc('ink'):.1f} | {pc('dark'):.1f} | {pc('cream'):.1f} |")


def open_paint_hex(paint):
    with open(os.path.join(KARTS, "manifest.json")) as f:
        return json.load(f)["paints"][paint]


# ------------------------------------------------------------------ rim
def cmd_rim(bodies, paint):
    ramp = paint_ramp(open_paint_hex(paint))
    high = tuple(ramp[3])
    print(f"Sun-side rim on the BODY EDGE, paint {paint}.")
    print("Denominator: perimeter pixels whose outward direction faces the sun")
    print(f"  (screen sun stall {SUN_SCREEN['stall'][0]:+.2f},{SUN_SCREEN['stall'][1]:+.2f}"
          f"  road {SUN_SCREEN['road'][0]:+.2f},{SUN_SCREEN['road'][1]:+.2f}), EXCLUDING every")
    print("  pixel of the fixed lamp tones f01a1a / ffb3a0 / ffd489 and the cream")
    print("  tones b09a6d / d9c79a / f2e6c4, which no lighting decision moves.")
    print("Numerator: those pixels carrying the paint ramp's `high` step or the warm rim tone.")
    print("`lamp px on that edge` is what a naive metric would have counted instead.")
    print("`shadow %` is the same numerator over the perimeter FACING AWAY from the sun.")
    print("It is the honest half of this table: a rim that is a rim breaks the ink ring")
    print("on one side only, so shadow % must stay near zero while rim % rises. If both")
    print("rose, the sprite would just be outlined in a warmer colour.\n")
    print("| body | cell | sun edge px | rim px | rim % | lamp px on that edge | shadow % |")
    print("|---|---|---:|---:|---:|---:|---:|")
    for b in bodies:
        _w, _h, px = sheet(b, paint)
        for key in ("stall192", "stall96", "road192", "road48"):
            cam, si, _n = DRAWN[key]
            sx, sy = SUN_SCREEN[cam]
            cw, ch, c = cell(px, cam, si, 0)
            m = body_mask(cw, ch, c)
            den = num = lamp = 0
            sden = snum = 0
            for y in range(ch):
                for x in range(cw):
                    if not m[y * cw + x]:
                        continue
                    ox = oy = 0.0
                    edge = False
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            if dx == 0 and dy == 0:
                                continue
                            nx, ny = x + dx, y + dy
                            if not (0 <= nx < cw and 0 <= ny < ch) or not m[ny * cw + nx]:
                                ox += dx
                                oy += dy
                                if abs(dx) + abs(dy) == 1:
                                    edge = True
                    if not edge:
                        continue
                    n = math.hypot(ox, oy)
                    if n == 0:
                        continue
                    facing = (ox / n) * sx + (oy / n) * sy
                    t = tone(c, cw, x, y)
                    if facing <= 0:
                        if t in LAMP or t in CREAM:
                            continue
                        sden += 1
                        if t == high or t in RIMTONE:
                            snum += 1
                        continue
                    if t in LAMP:
                        lamp += 1
                        continue
                    if t in CREAM:
                        continue
                    den += 1
                    if t == high or t in RIMTONE:
                        num += 1
            print(f"| {b} | {key} | {den} | {num} | {100.0 * num / max(1, den):.1f} | {lamp} | "
                  f"{100.0 * snum / max(1, sden):.1f} |")


# ------------------------------------------------------------------ matrix
def cmd_matrix(bodies, paint, cells, yaws):
    print("Cut-out separation, XOR / union of the alpha==255 masks, same cell, same")
    print("scale, both anchored on meta.json's `ground` point (identical for every")
    print("body, so this is plain in-cell alignment). Under 15 % is a collision.\n")
    masks = {}
    for b in bodies:
        _w, _h, px = sheet(b, paint)
        for key in cells:
            cam, si, _n = DRAWN[key]
            for yaw in yaws:
                cw, ch, c = cell(px, cam, si, yaw)
                masks[(b, key, yaw)] = (cw, ch, body_mask(cw, ch, c))
    for key in cells:
        print(f"\n**{key}** ({DRAWN[key][2]})\n")
        header = "| pair | " + " | ".join(f"yaw {y}" for y in yaws) + " | min |"
        print(header)
        print("|---" * (len(yaws) + 2) + "|")
        rows = []
        for i, a in enumerate(bodies):
            for bb in bodies[i + 1:]:
                vals = []
                for yaw in yaws:
                    cw, ch, ma = masks[(a, key, yaw)]
                    _cw, _ch, mb = masks[(bb, key, yaw)]
                    x = u = 0
                    for k in range(cw * ch):
                        if ma[k] or mb[k]:
                            u += 1
                            if ma[k] != mb[k]:
                                x += 1
                    vals.append(100.0 * x / max(1, u))
                rows.append((min(vals), f"{a}/{bb}", vals))
        rows.sort()
        for lo, name, vals in rows:
            cellsfmt = " | ".join(f"{v:.1f}" for v in vals)
            print(f"| {name} | {cellsfmt} | **{lo:.1f}** |")
        allv = [v for _lo, _n, vs in rows for v in vs]
        print(f"\nmin {min(allv):.1f}, median {sorted(allv)[len(allv) // 2]:.1f}, "
              f"pairs-yaws under 15 %: {sum(1 for v in allv if v < 15)} of {len(allv)}")


# ------------------------------------------------------------------ hue
def rgb2hsv(c):
    r, g, b = (v / 255 for v in c)
    mx, mn = max(r, g, b), min(r, g, b)
    d = mx - mn
    if d == 0:
        h = 0.0
    elif mx == r:
        h = (60 * ((g - b) / d)) % 360
    elif mx == g:
        h = 60 * ((b - r) / d) + 120
    else:
        h = 60 * ((r - g) / d) + 240
    return h, (0 if mx == 0 else d / mx), mx


def cmd_hue(bodies, _paint):
    """Every paint's ramp against the eight swatches: does each ramp step still
    classify as its own paint by hue, and what happens to saturation."""
    with open(os.path.join(KARTS, "manifest.json")) as f:
        paints = json.load(f)["paints"]
    # The white swatch is achromatic (S = 0.04); its hue is an artefact of
    # rounding, so it is not a hue any step can be "nearest" to, and white's
    # own steps are not hue-tested at all. Stated rather than silently dropped.
    hues = {n: rgb2hsv(hex2rgb(h))[0] for n, h in paints.items() if rgb2hsv(hex2rgb(h))[1] >= 0.15}
    print("Paint ramps against the seven CHROMATIC swatch hues. `own` = the nearest of")
    print("those to that ramp step is the paint's own. `drift` = degrees from the swatch")
    print("hue. The white swatch is excluded from both sides: at S 0.04 its hue is noise.\n")
    print("| paint | deep drift | deep own | shade drift | shade own | high drift | high own | S base | S high |")
    print("|---|---:|---|---:|---|---:|---|---:|---:|")
    for name, hexv in paints.items():
        if name not in hues:
            print(f"| {name} | (achromatic swatch, not hue-tested) | | | | | | "
                  f"{rgb2hsv(hex2rgb(hexv))[1]:.2f} | {rgb2hsv(tuple(paint_ramp(hexv)[3]))[1]:.2f} |")
            continue
        ramp = paint_ramp(hexv)
        base_h, base_s, _v = rgb2hsv(hex2rgb(hexv))
        out = [name]
        for i in (0, 1, 3):
            h, _s, _v = rgb2hsv(tuple(ramp[i]))
            drift = min(abs(h - base_h), 360 - abs(h - base_h))
            nearest = min(hues, key=lambda n: min(abs(h - hues[n]), 360 - abs(h - hues[n])))
            out += [f"{drift:.1f}", "yes" if nearest == name else f"**{nearest.upper()}**"]
        out += [f"{base_s:.2f}", f"{rgb2hsv(tuple(ramp[3]))[1]:.2f}"]
        print("| " + " | ".join(out) + " |")


# ------------------------------------------------------------------ tail bar
def cmd_tailbar(bodies, paint):
    print(f"Tail lamp presence, paint {paint}: pixels of f01a1a (bar) and ffb3a0 (glow).\n")
    print("| body | " + " | ".join(DRAWN) + " |")
    print("|---" * (len(DRAWN) + 1) + "|")
    bar, glow = hex2rgb("f01a1a"), hex2rgb("ffb3a0")
    for b in bodies:
        _w, _h, px = sheet(b, paint)
        row = [b]
        for key, (cam, si, _n) in DRAWN.items():
            cw, ch, c = cell(px, cam, si, 0)
            nb = ng = 0
            for y in range(ch):
                for x in range(cw):
                    t = tone(c, cw, x, y)
                    if c[(y * cw + x) * 4 + 3] != 255:
                        continue
                    nb += t == bar
                    ng += t == glow
            row.append(f"{nb}+{ng}")
        print("| " + " | ".join(row) + " |")


def main():
    mode = sys.argv[1]
    bodies = (arg("--bodies") or ",".join(BODIES)).split(",")
    paint = arg("--paint", "red")
    cells = (arg("--cells") or "stall96,stall48,road48,stall192").split(",")
    yaws = list(range(YAWS)) if arg("--yaws", "0") == "all" else [int(v) for v in arg("--yaws", "0").split(",")]
    if mode == "dims":
        cmd_dims(bodies, paint)
    elif mode == "glass":
        cmd_glass(bodies, paint)
    elif mode == "rim":
        cmd_rim(bodies, paint)
    elif mode == "matrix":
        cmd_matrix(bodies, paint, cells, yaws)
    elif mode == "hue":
        cmd_hue(bodies, paint)
    elif mode == "tailbar":
        cmd_tailbar(bodies, paint)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
