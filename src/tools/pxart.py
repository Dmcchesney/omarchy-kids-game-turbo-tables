"""Pixel-art post-processor, pure Python (no Pillow on this Mac).

  pxart.py bake    RENDER_DIR OUT.png --paint e0483a [--dither 0.25] [--px 4]
  pxart.py sprite  IN.png OUT_BASE --width 160 [--scale 3] [--outline]
  pxart.py scene   IN.png OUT_BASE --width 640 [--scale 3] [--dither 0.5]
  pxart.py compare LEFT.png RIGHT.png OUT.png [--height 480]
  pxart.py sheet   OUT.png IMG... [--height H] [--gap G]
  pxart.py paste   BASE.png OVERLAY.png OUT.png --at x,y

bake:   the sprite-sheet path. RENDER_DIR holds bake-cars.py's sixteen frames
        (stall-0..7.png, road-0..7.png), each --px times the 192x128 cell with
        the car's ground-centre at a fixed point. Every frame is box-downscaled
        to the three cell sizes (192x128, 96x64, 48x32), quantised to the
        paint-locked palette with a Bayer dither, despeckled, outlined, and
        placed in the contract's fixed-cell sheet:
            row 0..2  stall  at scale 1, 1/2, 1/4
            row 3..5  road   at scale 1, 1/2, 1/4
        Semi-transparent pixels (the renderer's contact shadow) become ONE
        purple tone at half alpha. The PNG is written by this file's own
        encoder, so the bytes depend only on the pixels -- the renderer's
        timestamps never reach the sheet.
sprite: crop to alpha bbox, box-downscale to --width, dither + quantise to the
        palette, optional 1px outline, write OUT_BASE.png and OUT_BASE-x{k}.png.
scene:  same without alpha crop/outline (opaque backgrounds).
compare / sheet / paste: evidence helpers, unchanged.

The palette is a fixed set of neutrals, cream and lamp tones plus ONE paint
ramp, derived from the paint hex itself (ui/Theme.qml's swatch), so a sheet is
locked to its own paint: a lit red face can never snap to orange, a shadowed one
never to purple.
"""
import os
import struct
import sys
import zlib


# ---------------------------------------------------------------- PNG I/O
def read_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, chunks, idat = 8, {}, []
    while pos < len(data):
        n = struct.unpack(">I", data[pos:pos+4])[0]
        typ = data[pos+4:pos+8]; body = data[pos+8:pos+8+n]; pos += 12 + n
        if typ in (b"IHDR", b"PLTE", b"tRNS"): chunks[typ.decode()] = body
        elif typ == b"IDAT": idat.append(body)
        elif typ == b"IEND": break
    w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", chunks["IHDR"])
    assert depth == 8 and interlace == 0 and ctype in (2, 3, 6), f"unsupported PNG {depth} {ctype} {interlace}"
    bpp = {2: 3, 3: 1, 6: 4}[ctype]
    raw = zlib.decompress(b"".join(idat))
    stride = w * bpp
    out = bytearray(w * h * 4)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p+stride]); p += stride
        if f == 1:
            for i in range(bpp, stride): line[i] = (line[i] + line[i-bpp]) & 255
        elif f == 2:
            for i in range(stride): line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = line[i-bpp] if i >= bpp else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i-bpp] if i >= bpp else 0
                b = prev[i]; c = prev[i-bpp] if i >= bpp else 0
                pa, pb, pc = abs(b-c), abs(a-c), abs(a+b-2*c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        o = y * w * 4
        if bpp == 4:
            out[o:o+w*4] = line
        elif bpp == 3:
            for x in range(w):
                out[o+x*4:o+x*4+3] = line[x*3:x*3+3]; out[o+x*4+3] = 255
        else:
            plte, trns = chunks["PLTE"], chunks.get("tRNS", b"")
            for x in range(w):
                i = line[x]
                out[o+x*4:o+x*4+3] = plte[i*3:i*3+3]; out[o+x*4+3] = trns[i] if i < len(trns) else 255
        prev = line
    return w, h, out


def write_png(path, w, h, px):
    """Deterministic: fixed filter (none), fixed zlib level, no ancillary
    chunks. Same pixels, same bytes."""
    raw = bytearray()
    for y in range(h):
        raw.append(0); raw += px[y*w*4:(y+1)*w*4]
    def chunk(t, b): return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


def write_png_indexed(path, w, h, px):
    """The sheet encoder: colour type 3 (palette) with a tRNS chunk, one byte
    per pixel instead of four, which is what makes 48 sheets fit the 2 MB
    budget. The palette is built from the pixels in scan order, so the bytes
    depend only on the pixels. Falls back to RGBA if there are more than 256
    distinct (r, g, b, a) values, which a quantised sheet never has."""
    index = {}
    colours = []
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        row = px[y*w*4:(y+1)*w*4]
        for x in range(w):
            c = bytes(row[x*4:x*4+4])
            i = index.get(c)
            if i is None:
                if len(colours) == 256:
                    return write_png(path, w, h, px)
                i = len(colours); index[c] = i; colours.append(c)
            raw.append(i)
    plte = b"".join(c[:3] for c in colours)
    trns = bytes(c[3] for c in colours)
    def chunk(t, b): return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 3, 0, 0, 0))
                           + chunk(b"PLTE", plte) + chunk(b"tRNS", trns)
                           + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


