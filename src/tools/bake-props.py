"""Turbo Tables prop kit -- the roadside landmarks and the power-up effect
sprites, modelled in bpy (this file IS the model; no .blend ever), rendered
headless through the same scene, key, fill and rim as bake-cars.py, from a
road camera whose distance scales with the prop's world size so every sprite
lands at a fixed pixels-per-unit: FINE (default 4) times the karts'.

Driven by src/tools/bake-props.ts (npm run props); never run by the shell.

  blender -b --python bake-props.py -- --out DIR [--only gantry,tireWall] [--px 2] [--fine 4]

Each prop renders one or more VIEWS (columns) at PX times its scale-1.0 cell:
  R  the prop standing on the right verge, seen from the road camera
  L  the same on the left verge (the geometry is placed at -x, not mirrored,
     so the sun stays on the right and the rim on the correct edge)
  f1 f2 ...  animation frames for props that move (flags, crowd)
Effect sprites render a single centred view with no ground anchor.
The pixel pass (px-props.py) turns the renders into one indexed sheet per prop.
"""
import bpy, math, os, sys, json
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(k, d): return argv[argv.index(k) + 1] if k in argv else d
OUT = arg("--out", "/tmp/props")
PX = int(arg("--px", "2"))          # supersample; 2 is enough at FINE 4
ONLY = [s for s in arg("--only", "").split(",") if s]
os.makedirs(OUT, exist_ok=True)

FINE = float(arg("--fine", "4.0"))   # props are a step finer than the cars: FINE times their pixels per unit
PX_PER_UNIT = 192 / 6.26 * FINE    # the karts' road camera is 192 px across 6.26 units at the anchor plane
CAR_CAM = dict(dist=9.4, height=1.8, aim_z=0.66, lens=54)

def srgb_to_linear(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def rgb(h, a=1.0): return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)) + (a,)

# ------------------------------------------------------------------ scene
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_percentage = 100
sc.render.film_transparent = True
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.render.image_settings.compression = 15
sc.view_settings.view_transform = "Standard"
sc.view_settings.look = "None"
sc.eevee.taa_render_samples = 16
sc.eevee.use_taa_reprojection = False
sc.eevee.use_raytracing = False
sc.eevee.use_shadows = True
sc.eevee.shadow_ray_count = 2
sc.eevee.shadow_step_count = 4
sc.render.use_motion_blur = False
world = bpy.data.worlds.new("dusk"); sc.world = world; world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs[0].default_value = rgb("5e1a50"); bg.inputs[1].default_value = 0.25

RIM_DIR = Vector((0.55, 0.45, 0.70)).normalized()

def sun(name, color, energy, direction):
    L = bpy.data.lights.new(name, "SUN"); L.energy = energy; L.color = color[:3]; L.angle = math.radians(6)
    o = bpy.data.objects.new(name, L); sc.collection.objects.link(o)
    dx, dy, dz = direction
    o.rotation_euler = (math.atan2(math.hypot(dx, dy), -dz), 0, math.atan2(dy, dx) - math.pi / 2)
    return o
sun("key", rgb("fff0dc"), 5.2, (-0.55, 0.65, -0.62))
sun("fill", rgb("9a5ce6"), 1.2, (0.6, -0.6, -0.5))

