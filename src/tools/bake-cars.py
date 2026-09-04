"""Bake one low-poly rally car body to its two turnarounds, headless.

  blender -b --python bake-cars.py -- --body coupe --paint e0483a --out DIR
      [--px 4] [--only stall:0,road:3]

The script IS the model: no .blend is read or written. Every part is a
primitive with a bevel modifier, flat-shaded, lit by one warm sun from
behind-right and a cool purple fill, rendered on transparent film with EEVEE.
Palette banding, outline and the pixel grid are applied afterwards by
pxart.py, so the render here stays clean and un-quantised.

Output, per run:

  DIR/stall-{0..7}.png, DIR/road-{0..7}.png
      the eight yaws (i x 45 degrees about vertical) from each camera, rendered
      at --px times the contract's 192x128 cell with the car's ground-centre at
      a FIXED image point (GROUND, below), so a cell is a plain box-downscale
      of a render and every yaw of every body shares one anchor.
  DIR/meta.json
      the number rects, tail-lamp centres and the ground anchor, in cell
      pixels at scale 1.0, computed from the projected bounds of the roundel
      and plate objects -- never by eye.

Two cameras, both fixed while the car turns:
  stall  above and off the rear-right shoulder (garage, roster, countdown)
  road   directly behind, slightly above (the track)
Column 0 is the car facing +Y, its rear to both cameras.

The number is NOT baked. Roundels and the rear plate are cream and blank.
"""
import json
import math
import os
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

# ------------------------------------------------------------------ args
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(k, d):
    return argv[argv.index(k) + 1] if k in argv else d


BODY = arg("--body", "coupe")
PAINT = arg("--paint", "e0483a").lstrip("#")
OUT = arg("--out", "/tmp/bake")
PX = int(arg("--px", "4"))          # render at PX times the 1.0-scale cell
ONLY = arg("--only", "")            # "stall:0,road:3" renders just those frames
YAWS = 8
CELL_W, CELL_H = 192, 128           # the contract's scale-1.0 cell
# Where the car's ground-centre (world origin) sits in the cell, per camera, as
# a fraction of the cell from the left and from the BOTTOM. The consumer anchors
# a cell at bottom-centre; the lowest pixel of a cell is the contact shadow
# under the rear bumper, which from an elevated camera projects well below the
# car's centre -- 40-odd px at scale 1.0 from the stall camera. meta.json's
# "ground" records the origin's cell pixel so a consumer can correct for it.
GROUND = {"stall": (0.5, 0.35), "road": (0.5, 0.28)}
os.makedirs(OUT, exist_ok=True)


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgb(h, a=1.0):
    """A hex swatch as Blender wants it: colour sockets are LINEAR. Feeding
    them sRGB bytes (the prototype did) re-encodes on output and every colour
    comes back lighter and washed -- red as salmon. Under the Standard view
    transform a face lit at exactly 1.0 now renders as exactly its swatch."""
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)) + (a,)


# ------------------------------------------------------------------ scene
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x = CELL_W * PX
sc.render.resolution_y = CELL_H * PX
sc.render.resolution_percentage = 100
sc.render.film_transparent = True
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.render.image_settings.compression = 15
sc.view_settings.view_transform = "Standard"
sc.view_settings.look = "None"
# Pinned for reproducibility: a fixed sample count, no reprojection, no
# ray tracing. The two-bake check in bake-sprites.ts is the proof; if it ever
# fails, these are the knobs.
sc.eevee.taa_render_samples = 16
sc.eevee.use_taa_reprojection = False
sc.eevee.use_raytracing = False
sc.eevee.use_shadows = True
sc.eevee.shadow_ray_count = 2
sc.eevee.shadow_step_count = 4
sc.render.use_motion_blur = False
world = bpy.data.worlds.new("dusk")
sc.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs[0].default_value = rgb("5e1a50")
bg.inputs[1].default_value = 0.25

root = bpy.data.objects.new("car", None)
sc.collection.objects.link(root)


