"""Pixel pass for the prop kit: the same quantise / despeckle / outline chain
as the car sheets, on the fixed palette plus each prop's declared paint ramps,
one indexed sheet per prop. Layout: columns are the prop's views (R, L, C and
animation frames, in meta order), rows are scales 1, 1/2 and 1/4, each row's
cells packed from the left at that scale. Every cell is anchored at meta's
`ground` point (bottom-centre for a standing prop, centre for an effect).
Also records each view's opaque bounds at scale 1, so a consumer can crop the
transparent margin a small prop carries. Driven by bake-props.ts.

  python3 px-props.py RENDER_DIR OUT_DIR [--px 2] [--contact contact.png [--k 2] [--contact-only a,b]]
"""
import sys, os, json, importlib.util
here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("pxart", os.path.join(here, "pxart.py"))
px = importlib.util.module_from_spec(spec); spec.loader.exec_module(px)

render_dir, out_dir = sys.argv[1], sys.argv[2]
PX = int(px.arg("--px", "2")) if hasattr(px, "arg") else 2   # bake-props.py renders at PX 2 by default; keep the two in step
CELLS = os.environ.get("PROPS_CELLS_DIR", "")
if CELLS: os.makedirs(CELLS, exist_ok=True)
os.makedirs(out_dir, exist_ok=True)
meta = json.load(open(os.path.join(render_dir, "props-meta.json")))

# full palette plus ink and glass tones; props are many-coloured, unlike a kart locked to one paint
FIXED = list(range(0, 24))   # neutrals, amber, teal, cream, lime, hazard
EXTRA = [px.hex2rgb(h) for h in ("280e27", "343a52", "4d5573", "2a1030", "3a1a44")]
def lock(paints):
    keep = [px.hex2rgb(px.PALETTE_HEX[i]) for i in FIXED]
    for name in paints:
        b = px.PAINTS[name]; keep += [px.hex2rgb(px.PALETTE_HEX[i]) for i in range(b, b + 4)]
    px.PALETTE = keep + EXTRA
SUN = px.SUN_SCREEN["road"]
OUTLINE = px.hex2rgb("280e27"); SHADOW = px.hex2rgb("5f255e"); RIM = px.hex2rgb("f0b07a")

sheets = {}
for name, m in meta.items():
    cw, ch = m["cell"]; views = m["views"]
    lock(m.get("paints", []))
    W = cw * len(views); rows = [0, ch, ch + ch // 2]; H = ch + ch // 2 + ch // 4
    sheet = bytearray(W * H * 4)
    cells = {}
    for vi, tag in enumerate(views):
        w, h, raw = px.read_png(os.path.join(render_dir, f"{name}-{tag}.png"))
        assert (w, h) == (cw * PX, ch * PX), f"{name}-{tag}: {w}x{h} vs {cw*PX}x{ch*PX}"
        for si, div in enumerate((1, 2, 4)):
            w2, h2, cell = px.box_down_exact(w, h, raw, PX * div)
            cell = px.quantise(w2, h2, cell, dither=0.12, alpha_cut=200, shadow_lo=24, shadow=SHADOW, shadow_alpha=128)
            cell = px.despeckle(w2, h2, cell)
            cell = px.outline(w2, h2, cell, colour=OUTLINE, rim=RIM, sun=SUN)
            ox, oy = vi * w2, rows[si]
            for y in range(h2):
                d = ((oy + y) * W + ox) * 4
                sheet[d:d + w2 * 4] = cell[y * w2 * 4:(y + 1) * w2 * 4]
            if si == 0:
                cells[tag] = (w2, h2, cell)
                if CELLS: px.write_png(os.path.join(CELLS, f"{name}-{tag}.png"), w2, h2, cell)
    px.write_png_indexed(os.path.join(out_dir, f"{name}.png"), W, H, sheet)
    sheets[name] = cells
    m["sheet"] = [W, H]
    m["rows"] = rows
    m["bounds"] = {tag: list(px.alpha_bbox(c[0], c[1], c[2])) for tag, c in cells.items()}
    print(f"sheet {name}: {W}x{H} views={views}")
json.dump(meta, open(os.path.join(out_dir, "props-meta.json"), "w"), indent=1, sort_keys=True)

# contact sheet: every prop's first view at scale 1.0, upscaled x3 on the ground purple, with a label strip
if "--contact" in sys.argv:
    out = sys.argv[sys.argv.index("--contact") + 1]
    K = int(px.arg("--k", "3")) if hasattr(px, "arg") else 3; gap = 18; bg = px.hex2rgb("3c1228")
    items = []
    only = px.arg("--contact-only", "").split(",") if "--contact-only" in sys.argv else None
    for name, cells in sheets.items():
        for tag, (w, h, cell) in cells.items():
            if only and f"{name}:{tag}" not in only and name not in only: continue
            w2, h2, up = px.upscale(w, h, cell, K)
            items.append((name + " " + tag, w2, h2, up))
    # lay out in rows of at most 1800 px
    rows, row, x = [], [], gap
    for it in items:
        if x + it[1] + gap > int(px.arg('--contact-width', '1900')) and row: rows.append(row); row, x = [], gap
        row.append(it); x += it[1] + gap
    if row: rows.append(row)
    W = max(sum(i[1] for i in r) + gap * (len(r) + 1) for r in rows)
    H = sum(max(i[2] for i in r) + gap + 20 for r in rows) + gap
    canvas = bytearray(W * H * 4)
    for i in range(0, len(canvas), 4): canvas[i], canvas[i+1], canvas[i+2], canvas[i+3] = bg[0], bg[1], bg[2], 255
    y = gap
    for r in rows:
        rh = max(i[2] for i in r); x = gap
        for (label, w2, h2, up) in r:
            for yy in range(h2):
                for xx in range(w2):
                    s = (yy * w2 + xx) * 4; a = up[s + 3] / 255
                    if a == 0: continue
                    d = ((y + rh - h2 + yy) * W + x + xx) * 4
                    for c in range(3): canvas[d + c] = int(up[s + c] * a + bg[c] * (1 - a))
                    canvas[d + 3] = 255
            x += w2 + gap
        y += rh + gap + 20
    px.write_png(out, W, H, canvas)
    print("contact ->", out, W, H)