# ------------------------------------------------------------------ palette (pxart's fixed tones; ramps built the same way)
def hex2rgb(s): return tuple(int(s[i:i+2], 16) for i in (0, 2, 4))
def mixc(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
def hexof(c): return "%02x%02x%02x" % tuple(c)
def highlight(h): return hexof(mixc(hex2rgb(h), hex2rgb("fff0d0"), 0.36))

MATS = {}
def mat(name, color, rough=1.0, emit=None, strength=0.0, rim=True, alpha=None):
    if name in MATS: return MATS[name]
    m = bpy.data.materials.new(name); m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    p = nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = rgb(color)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Specular IOR Level"].default_value = 0.2
    if emit:
        p.inputs["Emission Color"].default_value = rgb(emit); p.inputs["Emission Strength"].default_value = strength
    if alpha is not None:
        p.inputs["Alpha"].default_value = alpha
        for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
            try: setattr(m, attr, val)
            except Exception: pass
    if rim and not emit:
        g = nodes.new("ShaderNodeNewGeometry"); dot = nodes.new("ShaderNodeVectorMath"); dot.operation = "DOT_PRODUCT"
        dot.inputs[1].default_value = RIM_DIR; links.new(g.outputs["Normal"], dot.inputs[0])
        ramp = nodes.new("ShaderNodeMapRange")
        ramp.inputs["From Min"].default_value = 0.70; ramp.inputs["From Max"].default_value = 0.84
        ramp.inputs["To Min"].default_value = 0.0; ramp.inputs["To Max"].default_value = 1.0; ramp.clamp = True
        links.new(dot.outputs["Value"], ramp.inputs["Value"])
        em = nodes.new("ShaderNodeEmission"); em.inputs["Color"].default_value = rgb(highlight(color)); em.inputs["Strength"].default_value = 1.0
        mix = nodes.new("ShaderNodeMixShader"); links.new(ramp.outputs["Result"], mix.inputs["Fac"])
        links.new(p.outputs["BSDF"], mix.inputs[1]); links.new(em.outputs["Emission"], mix.inputs[2])
        links.new(mix.outputs["Shader"], nodes["Material Output"].inputs["Surface"])
    MATS[name] = m
    return m

# tones from pxart.PALETTE_HEX, by role
INK, TRIM, STEEL, RIMC, CHROME = "1a1b26", "2a2b3d", "414868", "6b7291", "a9b1d6"
CREAM, CREAM2, CREAM3 = "f2e6c4", "d9c79a", "b09a6d"
AMBER, AMBER2, AMBERHI = "f5a524", "a8690f", "ffd489"
TEAL, TEAL2, TEALHI = "39b3ad", "12454a", "8fe3dc"
HAZ, HAZ2, HAZHI = "d8a12a", "7a5410", "ffe08a"
RED, RED2, WHITE, WHITE2 = "d13a33", "8c1f22", "d8d9e0", "a9aab4"
ORANGE, GREEN, BLUE = "ec8a2e", "6bc24a", "4a8ae8"
TYRE, GROUND, SHADOWT = "1a1220", "3c1228", "5f255e"

# ------------------------------------------------------------------ parts
PARTS = []
def _finish(o, material, bevel=0.05, seg=2):
    o.data.materials.append(material)
    if bevel > 0:
        b = o.modifiers.new("bevel", "BEVEL"); b.width = bevel; b.segments = seg; b.limit_method = "ANGLE"
    for poly in o.data.polygons: poly.use_smooth = False
    PARTS.append(o)
    return o

def box(size, loc, material, bevel=0.05, rot=(0, 0, 0), seg=2):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    o = bpy.context.active_object; o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return _finish(o, material, bevel, seg)

def cyl(r, depth, loc, material, verts=12, rot=(0, 0, 0), bevel=0.0, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object; o.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return _finish(o, material, bevel)

def text(body, loc, material, size=0.5, extrude=0.02, rot=(math.pi / 2, 0, 0), align="CENTER"):
    cu = bpy.data.curves.new("t", "FONT"); cu.body = body; cu.size = size; cu.extrude = extrude
    cu.align_x = align; cu.align_y = "CENTER"
    o = bpy.data.objects.new("text", cu); sc.collection.objects.link(o)
    o.location = loc; o.rotation_euler = rot
    o.data.materials.append(material); PARTS.append(o)
    return o

def shadow(sx, sy, at=(0, 0)):
    m = mat("shadow", SHADOWT, rim=False, alpha=0.30)
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=1.0, depth=0.02, location=(at[0], at[1], 0.01))
    o = bpy.context.active_object; o.scale = (sx, sy, 1); bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(m); o.name = "shadow"; PARTS.append(o)
    return o

def checkers(x0, x1, z0, rows, cols, y, cell, a=CREAM, b=INK, depth=0.06):
    for r in range(rows):
        for c in range(cols):
            box((cell, depth, cell), (x0 + cell * (c + 0.5), y, z0 + cell * (r + 0.5)),
                mat("chk_" + (a if (r + c) % 2 == 0 else b), a if (r + c) % 2 == 0 else b, rim=False), bevel=0)

def flag_cloth(base, height, width, frame, a=CREAM, b=INK, cell=0.18):
    """A checkered flag on a pole; frame 0 hangs straight, frame 1 lifts its tail."""
    px, py, pz = base
    cyl(0.03, height, (px, py, pz + height / 2), mat("pole", RIMC), verts=8)
    rows, cols = 3, 4
    for r in range(rows):
        for c in range(cols):
            lift = (c / cols) * (0.10 if frame == 1 else 0.02)
            sway = (c / cols) ** 2 * (0.14 if frame == 1 else 0.0)
            box((cell, 0.03, cell), (px + cell * (c + 0.5), py + sway, pz + height - cell * (r + 0.5) + lift),
                mat("chk_" + (a if (r + c) % 2 == 0 else b), a if (r + c) % 2 == 0 else b, rim=False), bevel=0)

# ------------------------------------------------------------------ props
# Each prop: world footprint (w, h) in units, views, and a build(frame) function.
PROPS = {}
def prop(name, w, h, views=("R", "L"), frames=1, effect=False, lateral=3.4, paints=()):
    def deco(fn):
        PROPS[name] = dict(w=w, h=h, views=views, frames=frames, build=fn, effect=effect, lateral=lateral, paints=list(paints))
        return fn
    return deco

@prop("gantry", 9.8, 4.6, views=("C",), frames=2, lateral=0)
def build_gantry(frame):
    steel = mat("steel", STEEL); ink = mat("ink", INK, rim=False)
    for sx in (-1, 1):
        x = sx * 4.5
        # lattice pillar: two uprights and cross braces
        for dx in (-0.16, 0.16):
            box((0.10, 0.10, 3.9), (x + dx, 0, 1.95), steel, bevel=0.02)
        for i in range(5):
            z = 0.45 + i * 0.75
            box((0.36, 0.06, 0.05), (x, 0, z), steel, bevel=0)
            box((0.05, 0.06, 0.62), (x, 0, z + 0.36), steel, bevel=0, rot=(0, math.radians(38 * (1 if i % 2 else -1)), 0))
        box((0.60, 0.44, 0.16), (x, 0, 0.08), mat("base", TRIM), bevel=0.02)
    # beam with a checkered band and a lit board
    box((9.4, 0.36, 0.42), (0, 0, 4.05), steel, bevel=0.04)
    checkers(-4.7, 4.7, 3.60, 1, 26, -0.20, 0.36)
    box((5.2, 0.10, 0.80), (0, -0.24, 4.05), mat("board", INK, rim=False), bevel=0.02)
    text("TURBO TABLES", (0, -0.30, 4.05), mat("boardtext", AMBER, rim=False, emit=AMBER, strength=1.0), size=0.46)
    for i in range(6):
        x = -3.9 + i * 1.56
        box((0.30, 0.16, 0.16), (x, -0.30, 3.62), mat("lamp", "000000", rim=False, emit=AMBERHI, strength=1.0), bevel=0)
    flag_cloth((-4.5, -0.05, 4.26), 0.9, 0.7, frame)
    flag_cloth((4.5, -0.05, 4.26), 0.9, 0.7, frame)
    shadow(5.2, 0.5)

@prop("tireWall", 3.0, 0.95, paints=("red", "white"))
def build_tirewall(frame):
    tyre = mat("tyre", TYRE, rough=1.0); red = mat("bandred", RED); white = mat("bandwhite", WHITE)
    r, wdt = 0.36, 0.30
    for row, n in ((0, 5), (1, 4)):
        for i in range(n):
            y = -1.5 + r * 2 * i + (r if row else 0) + r
            z = r + row * r * 1.75
            cyl(r, wdt, (0, y, z), tyre, verts=12, rot=(0, math.pi / 2, 0), bevel=0.03)
            band = red if (i + row) % 2 == 0 else white
            cyl(r * 0.78, wdt + 0.02, (0, y, z), band, verts=12, rot=(0, math.pi / 2, 0), bevel=0)
            cyl(r * 0.36, wdt + 0.04, (0, y, z), mat("hub", TRIM, rim=False), verts=10, rot=(0, math.pi / 2, 0), bevel=0)
    shadow(0.6, 1.7)

@prop("banner", 3.2, 2.2, paints=("red",))
def build_banner(frame):
    pole = mat("pole", RIMC)
    for x in (-1.5, 1.5):
        cyl(0.045, 2.1, (x, 0, 1.05), pole, verts=8)
    box((3.1, 0.05, 0.95), (0, 0, 1.55), mat("cloth", CREAM), bevel=0.01)
    box((3.1, 0.06, 0.12), (0, 0, 2.04), mat("clothtrim", RED, rim=False), bevel=0)
    box((3.1, 0.06, 0.12), (0, 0, 1.06), mat("clothtrim", RED, rim=False), bevel=0)
    text("TURBO", (0, -0.04, 1.58), mat("bannertext", INK, rim=False), size=0.50)
    shadow(1.6, 0.25)

@prop("hayBale", 1.35, 0.75, paints=("yellow",))
def build_haybale(frame):
    hay = mat("hay", HAZ, rough=1.0)
    box((1.25, 0.75, 0.62), (0, 0, 0.31), hay, bevel=0.10, seg=3)
    for y in (-0.18, 0.18):
        box((1.29, 0.05, 0.05), (0, y, 0.34), mat("twine", HAZ2, rim=False), bevel=0)
    shadow(0.7, 0.45)

@prop("cone", 0.7, 0.9, paints=("orange", "white"))
def build_cone(frame):
    bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=0.24, radius2=0.05, depth=0.78, location=(0, 0, 0.45))
    o = bpy.context.active_object; _finish(o, mat("cone", ORANGE), bevel=0)
    box((0.62, 0.62, 0.06), (0, 0, 0.03), mat("conebase", INK, rim=False), bevel=0.01)
    cyl(0.17, 0.10, (0, 0, 0.42), mat("conewhite", WHITE, rim=False), verts=10, bevel=0)
    shadow(0.36, 0.36)