# ------------------------------------------------------------------ materials
def mat(name, color, rough=1.0, emit=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = rgb(color)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Specular IOR Level"].default_value = 0.2
    if emit:
        p.inputs["Emission Color"].default_value = rgb(emit)
        p.inputs["Emission Strength"].default_value = strength
    return m


M = {
    "paint": mat("paint", PAINT, 0.85),
    "livery": mat("livery", "f2e6c4", 0.9),
    "stripe": mat("stripe", "3c1228", 0.9),
    "glass": mat("glass", "2a1030", 0.4),
    "tyre": mat("tyre", "1a1220", 1.0),
    "rim": mat("rim", "6b7291", 0.7),
    "trim": mat("trim", "2a2b3d", 0.8),
    "cage": mat("cage", "414868", 0.7),
    # Lamps: a black base and emission at exactly 1.0 under the Standard view
    # transform, so a lamp pixel IS its colour and does not blow out to white.
    "head": mat("head", "000000", 1.0, "ffd489", 1.0),
    "tail": mat("tail", "000000", 1.0, "f01a1a", 1.0),
    "glow": mat("glow", "000000", 1.0, "ffb3a0", 1.0),
    "ink": mat("ink", "1a1220", 1.0),
}
# The contact shadow: a flat purple disc, blended. pxart flattens every pixel
# whose alpha is below its cut to one purple tone at half alpha, so only the
# rendered alpha matters here: EEVEE writes a material alpha of 0.30 as about
# 130/255 on transparent film (measured; the film encodes alpha non-linearly),
# well under pxart's cut of 200 and well over its floor of 24.
shadow_mat = bpy.data.materials.new("shadow")
shadow_mat.use_nodes = True
sp = shadow_mat.node_tree.nodes["Principled BSDF"]
sp.inputs["Base Color"].default_value = rgb("5f255e")
sp.inputs["Alpha"].default_value = 0.30
sp.inputs["Roughness"].default_value = 1.0
for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
    try:
        setattr(shadow_mat, attr, val)
    except Exception:
        pass


# ------------------------------------------------------------------ parts
def _finish(o, name, material, bevel):
    o.name = name
    if material is not None:
        o.data.materials.append(material)
    if bevel:
        b = o.modifiers.new("bevel", "BEVEL")
        b.width = bevel
        b.segments = 2
        b.limit_method = "ANGLE"
    for poly in o.data.polygons:
        poly.use_smooth = False
    o.parent = root
    return o


def box(name, size, loc, material, bevel=0.06, rot=(0, 0, 0)):
    """An axis-aligned block. size=(x,y,z) full extents; rot in radians."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.scale = size
    o.rotation_euler = rot
    return _finish(o, name, material, bevel)


def cyl(name, r, depth, loc, material, verts=14, rot=(0, math.pi / 2, 0), bevel=0.0, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = scale
    return _finish(o, name, material, bevel)


def wheel(loc, r=0.42, w=0.30, knobbly=False):
    """A tyre as a short cylinder with a two-tone rim, partly inside the arch.
    Knobbly: two coarse decagons half a step apart give a toothed outline."""
    if knobbly:
        cyl("tyre", r, w, loc, M["tyre"], verts=10, bevel=0.03)
        cyl("tyre_k", r * 0.94, w * 1.08, loc, M["tyre"], verts=10, rot=(0, math.pi / 2, math.pi / 10), bevel=0.02)
    else:
        cyl("tyre", r, w, loc, M["tyre"], verts=14, bevel=0.03)
    cyl("rim", r * 0.6, w * 1.06, loc, M["rim"], verts=10)
    cyl("hub", r * 0.24, w * 1.12, loc, M["trim"], verts=8)


def wheels(xs, ys, r, w=0.30, knobbly=False):
    for y in ys:
        for x in xs:
            wheel((x, y, r), r, w, knobbly)


def livery(x_half, y0, length, z, height=0.30, stripe_dz=0.14):
    """The cream panel with its dark stripe, on both flanks, proud of the body
    by a few centimetres so it reads as paint on a flat cell."""
    for s in (-1, 1):
        box("livery", (0.06, length, height), (s * x_half, y0, z), M["livery"], bevel=0.0)
        box("stripe", (0.06, length, 0.06), (s * (x_half + 0.004), y0, z + stripe_dz), M["stripe"], bevel=0.0)


def roundels(x_half, y, z, r=0.30):
    """Blank cream roundels, one per door. Named for meta.json."""
    for s, name in ((-1, "roundel_L"), (1, "roundel_R")):
        cyl(name, r, 0.04, (s * x_half, y, z), M["livery"], verts=20)


def plate(y, z, w=0.90, h=0.34):
    """The blank rear number panel. Rally-sized: a two-digit number has to be
    legible from the road camera at scale 1.0, about 30x11 cell px."""
    box("plate", (w, 0.04, h), (0, y, z), M["livery"], bevel=0.0)


def lamps_front(y, z, spread, w=0.38, h=0.26):
    box("head_l", (w, 0.08, h), (-spread, y, z), M["head"], bevel=0.0)
    box("head_r", (w, 0.08, h), (spread, y, z), M["head"], bevel=0.0)


def tail_bar(y, z, w=1.64, h=0.18):
    """A wide red bar with a pale glow strip through it. On a red car the bar
    itself vanishes into the paint; the strip is what still reads as a lamp."""
    box("tail", (w, 0.08, h), (0, y, z), M["tail"], bevel=0.0)
    box("tail_glow", (w * 0.86, 0.10, h * 0.34), (0, y - 0.005, z), M["glow"], bevel=0.0)


def contact_shadow(sx, sy, y0=0.0):
    """A flat purple ellipse the size of the footprint, nudged a little toward
    the front-left, away from the sun, so a sliver shows past the sun-away
    side. Parented to the car so it turns with it."""
    sh = cyl("shadow", 1.0, 0.02, (-0.12, y0 + 0.16, 0.01), None, verts=28, rot=(0, 0, 0))
    sh.scale = (sx, sy, 1.0)
    sh.data.materials.append(shadow_mat)
    return sh


# Car faces +Y. Units: roughly metres. Every body differs below the beltline:
# wheelbase, ride height, arch size, overhang and tyre radius are all its own.
# ---------------------------------------------------------------------------
def body_coupe():
    """Boxy 80s Group B coupe: long bonnet, upright cabin, flared arches, a
    small wing. Wheelbase 2.6, ride 0.30, tyre 0.42."""
    box("body", (1.90, 4.20, 0.56), (0, 0.0, 0.58), M["paint"], bevel=0.08)
    box("nose", (1.84, 1.20, 0.30), (0, 1.55, 0.98), M["paint"], bevel=0.06)
    box("deck", (1.84, 1.10, 0.30), (0, -1.55, 0.98), M["paint"], bevel=0.06)
    box("cabin", (1.44, 1.86, 0.52), (0, -0.20, 1.10), M["paint"], bevel=0.09)
    box("glass", (1.48, 1.62, 0.20), (0, -0.20, 1.18), M["glass"], bevel=0.02)
    box("glass_f", (1.20, 0.30, 0.20), (0, 0.78, 1.18), M["glass"], bevel=0.0, rot=(math.radians(-38), 0, 0))
    box("glass_r", (1.20, 0.26, 0.20), (0, -1.16, 1.18), M["glass"], bevel=0.0, rot=(math.radians(40), 0, 0))
    for x in (-1.0, 1.0):
        box("arch_f", (0.36, 1.10, 0.50), (x * 0.95, 1.30, 0.62), M["paint"], bevel=0.07)
        box("arch_r", (0.36, 1.10, 0.50), (x * 0.95, -1.30, 0.62), M["paint"], bevel=0.07)
        box("sill", (0.10, 2.10, 0.14), (x * 0.99, 0.0, 0.36), M["stripe"], bevel=0.02)
    livery(0.985, 0.0, 2.40, 0.64)
    box("wing", (1.76, 0.32, 0.06), (0, -2.00, 1.20), M["paint"], bevel=0.02)
    box("wing_lp", (0.12, 0.26, 0.18), (-0.72, -2.00, 1.10), M["trim"], bevel=0.0)
    box("wing_rp", (0.12, 0.26, 0.18), (0.72, -2.00, 1.10), M["trim"], bevel=0.0)
    box("bumper_f", (1.96, 0.20, 0.26), (0, 2.12, 0.38), M["trim"], bevel=0.04)
    box("bumper_r", (1.70, 0.20, 0.26), (0, -2.12, 0.40), M["trim"], bevel=0.04)
    box("grille", (1.10, 0.05, 0.20), (0, 2.13, 0.72), M["ink"], bevel=0.0)
    lamps_front(2.15, 0.76, 0.62)
    tail_bar(-2.15, 1.00, h=0.16)
    plate(-2.16, 0.70)
    roundels(1.005, -0.15, 0.72, r=0.33)
    wheels((-1.03, 1.03), (1.30, -1.30), 0.42)
    contact_shadow(1.35, 2.35)


def body_hatch():
    """Hot hatch: short, tall cabin, near-vertical tailgate, tiny overhangs.
    Wheelbase 2.2, ride 0.30, tyre 0.40."""
    box("body", (1.86, 3.50, 0.60), (0, 0.0, 0.60), M["paint"], bevel=0.08)
    box("nose", (1.80, 0.90, 0.30), (0, 1.25, 1.02), M["paint"], bevel=0.06)
    box("cabin", (1.52, 2.20, 0.66), (0, -0.50, 1.20), M["paint"], bevel=0.09)
    box("tailgate", (1.66, 0.22, 0.74), (0, -1.66, 1.04), M["paint"], bevel=0.05, rot=(math.radians(8), 0, 0))
    box("glass", (1.56, 1.94, 0.24), (0, -0.50, 1.30), M["glass"], bevel=0.02)
    box("glass_f", (1.26, 0.36, 0.22), (0, 0.66, 1.30), M["glass"], bevel=0.0, rot=(math.radians(-46), 0, 0))
    box("glass_r", (1.30, 0.20, 0.30), (0, -1.70, 1.34), M["glass"], bevel=0.0, rot=(math.radians(10), 0, 0))
    box("spoiler", (1.50, 0.30, 0.06), (0, -1.70, 1.56), M["paint"], bevel=0.02)
    for x in (-1.0, 1.0):
        box("arch_f", (0.34, 1.00, 0.48), (x * 0.94, 1.10, 0.62), M["paint"], bevel=0.07)
        box("arch_r", (0.34, 1.00, 0.48), (x * 0.94, -1.10, 0.62), M["paint"], bevel=0.07)
        box("sill", (0.10, 1.50, 0.14), (x * 0.97, 0.0, 0.36), M["stripe"], bevel=0.02)
    livery(0.965, 0.0, 1.80, 0.66)
    box("bumper_f", (1.92, 0.20, 0.28), (0, 1.72, 0.40), M["trim"], bevel=0.04)
    box("bumper_r", (1.64, 0.20, 0.28), (0, -1.72, 0.42), M["trim"], bevel=0.04)
    box("grille", (1.00, 0.05, 0.18), (0, 1.73, 0.76), M["ink"], bevel=0.0)
    lamps_front(1.75, 0.82, 0.58, w=0.34, h=0.28)
    tail_bar(-1.81, 1.10, w=1.56, h=0.16)
    plate(-1.82, 0.76)
    roundels(0.985, -0.20, 0.76, r=0.30)
    wheels((-1.01, 1.01), (1.10, -1.10), 0.40)
    contact_shadow(1.30, 1.95)


def body_wedge():
    """Group B wedge: low splitter nose, mid cabin, huge rear wing on tall
    posts, bigger rear tyres. Wheelbase 2.55, ride 0.27, tyres 0.42/0.47."""
    box("body", (1.96, 4.40, 0.46), (0, 0.0, 0.50), M["paint"], bevel=0.08)
    box("nose", (1.88, 1.70, 0.34), (0, 1.35, 0.76), M["paint"], bevel=0.06, rot=(math.radians(10), 0, 0))
    box("cabin", (1.42, 1.60, 0.44), (0, -0.30, 0.96), M["paint"], bevel=0.09)
    box("glass", (1.46, 1.36, 0.20), (0, -0.30, 1.04), M["glass"], bevel=0.02)
    box("glass_f", (1.26, 0.56, 0.16), (0, 0.66, 0.98), M["glass"], bevel=0.0, rot=(math.radians(-58), 0, 0))
    box("deck", (1.90, 1.30, 0.30), (0, -1.55, 0.78), M["paint"], bevel=0.06)
    box("wing", (2.16, 0.42, 0.07), (0, -2.05, 1.46), M["paint"], bevel=0.02)
    box("wing_lp", (0.10, 0.30, 0.60), (-0.82, -2.02, 1.12), M["trim"], bevel=0.0)
    box("wing_rp", (0.10, 0.30, 0.60), (0.82, -2.02, 1.12), M["trim"], bevel=0.0)
    box("wing_el", (0.06, 0.44, 0.24), (-1.10, -2.05, 1.46), M["paint"], bevel=0.0)
    box("wing_er", (0.06, 0.44, 0.24), (1.10, -2.05, 1.46), M["paint"], bevel=0.0)
    for x in (-1.0, 1.0):
        box("arch_f", (0.40, 1.10, 0.46), (x * 1.00, 1.30, 0.56), M["paint"], bevel=0.07)
        box("arch_r", (0.48, 1.24, 0.54), (x * 1.02, -1.25, 0.62), M["paint"], bevel=0.07)
        box("sill", (0.10, 2.00, 0.12), (x * 1.02, 0.0, 0.32), M["stripe"], bevel=0.02)
    livery(1.02, 0.05, 2.20, 0.58, height=0.26)
    box("splitter", (2.02, 0.34, 0.08), (0, 2.12, 0.30), M["trim"], bevel=0.02)
    box("bumper_r", (1.70, 0.18, 0.24), (0, -2.22, 0.38), M["trim"], bevel=0.04)
    box("grille", (0.90, 0.05, 0.14), (0, 2.18, 0.58), M["ink"], bevel=0.0, rot=(math.radians(10), 0, 0))
    lamps_front(2.19, 0.62, 0.62, w=0.42, h=0.20)
    tail_bar(-2.23, 0.86, w=1.70, h=0.14)
    plate(-2.24, 0.62, h=0.30)
    roundels(1.045, -0.25, 0.66, r=0.30)
    wheels((-1.06, 1.06), (1.30,), 0.42)
    wheels((-1.10, 1.10), (-1.25,), 0.47, w=0.36)
    contact_shadow(1.40, 2.45)


def body_saloon():
    """Three-box saloon: longer, modest lip spoiler, longer overhangs, the
    smallest arches. Wheelbase 2.85, ride 0.35, tyre 0.40."""
    box("body", (1.88, 4.70, 0.54), (0, 0.0, 0.62), M["paint"], bevel=0.08)
    box("bonnet", (1.80, 1.40, 0.26), (0, 1.55, 1.02), M["paint"], bevel=0.06)
    box("cabin", (1.46, 1.90, 0.50), (0, -0.05, 1.14), M["paint"], bevel=0.09)
    box("glass", (1.50, 1.66, 0.20), (0, -0.05, 1.22), M["glass"], bevel=0.02)
    box("glass_f", (1.24, 0.34, 0.20), (0, 0.95, 1.22), M["glass"], bevel=0.0, rot=(math.radians(-40), 0, 0))
    box("glass_r", (1.24, 0.30, 0.20), (0, -1.06, 1.22), M["glass"], bevel=0.0, rot=(math.radians(42), 0, 0))
    box("boot", (1.80, 1.20, 0.30), (0, -1.72, 1.00), M["paint"], bevel=0.06)
    box("lip", (1.40, 0.16, 0.05), (0, -2.28, 1.16), M["paint"], bevel=0.0)
    for x in (-1.0, 1.0):
        box("arch_f", (0.28, 1.04, 0.44), (x * 0.94, 1.42, 0.60), M["paint"], bevel=0.06)
        box("arch_r", (0.28, 1.04, 0.44), (x * 0.94, -1.42, 0.60), M["paint"], bevel=0.06)
        box("sill", (0.10, 2.40, 0.12), (x * 0.97, 0.0, 0.38), M["stripe"], bevel=0.02)
        box("trimline", (0.04, 4.00, 0.05), (x * 0.955, 0.0, 0.92), M["trim"], bevel=0.0)
    livery(0.965, 0.0, 2.70, 0.66)
    box("bumper_f", (1.94, 0.20, 0.26), (0, 2.38, 0.42), M["trim"], bevel=0.04)
    box("bumper_r", (1.66, 0.20, 0.26), (0, -2.38, 0.44), M["trim"], bevel=0.04)
    box("grille", (1.00, 0.05, 0.18), (0, 2.39, 0.78), M["ink"], bevel=0.0)
    lamps_front(2.41, 0.80, 0.62, w=0.36, h=0.22)
    tail_bar(-2.41, 1.04, w=1.60, h=0.16)
    plate(-2.42, 0.76)
    roundels(0.985, -0.05, 0.76, r=0.31)
    wheels((-1.00, 1.00), (1.42, -1.42), 0.40)
    contact_shadow(1.32, 2.60)


def body_buggy():
    """Open-frame buggy: a short tub, roll cage, exposed suspension, big
    knobbly tyres on a wide track. Wheelbase 2.4, ride 0.60, tyre 0.55."""
    box("tub", (1.30, 2.60, 0.50), (0, 0.10, 0.85), M["paint"], bevel=0.07)
    box("nose", (1.16, 0.80, 0.30), (0, 1.60, 0.80), M["paint"], bevel=0.06, rot=(math.radians(14), 0, 0))
    box("floor", (1.40, 3.20, 0.10), (0, 0.10, 0.62), M["trim"], bevel=0.02)
    box("seat_l", (0.40, 0.50, 0.42), (-0.30, -0.30, 1.28), M["ink"], bevel=0.03)
    box("seat_r", (0.40, 0.50, 0.42), (0.30, -0.30, 1.28), M["ink"], bevel=0.03)
    box("dash", (1.20, 0.30, 0.20), (0, 0.55, 1.18), M["trim"], bevel=0.02)
    box("screen", (1.10, 0.06, 0.36), (0, 0.80, 1.34), M["glass"], bevel=0.0, rot=(math.radians(-22), 0, 0))
    # roll cage: four posts, two rails, two hoops
    for x in (-0.58, 0.58):
        box("post_r", (0.09, 0.09, 0.96), (x, -0.50, 1.56), M["cage"], bevel=0.0)
        box("post_f", (0.09, 0.09, 0.96), (x, 0.62, 1.52), M["cage"], bevel=0.0, rot=(math.radians(-12), 0, 0))
        box("rail", (0.09, 1.20, 0.09), (x, 0.06, 2.02), M["cage"], bevel=0.0)
    box("hoop_r", (1.25, 0.09, 0.09), (0, -0.50, 2.02), M["cage"], bevel=0.0)
    box("hoop_f", (1.25, 0.09, 0.09), (0, 0.62, 1.98), M["cage"], bevel=0.0)
    box("brace", (0.09, 0.09, 0.80), (0.0, -1.00, 1.60), M["cage"], bevel=0.0, rot=(math.radians(30), 0, 0))
    # exposed suspension: an arm out to each wheel and a spring above it
    for y in (1.20, -1.20):
        for x in (-1, 1):
            box("arm", (0.60, 0.12, 0.08), (x * 0.72, y, 0.56), M["trim"], bevel=0.0)
            box("spring", (0.12, 0.12, 0.50), (x * 0.86, y, 0.84), M["rim"], bevel=0.0, rot=(0, math.radians(x * -22), 0))
    livery(0.655, 0.05, 1.60, 0.86, height=0.26, stripe_dz=0.12)
    box("bumper_f", (1.60, 0.12, 0.12), (0, 2.02, 0.66), M["cage"], bevel=0.0)
    box("bumper_r", (1.60, 0.12, 0.12), (0, -1.60, 0.66), M["cage"], bevel=0.0)
    box("head_l", (0.30, 0.16, 0.30), (-0.38, 1.98, 1.02), M["head"], bevel=0.02)
    box("head_r", (0.30, 0.16, 0.30), (0.38, 1.98, 1.02), M["head"], bevel=0.02)
    box("rear_panel", (1.28, 0.10, 0.56), (0, -1.22, 0.92), M["paint"], bevel=0.03)
    tail_bar(-1.28, 1.12, w=1.10, h=0.12)
    plate(-1.29, 0.84, w=0.80, h=0.30)
    roundels(0.675, -0.25, 0.92, r=0.27)
    wheels((-1.00, 1.00), (1.20, -1.20), 0.55, w=0.40, knobbly=True)
    contact_shadow(1.40, 2.05)


def body_pickup():
    """Cab-forward pickup: short bonnet, open bed with a roll bar, high
    stance, the longest wheelbase. Wheelbase 2.9, ride 0.52, tyre 0.48."""
    box("chassis", (1.90, 4.60, 0.40), (0, -0.10, 0.72), M["paint"], bevel=0.07)
    box("cab", (1.72, 1.60, 0.72), (0, 0.95, 1.28), M["paint"], bevel=0.09)
    box("bonnet", (1.82, 0.60, 0.30), (0, 2.05, 1.02), M["paint"], bevel=0.06)
    box("glass", (1.76, 1.34, 0.24), (0, 0.95, 1.38), M["glass"], bevel=0.02)
    box("glass_f", (1.40, 0.30, 0.24), (0, 1.74, 1.38), M["glass"], bevel=0.0, rot=(math.radians(-34), 0, 0))
    box("glass_r", (1.34, 0.10, 0.26), (0, 0.15, 1.40), M["glass"], bevel=0.0)
    box("bed_l", (0.12, 2.20, 0.36), (-0.89, -1.10, 1.10), M["paint"], bevel=0.03)
    box("bed_r", (0.12, 2.20, 0.36), (0.89, -1.10, 1.10), M["paint"], bevel=0.03)
    box("tailgate", (1.74, 0.12, 0.36), (0, -2.14, 1.10), M["paint"], bevel=0.03)
    box("bed_floor", (1.66, 2.10, 0.06), (0, -1.10, 0.94), M["trim"], bevel=0.0)
    for x in (-0.74, 0.74):
        box("bar_post", (0.10, 0.10, 0.84), (x, -0.05, 1.52), M["cage"], bevel=0.0)
    box("bar_top", (1.58, 0.10, 0.10), (0, -0.05, 1.98), M["cage"], bevel=0.0)
    for x in (-1.0, 1.0):
        box("arch_f", (0.36, 1.16, 0.52), (x * 0.97, 1.25, 0.74), M["paint"], bevel=0.07)
        box("arch_r", (0.36, 1.16, 0.52), (x * 0.97, -1.65, 0.74), M["paint"], bevel=0.07)
        box("step", (0.14, 1.30, 0.10), (x * 0.98, -0.20, 0.44), M["trim"], bevel=0.02)
    livery(0.965, -0.30, 2.10, 0.80, height=0.28)
    box("bumper_f", (1.96, 0.22, 0.28), (0, 2.34, 0.54), M["trim"], bevel=0.04)
    box("bumper_r", (1.66, 0.22, 0.28), (0, -2.34, 0.56), M["trim"], bevel=0.04)
    box("grille", (1.10, 0.05, 0.22), (0, 2.36, 0.84), M["ink"], bevel=0.0)
    lamps_front(2.38, 0.90, 0.62, w=0.36, h=0.26)
    tail_bar(-2.21, 0.82, w=1.66, h=0.14)
    plate(-2.22, 1.10, h=0.30)
    roundels(0.875, 0.75, 0.96, r=0.30)
    wheels((-1.04, 1.04), (1.25, -1.65), 0.48, w=0.34)
    contact_shadow(1.40, 2.55, y0=-0.15)


BODIES = {
    "coupe": body_coupe, "hatch": body_hatch, "wedge": body_wedge,
    "saloon": body_saloon, "buggy": body_buggy, "pickup": body_pickup,
}
if BODY not in BODIES:
    raise SystemExit(f"unknown body {BODY}; one of {', '.join(BODIES)}")
BODIES[BODY]()


# ------------------------------------------------------------------ light
def sun(name, color, energy, direction):
    L = bpy.data.lights.new(name, "SUN")
    L.energy = energy
    L.color = color[:3]
    L.angle = math.radians(6)
    o = bpy.data.objects.new(name, L)
    sc.collection.objects.link(o)
    dx, dy, dz = direction  # from the light toward the car
    o.rotation_euler = (math.atan2(math.hypot(dx, dy), -dz), 0, math.atan2(dy, dx) - math.pi / 2)
    return o


# key: the low sun, behind-right of the car (car faces +Y; behind-right = -Y, +X).
# Strength is calibrated to the swatch. A Lambertian face under a sun of
# strength S renders at albedo * S * cos / pi, so S = 5.2 puts the roof and the
# flanks that face the sun (cos 0.5-0.6) at about 0.85-1.0 of the swatch, and
# only the chamfers that face it squarely (cos ~0.9) reach 1.5 -- the ramp's
# warm highlight, the rim the bar asks for. The paint keeps its hue.
# The key is only faintly warm: a warmer one (the prototype's ffe3c4) tinted
# the white paint to cream and the blue toward grey-blue, and both then
# snapped to the wrong palette entries. Warmth belongs in the ramp's rim step.
sun("key", rgb("fff0dc"), 5.2, (-0.55, 0.65, -0.62))
# fill: cool purple from the front-left, weak.
sun("fill", rgb("9a5ce6"), 1.2, (0.6, -0.6, -0.5))


# ------------------------------------------------------------------ cameras
def camera(name, loc, aim_z, lens):
    aim = bpy.data.objects.new(name + "_aim", None)
    sc.collection.objects.link(aim)
    aim.location = (0, 0, aim_z)
    cd = bpy.data.cameras.new(name)
    cd.lens = lens
    cd.sensor_fit = "HORIZONTAL"
    o = bpy.data.objects.new(name, cd)
    sc.collection.objects.link(o)
    o.location = loc
    tr = o.constraints.new("TRACK_TO")
    tr.target = aim
    tr.track_axis = "TRACK_NEGATIVE_Z"
    tr.up_axis = "UP_Y"
    return o


CAMERAS = {
    # above and off the rear-right shoulder: the garage stall, roster, countdown
    "stall": camera("stall", (5.4, -6.2, 3.7), 0.70, 46),
    # directly behind, slightly above: the track
    "road": camera("road", (0.0, -9.4, 2.8), 0.62, 54),
}


def project(cam, p):
    v = world_to_camera_view(sc, cam, Vector(p))
    return v.x, v.y


def frame_ground(cam, ground):
    """Shift the lens so the world origin lands at `ground`. Camera shift is in
    units of the sensor width, so a few Newton steps settle it exactly."""
    bpy.context.view_layer.update()
    for _ in range(6):
        u, v = project(cam, (0, 0, 0))
        du, dv = ground[0] - u, ground[1] - v
        if abs(du) < 1e-6 and abs(dv) < 1e-6:
            break
        cam.data.shift_x -= du
        cam.data.shift_y -= dv * CELL_H / CELL_W
        bpy.context.view_layer.update()


for cname, c in CAMERAS.items():
    frame_ground(c, GROUND[cname])


# ------------------------------------------------------------------ meta
def bbox_world(o):
    return [o.matrix_world @ Vector(c) for c in o.bound_box]


def rect_of(cam, o, shrink=(1.0, 1.0)):
    us, vs = zip(*(project(cam, p) for p in bbox_world(o)))
    x0, x1 = min(us) * CELL_W, max(us) * CELL_W
    y0, y1 = (1 - max(vs)) * CELL_H, (1 - min(vs)) * CELL_H
    w, h = (x1 - x0) * shrink[0], (y1 - y0) * shrink[1]
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    return {"x": round(cx - w / 2, 1), "y": round(cy - h / 2, 1), "w": round(w, 1), "h": round(h, 1)}


def facing(cam, o, normal_local):
    """cos of the angle between the panel's outward normal and the line to the
    camera; > 0 means the panel faces the lens."""
    n = (o.matrix_world.to_3x3() @ Vector(normal_local)).normalized()
    to_cam = (cam.matrix_world.translation - o.matrix_world.translation).normalized()
    return n.dot(to_cam)


def tilt(cam, o, axis_local):
    """Screen tilt, in degrees, of the panel's baseline axis: the text angle."""
    c = o.matrix_world.translation
    a = o.matrix_world.to_3x3() @ Vector(axis_local)
    u0, v0 = project(cam, c)
    u1, v1 = project(cam, c + a * 0.5)
    dx, dy = (u1 - u0) * CELL_W, -(v1 - v0) * CELL_H
    ang = math.degrees(math.atan2(dy, dx))
    if ang > 90:
        ang -= 180
    if ang <= -90:
        ang += 180
    return round(ang, 1)


def number_rect(cam):
    """The best-facing blank panel for this yaw: a door roundel or the rear
    plate. Both roundel cylinders were rotated pi/2 about Y, so local +Z is
    world +X before the yaw: outward for the right door, INWARD for the left,
    whose outward normal is therefore local -Z. The plate box's outward
    normal is local -Y."""
    best = None
    for name, normal, axis, shrink in (
        ("roundel_L", (0, 0, -1), (0, 1, 0), (0.80, 0.70)),
        ("roundel_R", (0, 0, 1), (0, 1, 0), (0.80, 0.70)),
        ("plate", (0, -1, 0), (1, 0, 0), (0.90, 0.80)),
    ):
        o = bpy.data.objects[name]
        f = facing(cam, o, normal)
        if best is None or f > best[0]:
            best = (f, name, o, axis, shrink)
    f, name, o, axis, shrink = best
    r = rect_of(cam, o, shrink)
    # A panel seen at more than ~65 degrees off-axis is a sliver no digit fits.
    visible = f > 0.42 and r["w"] >= 6 and r["h"] >= 5
    r["angle"] = tilt(cam, o, axis) if visible else 0
    r["visible"] = visible
    r["on"] = "door" if name.startswith("roundel") else "plate"
    return r


def tail_lamps(cam):
    o = bpy.data.objects["tail"]
    m = o.matrix_world
    half = o.scale.x / 2 * 0.8
    pts = []
    for s in (-1, 1):
        u, v = project(cam, m @ Vector((s * half / o.scale.x, 0, 0)))
        pts.append([round(u * CELL_W, 1), round((1 - v) * CELL_H, 1)])
    return {"tail": pts, "visible": facing(cam, o, (0, -1, 0)) > 0.1}


EXTENT = {}


def extent(cam, label):
    """Track the projected bounds of every part's bounding box over the yaws;
    a body that leaves its cell fails the bake -- it is a bug, not a crop."""
    e = EXTENT.setdefault(label, [1.0, 0.0, 1.0, 0.0])
    for o in root.children:
        m = o.matrix_world
        for vert in o.data.vertices:
            u, v = project(cam, m @ vert.co)
            e[0], e[1], e[2], e[3] = min(e[0], u), max(e[1], u), min(e[2], v), max(e[3], v)


def assert_fits():
    bad = []
    for label, (u0, u1, v0, v1) in EXTENT.items():
        span = f"x {u0 * CELL_W:.1f}..{u1 * CELL_W:.1f} y {(1 - v1) * CELL_H:.1f}..{(1 - v0) * CELL_H:.1f}"
        print(f"EXTENT {label} {span}")
        if u0 < 0 or u1 > 1 or v0 < 0 or v1 > 1:
            bad.append(f"{BODY} leaves the {label} cell: {span}")
    if bad:
        raise SystemExit("\n".join(bad))


# ------------------------------------------------------------------ render
wanted = None
if ONLY:
    wanted = {(t.split(":")[0], int(t.split(":")[1])) for t in ONLY.split(",")}

meta = {
    "body": BODY,
    "cell": [[CELL_W, CELL_H], [CELL_W // 2, CELL_H // 2], [CELL_W // 4, CELL_H // 4]],
    "yaws": YAWS,
    "anchor": "bottom-center",
    "ground": {k: [round(g[0] * CELL_W, 1), round((1 - g[1]) * CELL_H, 1)] for k, g in GROUND.items()},
    "rects": "top-left origin, cell px at scale 1.0",
    "number": {"stall": [], "road": []},
    "lamps": {"stall": [], "road": []},
}
for cname, cam in CAMERAS.items():
    for i in range(YAWS):
        root.rotation_euler = (0, 0, math.radians(360.0 * i / YAWS))
        bpy.context.view_layer.update()
        extent(cam, cname)
        meta["number"][cname].append(number_rect(cam))
        meta["lamps"][cname].append(tail_lamps(cam))
assert_fits()

for cname, cam in CAMERAS.items():
    sc.camera = cam
    for i in range(YAWS):
        root.rotation_euler = (0, 0, math.radians(360.0 * i / YAWS))
        bpy.context.view_layer.update()
        if wanted is not None and (cname, i) not in wanted:
            continue
        sc.render.filepath = os.path.join(OUT, f"{cname}-{i}.png")
        bpy.ops.render.render(write_still=True)
        print("BAKED", sc.render.filepath)

with open(os.path.join(OUT, "meta.json"), "w") as f:
    json.dump(meta, f, indent=1, sort_keys=True)
    f.write("\n")
print("META", os.path.join(OUT, "meta.json"), "parts", len(root.children))