# ---------------------------------------------------------------- palette
# 32 colours built on the theme's anchors, each as a hue-shifted ramp:
# shadows lean cool (toward teal/indigo), highlights lean warm.
PALETTE_HEX = [
    # cool neutrals (ground, panels, chrome)
    "0b0c12", "1a1b26", "2a2b3d", "414868", "6b7291", "a9b1d6", "e6e9f5",
    # amber (work lights, lamps, charge)
    "5a3508", "a8690f", "f5a524", "ffd489",
    # teal (shadow, revealed answer, door)
    "082326", "12454a", "39b3ad", "8fe3dc",
    # cream (plates, road paint, fact text)
    "b09a6d", "d9c79a", "f2e6c4",
    # lime (ready, go)
    "1d3a18", "4d8f3a", "86e06a",
    # hazard yellow / rumble
    "7a5410", "d8a12a", "ffe08a",
    # the eight paints, four steps each: shadow leans cool, highlight warm,
    # but only one hue step so a red kart stays red under a work light
    "4a1014", "8c1f22", "d13a33", "f0705a",   # red
    "6b2a08", "b8531a", "ec8a2e", "ffb95c",   # orange
    "6b5308", "b8951a", "e8c62e", "fff08a",   # yellow
    "1d3a18", "3d7a2e", "6bc24a", "a8f08a",   # green
    "162a5e", "2a55b8", "4a8ae8", "8ec0ff",   # blue
    "3a1a5e", "6b34b0", "9a5ce6", "c99cff",   # purple
    "5e1a3e", "b0348a", "e65cb8", "ffa0e0",   # pink
    "6b6e78", "a9aab4", "d8d9e0", "f7f7fa",   # white
]
def hex2rgb(s): return tuple(int(s[i:i+2], 16) for i in (0, 2, 4))
PALETTE = [hex2rgb(h) for h in PALETTE_HEX]

# A sprite is locked to its own paint: one kart may use the neutrals, cream,
# hazard yellow and ITS ramp, and nothing else. Without this a lit red face
# snaps to the orange ramp and a shadowed one to purple -- the eye reads that
# as a dirty paint job, not as shading. Index ranges into PALETTE_HEX above.
PAINTS = {"red": 24, "orange": 28, "yellow": 32, "green": 36, "blue": 40, "purple": 44, "pink": 48, "white": 52}
def lock_palette(paint):
    global PALETTE
    keep = list(range(0, 7)) + list(range(15, 18)) + list(range(21, 24)) + list(range(PAINTS[paint], PAINTS[paint] + 4))
    PALETTE = [hex2rgb(PALETTE_HEX[i]) for i in keep]


def mix(a, b, t):
    return tuple(int(round(a[i] * (1 - t) + b[i] * t)) for i in range(3))


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
    return h, (0.0 if mx == 0 else d / mx), mx