@prop("drum", 0.9, 1.1, paints=("blue",))
def build_drum(frame):
    cyl(0.36, 0.95, (0, 0, 0.475), mat("drum", BLUE), verts=12, bevel=0.03)
    for z in (0.28, 0.66):
        cyl(0.375, 0.05, (0, 0, z), mat("drumring", TRIM, rim=False), verts=12, bevel=0)
    cyl(0.34, 0.03, (0, 0, 0.965), mat("drumtop", TRIM, rim=False), verts=12, bevel=0)
    shadow(0.42, 0.42)

@prop("crowd", 4.2, 2.1, frames=4, paints=("red", "purple"))
def build_crowd(frame):
    dark = mat("crowd", "2a1030", rough=1.0, rim=False); dark2 = mat("crowd2", "3a1a44", rough=1.0, rim=False)
    import random
    rnd = random.Random(7)
    for x in (-1.9, -0.63, 0.63, 1.9):
        box((0.08, 0.08, 0.72), (x, 0.0, 0.36), mat("railpost", RIMC), bevel=0.01)
    box((4.2, 0.06, 0.08), (0, 0.0, 0.70), mat("rail", CHROME), bevel=0.01)   # a pipe rail they lean on
    box((4.2, 0.06, 0.08), (0, 0.0, 0.36), mat("rail", CHROME), bevel=0.01)
    for i in range(11):
        x = -1.95 + i * 0.39 + rnd.uniform(-0.05, 0.05)
        h = rnd.uniform(1.35, 1.7)
        shirt = [mat("shirt_" + c, c) for c in (TEAL2, RED2, "6b34b0", CREAM3, STEEL)][i % 5]
        # the wave: each person's phase is their place along the rail, so at any
        # frame a few are in the air, a few have arms up, and the rest stand
        phase = (i + frame) % 4
        jump = 0.22 if phase == 1 else (0.08 if phase == 2 else 0.0)
        arms = phase in (1, 2)
        body_h = h * 0.55
        box((0.30, 0.22, body_h), (x, 0.55, body_h / 2 + 0.05 + jump), shirt, bevel=0.06, seg=3)     # body
        cyl(0.11, 0.22, (x, 0.55, body_h + 0.16 + jump), dark, verts=8, bevel=0.03)                  # head
        for side in (-1, 1):                                                                         # arms
            if arms:
                box((0.07, 0.07, 0.42), (x + side * 0.20, 0.55, body_h + 0.12 + jump), shirt, bevel=0.02)
            else:
                box((0.07, 0.07, 0.40), (x + side * 0.20, 0.55, body_h * 0.55 + 0.05 + jump), shirt, bevel=0.02)
        if i % 3 == 0:
            up = 0.55 if arms else 0.25
            box((0.05, 0.05, 0.6), (x + 0.2, 0.55, body_h + up + jump), mat("stick", RIMC, rim=False), bevel=0)
            col = [AMBER, RED, TEAL, CREAM][i % 4]
            box((0.28, 0.03, 0.20), (x + 0.36, 0.55, body_h + up + 0.22 + jump), mat("flag_" + col, col, rim=False), bevel=0)
    shadow(2.2, 0.5, at=(0, 0.4))

