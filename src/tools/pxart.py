"""Pixel-art post-processor, pure Python (no Pillow on this Mac).

  pxart.py sprite  IN.png OUT_BASE --width 160 [--scale 3] [--outline]
  pxart.py scene   IN.png OUT_BASE --width 640 [--scale 3] [--dither 0.5]
  pxart.py compare LEFT.png RIGHT.png OUT.png [--height 480]

sprite: crop to alpha bbox, box-downscale to --width, Bayer-dither + quantise
        to the palette, optional 1px outline, write OUT_BASE.png (grid size)
        and OUT_BASE-x{scale}.png (nearest upscale).
scene:  same without alpha crop/outline (opaque backgrounds).
compare: put two images side by side on the theme ground at a common height,
        nearest-neighbour, so a before/after can be judged at one scale.
"""
import struct, sys, zlib

# ---------------------------------------------------------------- PNG I/O
def read_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, chunks, idat = 8, {}, []
    while pos < len(data):
        n = struct.unpack(">I", data[pos:pos+4])[0]
        typ = data[pos+4:pos+8]; body = data[pos+8:pos+8+n]; pos += 12 + n
        if typ == b"IHDR": chunks["IHDR"] = body
        elif typ == b"IDAT": idat.append(body)
        elif typ == b"IEND": break
    w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", chunks["IHDR"])
    assert depth == 8 and interlace == 0 and ctype in (2, 6), f"unsupported PNG {depth} {ctype} {interlace}"
    bpp = 4 if ctype == 6 else 3
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
        else:
            for x in range(w):
                out[o+x*4:o+x*4+3] = line[x*3:x*3+3]; out[o+x*4+3] = 255
        prev = line
    return w, h, out

def write_png(path, w, h, px):
    raw = bytearray()
    for y in range(h):
        raw.append(0); raw += px[y*w*4:(y+1)*w*4]
    def chunk(t, b): return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
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

def box_down(w, h, px, tw):
    th = max(1, round(h * tw / w))
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

SHADOW = (11, 12, 18)
def quantise(w, h, px, dither=0.5, alpha_cut=160, shadow_lo=24):
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
                out[i], out[i+1], out[i+2], out[i+3] = SHADOW[0], SHADOW[1], SHADOW[2], 140
                continue
            t = (BAYER4[y & 3][x & 3] - 7.5) * amp / 8
            r = min(255, max(0, px[i] + t)); g = min(255, max(0, px[i+1] + t)); b = min(255, max(0, px[i+2] + t))
            c = nearest(r, g, b)
            out[i], out[i+1], out[i+2], out[i+3] = c[0], c[1], c[2], 255
    return out

def outline(w, h, px, colour=(11, 12, 18)):
    """A one-pixel line around the fully opaque body. The half-alpha shadow is
    neither outlined nor overwritten, so it stays a flat shape under the kart."""
    out = bytearray(px)
    for y in range(h):
        for x in range(w):
            i = (y * w + x) * 4
            if px[i+3] == 255: continue
            for dx, dy in ((1,0), (-1,0), (0,1), (0,-1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and px[(ny*w+nx)*4+3] == 255:
                    out[i], out[i+1], out[i+2], out[i+3] = colour[0], colour[1], colour[2], 255
                    break
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

def main():
    mode = sys.argv[1]
    if mode in ("sprite", "scene"):
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