def hsv2rgb(h, s, v):
    h = h % 360
    c = v * s
    x = c * (1 - abs((h / 60) % 2 - 1))
    m = v - c
    r, g, b = [(c, x, 0), (x, c, 0), (0, c, x), (0, x, c), (x, 0, c), (c, 0, x)][int(h // 60)]
    return tuple(int(round((v + m) * 255)) for v in (r, g, b))


def _hold_hue(base, c, max_deg):
    """Rotate `c` back toward `base`'s hue until it is within `max_deg`.

    The design's Visual style row says the paint keeps its own hue under this
    light. Mixing a dark step toward the ground purple does not respect that
    equally at every hue: yellow's deep step drifted 11.9 degrees and landed
    nearer the ORANGE swatch than the yellow one, on all six bodies, which is
    a yellow car whose shadows are an orange car's. Saturation and value are
    left exactly where the mix put them; only the hue is held."""
    hb, _sb, _vb = rgb2hsv(base)
    h, s, v = rgb2hsv(c)
    if s == 0:
        return c
    d = (h - hb + 180) % 360 - 180
    if abs(d) <= max_deg:
        return c
    return hsv2rgb(hb + (max_deg if d > 0 else -max_deg), s, v)


def _hold_sat(base, c, floor):
    """Keep the highlight step at least `floor` of the swatch's saturation.

    Mixing toward cream desaturates hardest on the cool half -- purple 0.60 to
    0.33, blue 0.72 to 0.39 -- so the highlight went chalky where a low sun
    should make it hotter. The bar's brightest pixels are MORE saturated than
    its mid-tones, not less."""
    _hb, sb, _vb = rgb2hsv(base)
    h, s, v = rgb2hsv(c)
    return c if s >= sb * floor else hsv2rgb(h, sb * floor, v)


DEEP_HUE_HOLD = 6.0     # degrees the deep and shade steps may drift from the swatch
HIGH_SAT_FLOOR = 0.72   # of the swatch's saturation


def paint_ramp(hexcolour):
    """Four steps around one swatch: deep shadow toward the ground purple,
    shadow cooler and darker, the swatch itself, a highlight toward warm
    cream. The swatch is the middle so the dominant tone IS the paint.

    Both dark steps hold the swatch's hue to within DEEP_HUE_HOLD degrees and
    the highlight holds HIGH_SAT_FLOOR of its saturation, so no step of any
    ramp classifies as a different paint and no highlight goes chalky."""
    base = hex2rgb(hexcolour)
    deep = _hold_hue(base, mix(tuple(int(c * 0.42) for c in base), hex2rgb("3c1228"), 0.30), DEEP_HUE_HOLD)
    shade = _hold_hue(base, mix(tuple(int(c * 0.68) for c in base), hex2rgb("5f255e"), 0.16), DEEP_HUE_HOLD)
    high = _hold_sat(base, mix(base, hex2rgb("fff0d0"), 0.36), HIGH_SAT_FLOOR)
    return [deep, shade, base, high]


# The sprite-sheet palette: neutrals for tyres, rims, trim and glass; cream for
# the livery, roundels and plate; the lamp tones; and the paint ramp. Amber
# f5a524 and the hazard yellows are left out on purpose -- they sit too close
# to the orange and yellow ramps and would steal body pixels.
SHEET_FIXED_HEX = [
    "0b0c12", "1a1b26", "2a2b3d", "414868", "6b7291", "a9b1d6",   # cool neutrals
    "b09a6d", "d9c79a", "f2e6c4",                                 # cream
    "ffd489",                                                     # headlamp
    "f01a1a", "ffb3a0",                                           # tail bar, its glow strip
    "280e27",                                                     # ink / outline
    # Glass. It needs a tone of its own: rounds 1-3 painted the windows
    # 2a1030, which is three units from the outline ink 280e27, so the
    # quantiser sent every window pixel to the outline colour and the
    # greenhouse became a hole under a floating lid -- 34 to 50 % of the top
    # third of the coupe, hatch and saloon was the outline tone. Luma 51,
    # between the ink at 21 and a paint base around 100, so glass is darker
    # than paint and lighter than the line that draws the car.
    "343a52", "4d5573",                                           # glass, lit glass
]
def sheet_palette(hexcolour):
    global PALETTE
    PALETTE = [hex2rgb(h) for h in SHEET_FIXED_HEX] + paint_ramp(hexcolour)
    return PALETTE


def nearest(r, g, b):
    best, bd = PALETTE[0], 1e18
    for c in PALETTE:
        dr, dg, db = r - c[0], g - c[1], b - c[2]
        d = 2*dr*dr + 4*dg*dg + 3*db*db  # perceptual-ish weights
        if d < bd: bd, best = d, c
    return best

BAYER4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

# ---------------------------------------------------------------- ops
def alpha_bbox(w, h, px, thresh=24):
    x0, y0, x1, y1 = w, h, -1, -1
    for y in range(h):
        row = y * w * 4
        for x in range(w):
            if px[row + x*4 + 3] > thresh:
                if x < x0: x0 = x
                if x > x1: x1 = x
                if y < y0: y0 = y
                if y > y1: y1 = y
    return (0, 0, w, h) if x1 < 0 else (x0, y0, x1 + 1, y1 + 1)

def crop(w, h, px, box):
    x0, y0, x1, y1 = box
    cw, ch = x1 - x0, y1 - y0
    out = bytearray(cw * ch * 4)
    for y in range(ch):
        s = ((y0 + y) * w + x0) * 4
        out[y*cw*4:(y+1)*cw*4] = px[s:s + cw*4]
    return cw, ch, out

def box_down(w, h, px, tw, th=None):
    th = th or max(1, round(h * tw / w))
    out = bytearray(tw * th * 4)
    for ty in range(th):
        ya, yb = int(ty * h / th), max(int(ty * h / th) + 1, int((ty + 1) * h / th))
        for tx in range(tw):
            xa, xb = int(tx * w / tw), max(int(tx * w / tw) + 1, int((tx + 1) * w / tw))
            r = g = b = a = n = 0
            for y in range(ya, min(yb, h)):
                row = y * w * 4
                for x in range(xa, min(xb, w)):
                    i = row + x*4; al = px[i+3]
                    # premultiplied average so transparent pixels do not darken edges
                    r += px[i] * al; g += px[i+1] * al; b += px[i+2] * al; a += al; n += 1
            o = (ty * tw + tx) * 4
            if a > 0:
                out[o], out[o+1], out[o+2], out[o+3] = r // a, g // a, b // a, a // n
    return tw, th, out


def box_down_exact(w, h, px, k):
    """Integer k:1 box filter -- the bake path, where the render is an exact
    multiple of the cell. Same result as box_down, several times faster."""
    tw, th = w // k, h // k
    out = bytearray(tw * th * 4)
    kk = k * k
    for ty in range(th):
        rows = [((ty * k + j) * w) * 4 for j in range(k)]
        o = ty * tw * 4
        for tx in range(tw):
            x0 = tx * k * 4
            r = g = b = a = 0
            for row in rows:
                i = row + x0
                for _ in range(k):
                    al = px[i+3]
                    if al:
                        r += px[i] * al; g += px[i+1] * al; b += px[i+2] * al; a += al
                    i += 4
            if a:
                out[o] = r // a; out[o+1] = g // a; out[o+2] = b // a; out[o+3] = a // kk
            o += 4
    return tw, th, out


SHADOW = (11, 12, 18)
def quantise(w, h, px, dither=0.5, alpha_cut=160, shadow_lo=24, shadow=SHADOW, shadow_alpha=140):
    """Opaque pixels are dithered onto the palette. Semi-transparent pixels --
    the renderer's soft ground shadow -- become ONE dark tone at half alpha,
    which is how a sprite sheet carries a shadow: a flat shape, not a blur."""
    out = bytearray(w * h * 4)
    amp = 255 / 16 * dither  # spread of the Bayer offset
    for y in range(h):
        for x in range(w):
            i = (y * w + x) * 4
            a = px[i+3]
            if a < shadow_lo: continue
            if a < alpha_cut:
                out[i], out[i+1], out[i+2], out[i+3] = shadow[0], shadow[1], shadow[2], shadow_alpha
                continue
            t = (BAYER4[y & 3][x & 3] - 7.5) * amp / 8
            r = min(255, max(0, px[i] + t)); g = min(255, max(0, px[i+1] + t)); b = min(255, max(0, px[i+2] + t))
            c = nearest(r, g, b)
            out[i], out[i+1], out[i+2], out[i+3] = c[0], c[1], c[2], 255
    return out

def outline(w, h, px, colour=(11, 12, 18), rim=None, sun=None, rim_min=0.34):
    """A one-pixel line around the fully opaque body. The half-alpha shadow is
    neither outlined nor overwritten, so it stays a flat shape under the kart.

    Golden hour is an edge, not a facet. With `rim` and `sun` given, the ring
    is not uniform: an edge pixel whose outward direction faces the sun takes
    the paint's highlight step instead of the ink, so the line breaks on the
    sun side and the car is lit from behind-right rather than drawn in one
    colour all the way round. `sun` is (dx, dy) in image pixels with y DOWN;
    `rim_min` is the cosine below which an edge is not sunward -- 0.34 is
    about 70 degrees either side of the sun, a little over a third of the
    perimeter, which is what a low sun actually lights.

    The ring's geometry is unchanged: the same pixels are painted, in the same
    order, so the silhouette and every cut-out measurement are untouched. Only
    the colour of the sunward third differs."""
    out = bytearray(px)
    for y in range(h):
        for x in range(w):
            i = (y * w + x) * 4
            if px[i+3] == 255: continue
            touches = False
            ox = oy = 0.0
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    if dx == 0 and dy == 0: continue
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and px[(ny*w+nx)*4+3] == 255:
                        # the outward direction points AWAY from the body
                        ox -= dx; oy -= dy
                        if abs(dx) + abs(dy) == 1: touches = True
            if not touches: continue
            c = colour
            if rim is not None and sun is not None:
                n = (ox*ox + oy*oy) ** 0.5
                if n > 0 and (ox/n) * sun[0] + (oy/n) * sun[1] >= rim_min:
                    c = rim
            out[i], out[i+1], out[i+2], out[i+3] = c[0], c[1], c[2], 255
    return out

def despeckle(w, h, px):
    """Replace a lone pixel whose four neighbours mostly agree with that
    majority colour. Removes dither speckle on flat faces, keeps edges."""
    out = bytearray(px)
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            i = (y * w + x) * 4
            if px[i+3] != 255: continue
            me = px[i:i+3]
            counts = {}
            for dx, dy in ((1,0), (-1,0), (0,1), (0,-1)):
                j = ((y+dy) * w + x + dx) * 4
                if px[j+3] != 255: continue
                c = bytes(px[j:j+3]); counts[c] = counts.get(c, 0) + 1
            if counts.get(bytes(me), 0) == 0:
                best = max(counts.items(), key=lambda kv: kv[1], default=None)
                if best and best[1] >= 3:
                    out[i:i+3] = best[0]
    return out

def upscale(w, h, px, k):
    W, H = w * k, h * k
    out = bytearray(W * H * 4)
    for y in range(H):
        sy = (y // k) * w * 4
        rowbuf = bytearray()
        for x in range(w):
            rowbuf += px[sy + x*4: sy + x*4 + 4] * k
        out[y*W*4:(y+1)*W*4] = rowbuf
    return W, H, out

def on_ground(w, h, px, bg=(26, 27, 38)):
    out = bytearray(w * h * 4)
    for i in range(0, w*h*4, 4):
        a = px[i+3] / 255
        out[i] = int(px[i]*a + bg[0]*(1-a)); out[i+1] = int(px[i+1]*a + bg[1]*(1-a)); out[i+2] = int(px[i+2]*a + bg[2]*(1-a)); out[i+3] = 255
    return out

def arg(name, default):
    if name in sys.argv:
        return sys.argv[sys.argv.index(name) + 1]
    return default


# ---------------------------------------------------------------- the sheet
CELL = (192, 128)
SCALES = (1, 2, 4)                 # divisors: scale 1.0, 0.5, 0.25
CAMERAS = ("stall", "road")
YAWS = 8
SHEET_W = CELL[0] * YAWS           # 1536
ROW_Y = [0, 128, 192, 224, 352, 416]
SHEET_H = 448
SHADOW_TONE = hex2rgb("5f255e")    # the design's purple shadow, never grey
OUTLINE_TONE = hex2rgb("280e27")   # dusk ink

# Where the low sun is ON SCREEN, per camera, as a unit (dx, dy) in image
# pixels with y DOWN. Not chosen by eye and not written down twice:
# bake-cars.py's RIM_DIR is a world vector, each camera's screen basis is
# right = normalize(view x Z) and up = right x view, and the camera positions
# are bake-cars.py's CAMERAS. src/tools/carstats.py imports SUN_SCREEN from
# here, so the sprite and the metric cannot drift apart.
RIM_DIR = (0.55, 0.45, 0.70)
CAMERA_EYE = {"stall": (5.6, -6.4, 2.0), "road": (0.0, -9.4, 1.8)}
CAMERA_AIM_Z = {"stall": 0.72, "road": 0.66}


def screen_sun(camera):
    ex, ey, ez = CAMERA_EYE[camera]
    d = (-ex, -ey, CAMERA_AIM_Z[camera] - ez)
    n = sum(c * c for c in d) ** 0.5
    d = tuple(c / n for c in d)
    right = (d[1], -d[0], 0.0)
    n = (right[0] ** 2 + right[1] ** 2) ** 0.5 or 1.0
    right = (right[0] / n, right[1] / n, 0.0)
    up = (right[1] * d[2] - right[2] * d[1], right[2] * d[0] - right[0] * d[2], right[0] * d[1] - right[1] * d[0])
    sx = sum(RIM_DIR[i] * right[i] for i in range(3))
    sy = sum(RIM_DIR[i] * up[i] for i in range(3))
    n = (sx * sx + sy * sy) ** 0.5 or 1.0
    return (sx / n, -sy / n)      # y down


SUN_SCREEN = {c: screen_sun(c) for c in CAMERAS}


def bake_sheet(render_dir, out_path, paint_hex, dither=0.15, px=4):
    sheet_palette(paint_hex)
    rim_tone = tuple(paint_ramp(paint_hex)[3])
    sheet = bytearray(SHEET_W * SHEET_H * 4)
    for ci, cam in enumerate(CAMERAS):
        for yaw in range(YAWS):
            w, h, raw = read_png(os.path.join(render_dir, f"{cam}-{yaw}.png"))
            assert (w, h) == (CELL[0] * px, CELL[1] * px), f"{cam}-{yaw}: render is {w}x{h}, expected {CELL[0] * px}x{CELL[1] * px}"
            for si, div in enumerate(SCALES):
                cw, ch, cell = box_down_exact(w, h, raw, px * div)
                # The renderer's shadow disc lands at alpha ~130; body edges
                # against transparency land anywhere. Everything under the cut
                # is shadow tone, and the outline pass then reclaims the edge
                # pixels that touch the body.
                cell = quantise(cw, ch, cell, dither=dither, alpha_cut=200, shadow_lo=24, shadow=SHADOW_TONE, shadow_alpha=128)
                cell = despeckle(cw, ch, cell)
                cell = outline(cw, ch, cell, colour=OUTLINE_TONE, rim=rim_tone, sun=SUN_SCREEN[cam])
                ox, oy = yaw * cw, ROW_Y[ci * 3 + si]
                for y in range(ch):
                    d = ((oy + y) * SHEET_W + ox) * 4
                    sheet[d:d + cw * 4] = cell[y * cw * 4:(y + 1) * cw * 4]
    write_png_indexed(out_path, SHEET_W, SHEET_H, sheet)
    return sheet


def main():
    mode = sys.argv[1]
    if mode == "bake":
        render_dir, out = sys.argv[2], sys.argv[3]
        paint = arg("--paint", "e0483a").lstrip("#")
        bake_sheet(render_dir, out, paint, dither=float(arg("--dither", "0.15")), px=int(arg("--px", "4")))
        print(f"bake: {render_dir} -> {out} {SHEET_W}x{SHEET_H}, paint {paint}, palette {len(PALETTE)}")
    elif mode in ("sprite", "scene"):
        src, base = sys.argv[2], sys.argv[3]
        tw = int(arg("--width", "160")); k = int(arg("--scale", "3")); dith = float(arg("--dither", "0.5"))
        w, h, px = read_png(src)
        if "--paint" in sys.argv:
            lock_palette(arg("--paint", "red"))
        if mode == "sprite":
            w, h, px = crop(w, h, px, alpha_bbox(w, h, px))
        elif "--crop" in sys.argv:
            w, h, px = crop(w, h, px, tuple(int(v) for v in arg("--crop", "0,0,0,0").split(",")))
        w, h, px = box_down(w, h, px, tw)
        px = quantise(w, h, px, dither=dith, alpha_cut=(160 if mode == "sprite" else 1), shadow_lo=(24 if mode == "sprite" else 1))
        if "--despeckle" in sys.argv:
            px = despeckle(w, h, px)
        if mode == "sprite" and "--outline" in sys.argv:
            px = outline(w, h, px)
        write_png(base + ".png", w, h, px)
        W, H, up = upscale(w, h, px, k)
        write_png(base + f"-x{k}.png", W, H, up)
        print(f"{mode}: {src} -> {base}.png {w}x{h}, -x{k} {W}x{H}, palette {len(PALETTE)}")
    elif mode == "sheet":
        # sheet OUT.png IMG1 IMG2 ... [--height H] [--gap G] : N images in a row, nearest, on the ground colour
        out = sys.argv[2]; H = int(arg("--height", "240")); gap = int(arg("--gap", "24"))
        srcs = [a for a in sys.argv[3:] if a.endswith(".png") and not a.startswith("--")]
        cells = []
        for p in srcs:
            w, h, px = read_png(p); w, h, px = crop(w, h, px, alpha_bbox(w, h, px))
            tw = max(1, round(w * H / h)); sc = bytearray(tw * H * 4)
            for y in range(H):
                sy = int(y * h / H)
                for x in range(tw):
                    sx = int(x * w / tw); i = (sy*w + sx)*4
                    sc[(y*tw+x)*4:(y*tw+x)*4+4] = px[i:i+4]
            cells.append((tw, H, sc))
        W = sum(c[0] for c in cells) + gap * (len(cells) + 1)
        canvas = bytearray(W * (H + gap*2) * 4)
        for i in range(0, len(canvas), 4): canvas[i:i+4] = b"\x1a\x1b\x26\xff"
        x = gap
        for (tw, th, sc) in cells:
            for y in range(th):
                for xx in range(tw):
                    s = (y*tw+xx)*4; a = sc[s+3] / 255
                    if a == 0: continue
                    d = ((y+gap)*W + x + xx)*4
                    canvas[d] = int(sc[s]*a + 26*(1-a)); canvas[d+1] = int(sc[s+1]*a + 27*(1-a)); canvas[d+2] = int(sc[s+2]*a + 38*(1-a)); canvas[d+3] = 255
            x += tw + gap
        write_png(out, W, H + gap*2, canvas)
        print(f"sheet -> {out} {W}x{H+gap*2} ({len(cells)} cells)")
    elif mode == "paste":
        # paste BASE.png OVERLAY.png OUT.png --at x,y : overlay alpha-composited onto base
        bw, bh, bpx = read_png(sys.argv[2]); ow, oh, opx = read_png(sys.argv[3])
        ax, ay = (int(v) for v in arg("--at", "0,0").split(","))
        out = bytearray(bpx)
        for y in range(oh):
            by = ay + y
            if not (0 <= by < bh): continue
            for x in range(ow):
                bx = ax + x
                if not (0 <= bx < bw): continue
                s = (y*ow + x)*4; d = (by*bw + bx)*4; a = opx[s+3] / 255
                if a == 0: continue
                for c in range(3): out[d+c] = int(opx[s+c]*a + bpx[d+c]*(1-a))
                out[d+3] = 255
        write_png(sys.argv[4], bw, bh, out)
        print(f"paste -> {sys.argv[4]} overlay {ow}x{oh} at {ax},{ay}")
    elif mode == "compare":
        left, right, out = sys.argv[2], sys.argv[3], sys.argv[4]
        H = int(arg("--height", "480")); gap = 40
        imgs = []
        for p in (left, right):
            w, h, px = read_png(p)
            if p == left:  # live render: crop to its own alpha box first
                w, h, px = crop(w, h, px, alpha_bbox(w, h, px))
            # scale to common height, nearest (integer or fractional)
            tw = max(1, round(w * H / h))
            sc = bytearray(tw * H * 4)
            for y in range(H):
                sy = int(y * h / H)
                for x in range(tw):
                    sx = int(x * w / tw); i = (sy*w + sx)*4
                    sc[(y*tw+x)*4:(y*tw+x)*4+4] = px[i:i+4]
            imgs.append((tw, H, sc))
        W = imgs[0][0] + imgs[1][0] + gap*3
        canvas = bytearray(W * (H + gap*2) * 4)
        for i in range(0, len(canvas), 4): canvas[i:i+4] = b"\x1a\x1b\x26\xff"
        x = gap
        for (tw, th, sc) in imgs:
            for y in range(th):
                for xx in range(tw):
                    s = (y*tw+xx)*4; a = sc[s+3] / 255
                    d = ((y+gap)*W + x + xx)*4
                    canvas[d] = int(sc[s]*a + 26*(1-a)); canvas[d+1] = int(sc[s+1]*a + 27*(1-a)); canvas[d+2] = int(sc[s+2]*a + 38*(1-a)); canvas[d+3] = 255
            x += tw + gap
        write_png(out, W, H + gap*2, canvas)
        print(f"compare -> {out} {W}x{H+gap*2}")

if __name__ == "__main__":
    main()