@prop("wrench", 1.4, 1.4, views=("C",), frames=4, effect=True, lateral=0, paints=("white",))
def build_wrench(frame):
    """A spinning wrench, four frames of a quarter turn each, seen edge-on to
    the road camera so it reads as a thrown thing."""
    steel = mat("wrenchsteel", CHROME, rough=0.5)
    ang = frame * math.pi / 4
    c, sn = math.cos(ang), math.sin(ang)
    def at(u, v):  # along the shank (u) and across it (v): a rotation about Y by ang maps local z to (sin, 0, cos) and local x to (cos, 0, -sin)
        return (u * sn + v * c, 0, 0.7 + u * c - v * sn)
    box((0.16, 0.06, 0.78), at(0, 0), steel, bevel=0.03, rot=(0, ang, 0))
    for end in (-1, 1):
        # an open-end head: a ring with a notch cut by two jaw blocks around a gap
        cyl(0.20, 0.06, at(0.50 * end, 0), steel, verts=12, rot=(math.pi / 2, 0, 0), bevel=0.02)
        for side in (-1, 1):
            box((0.10, 0.08, 0.16), at(0.66 * end, side * 0.14), steel, bevel=0.01, rot=(0, ang, 0))

@prop("pileUp", 3.0, 1.6, views=("C",), effect=True, lateral=0, paints=("red", "white", "orange"))
def build_pileup(frame):
    """The Pile-Up card's aftermath across the lane: an overturned kart with
    its wheels in the air, a striped barricade knocked over against it, and a
    tyre that rolled away. Wheels-up is the one silhouette every child reads as
    a crash from any distance."""
    tyre = mat("tyre", TYRE); white = mat("bandwhite", WHITE); red = mat("bandred", RED)
    # the kart, upside down: chassis on the ground, cabin crushed under it, wheels up on stub axles
    yaw = 0.35
    rot = (math.pi, 0, yaw)
    box((1.30, 2.10, 0.42), (0.1, 0.1, 0.44), mat("wreck", ORANGE), bevel=0.06, rot=rot)                     # body shell
    box((1.00, 1.10, 0.30), (0.1, -0.1, 0.16), mat("wreckcab", TRIM), bevel=0.04, rot=rot)                    # cabin, on the tarmac
    box((0.80, 0.25, 0.12), (0.1, -1.05, 0.62), mat("tail", "000000", rim=False, emit="f01a1a", strength=1.0), bevel=0, rot=rot)  # tail bar, now on top
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx = 0.1 + sx * 0.70 * math.cos(yaw) - sy * 0.75 * math.sin(yaw); cy = 0.1 + sx * 0.70 * math.sin(yaw) + sy * 0.75 * math.cos(yaw)
            cyl(0.06, 0.30, (cx, cy, 0.78), mat("axle", STEEL), verts=8, rot=(0, math.pi / 2, yaw))
            tilt = 0.25 if (sx, sy) == (1, -1) else 0.0                                                      # one wheel hangs crooked
            cyl(0.36, 0.30, (cx, cy, 0.98), tyre, verts=12, rot=(tilt, math.pi / 2, yaw), bevel=0.03)
            cyl(0.36 * 0.55, 0.32, (cx, cy, 0.98), mat("rim", RIMC), verts=10, rot=(tilt, math.pi / 2, yaw), bevel=0)
    # the barricade, a striped sawhorse knocked over against the kart's flank
    bar_rot = (0, -0.55, -0.35)
    bx, by = -1.25, -0.55
    box((1.90, 0.10, 0.28), (bx, by, 0.55), white, bevel=0.02, rot=bar_rot)
    for i in range(5):
        u = -0.80 + i * 0.40
        box((0.20, 0.11, 0.30), (bx + u * math.cos(bar_rot[2]) - 0.0, by + u * math.sin(bar_rot[2]), 0.55 - u * math.sin(bar_rot[1]) * 0.0), red, bevel=0, rot=bar_rot)
    for leg in (-0.75, 0.75):
        box((0.08, 0.50, 0.60), (bx + leg * math.cos(bar_rot[2]), by + leg * math.sin(bar_rot[2]), 0.30), mat("barleg", STEEL), bevel=0.01, rot=(0.6, bar_rot[1], bar_rot[2]))
    # the tyre that rolled clear, standing on its tread
    cyl(0.36, 0.30, (1.55, 0.35, 0.36), tyre, verts=12, rot=(math.pi / 2, 0, 0.2), bevel=0.03)
    cyl(0.36 * 0.78, 0.32, (1.55, 0.35, 0.36), white, verts=12, rot=(math.pi / 2, 0, 0.2), bevel=0)
    shadow(1.7, 1.2)


WOOD, WOOD2, WOODHI = "b09a6d", "7a5410", "d9c79a"
ROCK, ROCK2, ROCK3 = "414868", "2a2b3d", "6b7291"
PINE, PINE2 = "12454a", "082326"

@prop("distanceBoard", 1.3, 1.9, paints=("red",))
def build_distance(frame):
    """A distance board on a post: 200 on frame 0, 100 on frame 1 -- two
    boards from one model, so a corner announces itself twice."""
    cyl(0.05, 1.3, (0, 0, 0.65), mat("pole", RIMC), verts=8)
    box((1.2, 0.06, 0.62), (0, 0, 1.55), mat("boardcream", CREAM), bevel=0.02)
    box((1.2, 0.07, 0.10), (0, 0, 1.82), mat("bandred", RED, rim=False), bevel=0)
    text("200" if frame == 0 else "100", (0, -0.04, 1.50), mat("boardink", INK, rim=False), size=0.42)
    shadow(0.5, 0.2)
PROPS["distanceBoard"]["frames"] = 2

@prop("markerPost", 0.3, 1.3, paints=("red", "white"))
def build_marker(frame):
    for i in range(4):
        box((0.12, 0.12, 0.28), (0, 0, 0.14 + i * 0.28), mat("bandred" if i % 2 == 0 else "bandwhite", RED if i % 2 == 0 else WHITE), bevel=0.01)
    box((0.16, 0.16, 0.06), (0, 0, 1.15), mat("postcap", INK, rim=False), bevel=0)
    shadow(0.12, 0.12)

@prop("pitBoard", 2.0, 2.0)
def build_pitboard(frame):
    """The timing board: a dark cabinet on legs with a lit teal readout the
    game prints over (the readout is a flat emitted tone, nothing baked in)."""
    for x in (-0.8, 0.8):
        box((0.08, 0.08, 1.0), (x, 0, 0.5), mat("steel", STEEL), bevel=0.01)
    box((2.0, 0.30, 0.90), (0, 0, 1.45), mat("cabinet", TRIM), bevel=0.03)
    box((1.80, 0.08, 0.62), (0, -0.14, 1.45), mat("readout", "000000", rim=False, emit=TEAL2, strength=1.0), bevel=0)
    box((1.80, 0.02, 0.06), (0, -0.19, 1.72), mat("readoutline", "000000", rim=False, emit=TEAL, strength=1.0), bevel=0)
    shadow(1.0, 0.3)

@prop("billboard", 3.8, 3.0)
def build_billboard(frame):
    """A blank cream board on two posts. The game prints the child's own facts
    on it in sector 11; nothing is baked into the face."""
    for x in (-1.5, 1.5):
        box((0.12, 0.12, 2.9), (x, 0, 1.45), mat("woodpost", WOOD2), bevel=0.01)
    box((3.8, 0.10, 1.80), (0, 0, 2.0), mat("boardcream", CREAM), bevel=0.02)
    box((3.9, 0.12, 0.10), (0, 0, 2.95), mat("boardframe", WOOD2, rim=False), bevel=0)
    box((3.9, 0.12, 0.10), (0, 0, 1.05), mat("boardframe", WOOD2, rim=False), bevel=0)
    shadow(1.9, 0.3)

@prop("waterTower", 2.8, 6.4)
def build_tower(frame):
    steel = mat("steel", STEEL)
    for sx, sy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        box((0.12, 0.12, 4.2), (sx * 0.9, sy * 0.9, 2.1), steel, bevel=0.01, rot=(sy * -0.06, sx * 0.06, 0))
    for z in (1.4, 2.8):
        box((2.0, 0.08, 0.08), (0, -0.9, z), steel, bevel=0)
        box((0.08, 2.0, 0.08), (-0.9, 0, z), steel, bevel=0); box((0.08, 2.0, 0.08), (0.9, 0, z), steel, bevel=0)
    cyl(1.35, 1.9, (0, 0, 5.15), mat("tank", CREAM2), verts=14, bevel=0.04)
    for z in (4.5, 5.15, 5.8):
        cyl(1.38, 0.08, (0, 0, z), mat("tankband", STEEL, rim=False), verts=14, bevel=0)
    bpy.ops.mesh.primitive_cone_add(vertices=14, radius1=1.45, radius2=0.1, depth=0.7, location=(0, 0, 6.45)); _finish(bpy.context.active_object, mat("tankroof", RED), bevel=0)
    text("PIT", (0, -1.44, 5.15), mat("towerink", INK, rim=False), size=0.55)
    shadow(1.5, 1.5)

@prop("rockWall", 6.5, 3.8, lateral=5.0)
def build_rock(frame):
    """A quarry face beside the road: a bank of faceted boulders, big at the
    back, small at the toe, with the warm rim on their sun edges."""
    import random
    rnd = random.Random(11)
    tones = [ROCK, ROCK2, ROCK3, "5f255e"]
    def boulder(x, y, z, r, tone):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=r, location=(x, y, z))
        o = bpy.context.active_object
        o.scale = (rnd.uniform(0.8, 1.4), rnd.uniform(0.7, 1.1), rnd.uniform(0.7, 1.2))
        o.rotation_euler = (rnd.uniform(0, 3.1), rnd.uniform(0, 3.1), rnd.uniform(0, 3.1))
        bpy.ops.object.transform_apply(scale=True, rotation=True)
        _finish(o, mat("rock_" + tone, tone, rough=1.0), bevel=0)
    # back row, big
    for i in range(5):
        boulder(-2.6 + i * 1.3 + rnd.uniform(-0.2, 0.2), 0.9, 1.6 + rnd.uniform(-0.3, 0.5), rnd.uniform(1.3, 1.7), tones[i % 3])
    # middle row
    for i in range(6):
        boulder(-2.9 + i * 1.15 + rnd.uniform(-0.2, 0.2), 0.2, 0.9 + rnd.uniform(-0.2, 0.3), rnd.uniform(0.9, 1.2), tones[(i + 1) % 3])
    # toe, small, spilling toward the road
    for i in range(7):
        boulder(-3.0 + i * 1.0 + rnd.uniform(-0.3, 0.3), -0.6 + rnd.uniform(-0.2, 0.2), 0.35, rnd.uniform(0.35, 0.55), tones[(i + 2) % 4])
    shadow(3.4, 1.0)

@prop("jetty", 1.8, 1.2, lateral=4.6)
def build_jetty(frame):
    """A wooden jetty running away from the road over the lake sector's water."""
    for i in range(7):
        y = i * 0.6
        box((1.5, 0.52, 0.08), (0, y, 0.62), mat("plank", WOOD if i % 2 else WOODHI), bevel=0.01)
    for i in range(4):
        for sx in (-1, 1):
            cyl(0.08, 0.75, (sx * 0.65, i * 1.2, 0.30), mat("pile", WOOD2), verts=8)
    box((0.06, 3.6, 0.06), (-0.72, 1.8, 1.0), mat("rail", WOOD2), bevel=0)
    for i in range(4):
        box((0.06, 0.06, 0.4), (-0.72, i * 1.2, 0.8), mat("rail", WOOD2), bevel=0)
    shadow(0.9, 2.2, at=(0, 1.8))

@prop("pine", 1.8, 4.6, frames=2)
def build_pine(frame):
    """Two silhouette pines from one model: frame 1 is a taller, thinner tree."""
    tall = 1.0 if frame == 0 else 1.25
    cyl(0.10, 1.0, (0, 0, 0.5), mat("trunk", PINE2), verts=8)
    z = 0.9
    for i, r in enumerate((0.85, 0.72, 0.58, 0.42, 0.26)):
        bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=r * (1.0 if frame == 0 else 0.85), radius2=0.02, depth=1.05 * tall, location=(0, 0, z + 0.5 * tall))
        _finish(bpy.context.active_object, mat("pine" if i % 2 == 0 else "pine2", PINE if i % 2 == 0 else PINE2), bevel=0)
        z += 0.62 * tall
    shadow(0.6, 0.35)

@prop("bridge", 9.8, 5.0, views=("C",), lateral=0)
def build_bridge(frame):
    """A wooden truss bridge over the road."""
    wood = mat("wood", WOOD); dark = mat("wooddark", WOOD2)
    for sx in (-1, 1):
        x = sx * 4.5
        box((0.45, 0.6, 3.6), (x, 0, 1.8), dark, bevel=0.03)
        box((0.9, 0.9, 0.25), (x, 0, 0.12), mat("stone", ROCK2), bevel=0.03)
    box((9.4, 0.7, 0.35), (0, 0, 3.8), wood, bevel=0.03)
    for i in range(11):
        x = -4.2 + i * 0.84
        box((0.12, 0.12, 1.2), (x, -0.32, 4.55), dark, bevel=0)
        box((0.12, 0.12, 1.15), (x + 0.42, -0.32, 4.55), dark, bevel=0, rot=(0, math.radians(38), 0))
    box((9.4, 0.12, 0.14), (0, -0.32, 5.1), wood, bevel=0)
    box((9.4, 0.12, 0.14), (0, -0.32, 4.4), wood, bevel=0)
    shadow(5.0, 0.5)

@prop("rollerDoor", 9.8, 5.6, views=("C",), lateral=0, frames=2)
def build_rollerdoor(frame):
    """The garage from the design: a long low building the road runs through,
    roller door up, work lamps on; frame 1 has one lamp off, for the flicker."""
    wall = mat("garagewall", TRIM); wall2 = mat("garagewall2", STEEL)
    for sx in (-1, 1):
        box((2.6, 1.6, 4.4), (sx * 4.0, 0, 2.2), wall if sx < 0 else wall2, bevel=0.04)
        box((0.5, 0.5, 0.9), (sx * 3.4, -0.6, 0.45), mat("drum", BLUE), bevel=0.03)
    box((9.8, 1.8, 0.9), (0, 0, 4.85), wall, bevel=0.04)
    box((9.9, 0.3, 0.16), (0, -0.9, 5.35), mat("garagetrim", CREAM3, rim=False), bevel=0)
    cyl(0.32, 5.6, (0, -0.55, 4.25), mat("rollerdrum", RIMC), verts=12, rot=(0, math.pi / 2, 0))
    for i in range(6):
        box((0.9, 0.05, 0.16), (-2.8 + i * 1.12, -0.6, 3.75), mat("doorslat", STEEL, rim=False), bevel=0)
    for i in range(3):
        on = not (frame == 1 and i == 1)
        box((0.34, 0.18, 0.14), (-2.2 + i * 2.2, -0.92, 4.45), mat("lampon" if on else "lampoff", "000000" if on else TRIM, rim=False, emit=AMBERHI if on else None, strength=1.0 if on else 0.0), bevel=0)
    text("PIT", (-4.0, -0.82, 3.2), mat("garageink", AMBER, rim=False, emit=AMBER, strength=1.0), size=0.7)
    shadow(5.0, 1.0)

@prop("overpass", 9.8, 4.8, views=("C",), lateral=0)
def build_overpass(frame):
    conc = mat("concrete", ROCK3); conc2 = mat("concrete2", ROCK)
    for sx in (-1, 1):
        box((1.2, 1.4, 3.4), (sx * 4.3, 0, 1.7), conc2, bevel=0.04)
    box((9.8, 2.0, 0.7), (0, 0, 3.75), conc, bevel=0.05)
    box((9.8, 0.12, 0.5), (0, -1.0, 4.35), conc2, bevel=0.02)
    for i in range(13):
        box((0.08, 0.08, 0.5), (-4.6 + i * 0.77, -1.06, 4.35), mat("railing", STEEL), bevel=0)
    box((9.8, 0.10, 0.08), (0, -1.06, 4.62), mat("railing", STEEL), bevel=0)
    box((2.6, 0.06, 0.18), (2.5, -1.03, 3.45), mat("stripe", HAZ, rim=False), bevel=0)
    shadow(5.0, 1.0)

@prop("scrapyard", 3.6, 2.6, paints=("red", "blue", "orange"))
def build_scrapyard(frame):
    """Three dead kart shells stacked, one on its side, wheels missing."""
    def shell(loc, rot, colour, name):
        box((1.30, 2.10, 0.45), loc, mat(name, colour), bevel=0.06, rot=rot)
        box((1.00, 1.00, 0.36), (loc[0], loc[1] - 0.1, loc[2] + 0.38), mat("wreckcab", TRIM), bevel=0.04, rot=rot)
    shell((-0.9, 0.2, 0.25), (0, 0, 0.3), RED2, "scrap_red")
    shell((0.9, 0.0, 0.25), (0, 0, -0.2), BLUE, "scrap_blue")
    shell((0.0, 0.1, 1.05), (0.15, 0, 0.9), ORANGE, "scrap_orange")
    tyre = mat("tyre", TYRE)
    cyl(0.36, 0.30, (-1.7, -0.6, 0.36), tyre, verts=12, rot=(math.pi / 2, 0, 0.4), bevel=0.03)
    cyl(0.36, 0.30, (1.6, -0.5, 0.15), tyre, verts=12, rot=(0, 0, 0), bevel=0.03)
    shadow(1.9, 1.2)


@prop("oilSlick", 2.2, 0.3, views=("C",), effect=True, lateral=0)
def build_oilslick(frame):
    """The Oil Slick card's decal: a flat dark spill across a lane, seen from
    the road camera so it foreshortens the way the road does."""
    bpy.ops.mesh.primitive_circle_add(vertices=16, radius=1.0, fill_type="NGON", location=(0, 0, 0.02))
    o = bpy.context.active_object; o.scale = (1.1, 0.7, 1); bpy.ops.object.transform_apply(scale=True)
    _finish(o, mat("oil", "0b0c12", rough=0.3, rim=False), bevel=0)
    bpy.ops.mesh.primitive_circle_add(vertices=12, radius=0.5, fill_type="NGON", location=(0.15, 0.1, 0.03))
    o = bpy.context.active_object; o.scale = (1.2, 0.6, 1); bpy.ops.object.transform_apply(scale=True)
    _finish(o, mat("oilsheen", "343a52", rough=0.2, rim=False), bevel=0)
    for x, y, r in ((-1.2, 0.3, 0.18), (1.25, -0.2, 0.14), (0.9, 0.55, 0.12)):
        bpy.ops.mesh.primitive_circle_add(vertices=8, radius=r, fill_type="NGON", location=(x, y, 0.02))
        _finish(bpy.context.active_object, mat("oil", "0b0c12", rough=0.3, rim=False), bevel=0)

@prop("pothole", 1.8, 0.3, views=("C",), effect=True, lateral=0)
def build_pothole(frame):
    """The Pothole card's decal: a broken-edged hole with a lighter rim of
    loose tarmac, flat on the road."""
    import random
    rnd = random.Random(5)
    bpy.ops.mesh.primitive_circle_add(vertices=14, radius=0.95, fill_type="NGON", location=(0, 0, 0.02))
    o = bpy.context.active_object; o.scale = (1.0, 0.75, 1)
    for v in o.data.vertices: v.co.x *= rnd.uniform(0.85, 1.15); v.co.y *= rnd.uniform(0.85, 1.15)
    bpy.ops.object.transform_apply(scale=True)
    _finish(o, mat("holerim", "2a2b3d", rough=1.0, rim=False), bevel=0)
    bpy.ops.mesh.primitive_circle_add(vertices=12, radius=0.72, fill_type="NGON", location=(0.05, 0, 0.03))
    o = bpy.context.active_object; o.scale = (1.0, 0.72, 1)
    for v in o.data.vertices: v.co.x *= rnd.uniform(0.85, 1.15); v.co.y *= rnd.uniform(0.85, 1.15)
    bpy.ops.object.transform_apply(scale=True)
    _finish(o, mat("hole", "0b0c12", rough=1.0, rim=False), bevel=0)
    for i in range(6):
        a = i * 1.05 + 0.3
        box((0.22, 0.10, 0.06), (math.cos(a) * 1.05, math.sin(a) * 0.8, 0.04), mat("rubble", "414868", rim=False), bevel=0, rot=(0, 0, a))

@prop("towHook", 0.9, 0.9, views=("C",), effect=True, lateral=0, frames=2)
def build_towhook(frame):
    """The Tow Hook card's hook head; the line is drawn in QML from the kart
    to this sprite. The ring is an open arc of short bars; frame 1 closes it
    with a latch once it has caught."""
    steel = mat("hooksteel", CHROME, rough=0.5)
    cyl(0.12, 0.35, (0, 0, 0.72), steel, verts=10)
    R = 0.26; cx, cz = 0.0, 0.34
    span = range(2, 13) if frame == 0 else range(0, 14)       # frame 0 leaves the right side open
    for i in span:
        a = i / 14 * 2 * math.pi + math.pi / 2
        box((0.12, 0.10, 0.14), (cx + R * math.cos(a), 0, cz + R * math.sin(a)), steel, bevel=0.02, rot=(0, -a, 0))
    if frame == 1:
        box((0.08, 0.08, 0.30), (0.22, 0, 0.42), mat("latch", RIMC), bevel=0.01, rot=(0, -0.35, 0))

@prop("hubcap", 0.7, 0.7, views=("C",), effect=True, lateral=0, frames=3)
def build_hubcap(frame):
    """The hubcap that flies off a Pothole hit: three frames of a tumble, from
    edge-on to face-on."""
    tilt = (0.0, 0.9, 1.7)[frame]
    cyl(0.32, 0.05, (0, 0, 0.35), mat("rim", RIMC, rough=0.4), verts=12, rot=(tilt, math.pi / 2, 0), bevel=0.01)
    cyl(0.14, 0.07, (0, 0, 0.35), mat("hubcentre", CHROME, rough=0.4), verts=10, rot=(tilt, math.pi / 2, 0), bevel=0)

# ------------------------------------------------------------------ camera and render
def camera(dist, height, aim_z, lens):
    aim = bpy.data.objects.new("aim", None); sc.collection.objects.link(aim); aim.location = (0, 0, aim_z)
    cd = bpy.data.cameras.new("cam"); cd.lens = lens; cd.sensor_fit = "HORIZONTAL"
    o = bpy.data.objects.new("cam", cd); sc.collection.objects.link(o); o.location = (0, -dist, height)
    tr = o.constraints.new("TRACK_TO"); tr.target = aim; tr.track_axis = "TRACK_NEGATIVE_Z"; tr.up_axis = "UP_Y"
    sc.camera = o
    return o, aim

def project(cam, p):
    v = world_to_camera_view(sc, cam, Vector(p)); return v.x, v.y

def frame_point(cam, p, target):
    bpy.context.view_layer.update()
    for _ in range(8):
        u, v = project(cam, p); du, dv = target[0] - u, target[1] - v
        if abs(du) < 1e-6 and abs(dv) < 1e-6: break
        cam.data.shift_x -= du; cam.data.shift_y -= dv * sc.render.resolution_y / sc.render.resolution_x
        bpy.context.view_layer.update()

def clear_parts():
    for o in list(PARTS):
        bpy.data.objects.remove(o, do_unlink=True)
    PARTS.clear()

def bounds_of_parts():
    lo = [1e9, 1e9, 1e9]; hi = [-1e9, -1e9, -1e9]
    bpy.context.view_layer.update()
    for o in PARTS:
        if o.name == "shadow": continue
        for corner in o.bound_box:
            wc = o.matrix_world @ Vector(corner)
            for i in range(3):
                lo[i] = min(lo[i], wc[i]); hi[i] = max(hi[i], wc[i])
    return lo, hi

meta = {}
for name, p in PROPS.items():
    if ONLY and name not in ONLY: continue
    # measure: the widest and tallest the prop gets over all its frames
    ext_w, ext_h = p["w"], p["h"]
    for f in range(p["frames"]):
        clear_parts(); p["build"](f); lo, hi = bounds_of_parts()
        ext_w = max(ext_w, 2 * max(abs(lo[0]), abs(hi[0]))); ext_h = max(ext_h, hi[2])
    clear_parts()
    cell_w = max(int(math.ceil(ext_w * PX_PER_UNIT * 1.14 / 8) * 8), int(0.55 * 192 * FINE))
    cell_h = int(math.ceil(ext_h * PX_PER_UNIT * 1.22 / 8) * 8) + (0 if p["effect"] else 16)
    p["h"] = ext_h
    ground_frac = 0.06 if p["effect"] else 0.14
    rig = {"cam": None, "aim": None}
    def setup(cw, chh):
        if rig["cam"] is not None:
            bpy.data.objects.remove(rig["cam"], do_unlink=True); bpy.data.objects.remove(rig["aim"], do_unlink=True)
        sc.render.resolution_x, sc.render.resolution_y = cw * PX, chh * PX
        # The camera backs off with the cell's WORLD width: cell_w / FINE is the
        # base-density pixel width, and 192 base px is the karts' 6.26-unit field,
        # so pixels per unit at the anchor plane stay constant whatever the cell.
        # A small prop must not pull the camera inside itself: the karts' camera
        # never comes closer than about half its stock distance, so neither does
        # this one. The cell then carries transparent margin, which is cheap.
        k = max(cw / (192 * FINE), 0.55)
        rig["cam"], rig["aim"] = camera(CAR_CAM["dist"] * k, CAR_CAM["height"] * k, CAR_CAM["aim_z"] * k, CAR_CAM["lens"])
        return rig["cam"], rig["aim"]
    cam, aim = setup(cell_w, cell_h)
    # Fit by projection: perspective pulls a receding jetty or a tall tank toward
    # the frame centre, which world extents cannot see. Project every corner of
    # every view and frame through the real camera and grow the cell until all
    # of them sit inside a 3 % margin, then use that cell for every render.
    for _ in range(5):
        need_w, need_h = 1.0, 1.0
        for view in p["views"]:
            for f in range(p["frames"]):
                clear_parts(); p["build"](f)
                off = {"R": p["lateral"], "L": -p["lateral"], "C": 0.0}[view]
                for o in PARTS: o.location.x += off
                g = 0.5 if p["effect"] else ground_frac
                anchor = (off, 0, p["h"] / 2) if p["effect"] else (off, 0, 0)
                frame_point(cam, anchor, (0.5, g))
                for o in PARTS:
                    if o.name == "shadow": continue
                    for corner in o.bound_box:
                        u, v = project(cam, o.matrix_world @ Vector(corner))
                        need_w = max(need_w, abs(u - 0.5) / 0.47)
                        if v > g: need_h = max(need_h, (v - g) / (0.97 - g))
                        else: need_h = max(need_h, (g - v) / max(1e-6, g - 0.03))
        clear_parts()
        if need_w <= 1.0 and need_h <= 1.0: break
        cell_w = int(math.ceil(cell_w * need_w / 8) * 8); cell_h = int(math.ceil(cell_h * need_h / 8) * 8)
        cam, aim = setup(cell_w, cell_h)
    views = []
    for view in p["views"]:
        for f in range(p["frames"]):
            clear_parts()
            p["build"](f)
            off = {"R": p["lateral"], "L": -p["lateral"], "C": 0.0}[view]
            for o in PARTS: o.location.x += off
            anchor = (off, 0, 0) if not p["effect"] else (off, 0, p["h"] / 2)
            frame_point(cam, anchor, (0.5, ground_frac if not p["effect"] else 0.5))
            tag = f"{view}{f}"
            sc.render.filepath = os.path.join(OUT, f"{name}-{tag}.png")
            bpy.ops.render.render(write_still=True)
            views.append(tag)
            print("BAKED", sc.render.filepath, cell_w, cell_h)
    meta[name] = dict(cell=[cell_w, cell_h], world=[p["w"], p["h"]], views=views, effect=p["effect"], paints=p["paints"],
                      ground=[cell_w / 2, cell_h * (1 - ground_frac)] if not p["effect"] else None)
    clear_parts()
    bpy.data.objects.remove(cam, do_unlink=True); bpy.data.objects.remove(aim, do_unlink=True)

with open(os.path.join(OUT, "props-meta.json"), "w") as f:
    json.dump(meta, f, indent=1, sort_keys=True); f.write("\n")
print("META", os.path.join(OUT, "props-meta.json"), list(meta))
