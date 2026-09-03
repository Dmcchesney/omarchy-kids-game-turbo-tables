"""Bake one low-poly rally car to an 8-yaw turnaround, headless.

  blender -b --python bake-car.py -- --body coupe --paint d13a33 --out DIR [--size 512] [--yaws 8]

The script IS the model: no .blend is read or written. Every part is a
primitive with a bevel modifier, flat-shaded, lit by one warm sun from
behind-right and a cool purple fill, rendered on transparent film with EEVEE.
Palette banding, outline and the final pixel grid are applied afterwards by
pxart.py, so this render stays clean and un-quantised.
"""
import bpy, math, sys, os

# ------------------------------------------------------------------ args
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(k, d):
    return argv[argv.index(k) + 1] if k in argv else d
BODY = arg("--body", "coupe"); PAINT = arg("--paint", "d13a33"); OUT = arg("--out", "/tmp/bake")
SIZE = int(arg("--size", "512")); YAWS = int(arg("--yaws", "8"))
os.makedirs(OUT, exist_ok=True)

def rgb(h, a=1.0):
    return (int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, a)

# ------------------------------------------------------------------ scene
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x = SIZE; sc.render.resolution_y = int(SIZE * 0.625)
sc.render.film_transparent = True
sc.render.image_settings.file_format = "PNG"; sc.render.image_settings.color_mode = "RGBA"
sc.view_settings.view_transform = "Standard"
try: sc.eevee.taa_render_samples = 16
except Exception: pass
world = bpy.data.worlds.new("dusk"); sc.world = world; world.use_nodes = True
bg = world.node_tree.nodes["Background"]; bg.inputs[0].default_value = rgb("5e1a50"); bg.inputs[1].default_value = 0.35

root = bpy.data.objects.new("car", None); sc.collection.objects.link(root)

# ------------------------------------------------------------------ materials
def mat(name, color, rough=1.0, emit=None, strength=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = rgb(color); p.inputs["Roughness"].default_value = rough
    if emit:
        p.inputs["Emission Color"].default_value = rgb(emit); p.inputs["Emission Strength"].default_value = strength
    return m
M = {
    "paint": mat("paint", PAINT, 0.85),
    "livery": mat("livery", "f2e6c4", 0.9),
    "stripe": mat("stripe", "3c1228", 0.9),
    "glass": mat("glass", "2a1030", 0.4),
    "tyre": mat("tyre", "1a1220", 1.0),
    "rim": mat("rim", "6b7291", 0.7),   # v2: mid grey -- a light rim quantised to cream under the paint-locked palette
    "trim": mat("trim", "2a2b3d", 0.8),
    "head": mat("head", "ffd489", 0.5, "ffd489", 6.0),
    "tail": mat("tail", "ff3b30", 0.5, "ff3b30", 5.0),
    "ink": mat("ink", "1a1220", 1.0),
}

# ------------------------------------------------------------------ parts
def box(name, size, loc, material, bevel=0.06, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object; o.name = name
    o.scale = (size[0], size[1], size[2]); o.rotation_euler = rot
    o.data.materials.append(material)
    if bevel:
        b = o.modifiers.new("bevel", "BEVEL"); b.width = bevel; b.segments = 2; b.limit_method = "ANGLE"
    for poly in o.data.polygons: poly.use_smooth = False
    o.parent = root
    return o

def wheel(name, loc, r=0.42, w=0.30):
    bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=r, depth=w, location=loc, rotation=(0, math.pi / 2, 0))
    t = bpy.context.active_object; t.name = name; t.data.materials.append(M["tyre"]); t.parent = root
    for poly in t.data.polygons: poly.use_smooth = False
    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=r * 0.6, depth=w * 1.06, location=loc, rotation=(0, math.pi / 2, 0))
    m = bpy.context.active_object; m.name = name + "_rim"; m.data.materials.append(M["rim"]); m.parent = root
    for poly in m.data.polygons: poly.use_smooth = False

def text(body, loc, size, material, rot=(math.pi / 2, 0, 0)):
    c = bpy.data.curves.new("num", "FONT"); c.body = body; c.size = size; c.align_x = "CENTER"; c.align_y = "CENTER"
    o = bpy.data.objects.new("num", c); sc.collection.objects.link(o)
    o.location = loc; o.rotation_euler = rot; o.data.materials.append(material); o.parent = root
    return o

# Car faces +Y. Units: about 4.2 long, 2.0 wide, 1.3 tall. Wheelbase 2.6.
if BODY == "coupe":  # boxy 80s coupe, Quattro-like: long bonnet, upright cabin, flared arches, small wing
    # v2: the body is a lower slab with a separate lower nose; the cabin is a
    # glass "greenhouse" band with a paint roof slab on top, so the window band
    # reads as a band and not a hairline; the wing is lower and its posts join
    # the deck; lamps are bigger; a flat purple contact shadow sits under it.
    box("body",  (1.90, 4.20, 0.56), (0, 0.0, 0.58), M["paint"], bevel=0.08)
    box("nose",  (1.84, 1.20, 0.30), (0, 1.55, 0.98), M["paint"], bevel=0.06)      # bonnet line, lower than the deck
    box("deck",  (1.84, 1.10, 0.30), (0, -1.55, 0.98), M["paint"], bevel=0.06)     # boot deck
    # v3: one paint cabin, and the glass as an INSET band that protrudes 2cm from
    # it -- v2's separate greenhouse plus a thin roof read as a box on a box.
    box("cabin", (1.44, 1.86, 0.52), (0, -0.20, 1.10), M["paint"], bevel=0.09)
    box("glass", (1.48, 1.62, 0.20), (0, -0.20, 1.18), M["glass"], bevel=0.02)
    box("glass_f", (1.20, 0.30, 0.20), (0, 0.78, 1.18), M["glass"], bevel=0.0, rot=(math.radians(-38), 0, 0))
    box("glass_r", (1.20, 0.26, 0.20), (0, -1.16, 1.18), M["glass"], bevel=0.0, rot=(math.radians(40), 0, 0))
    for x in (-1.0, 1.0):  # flared arches
        box("arch_f", (0.36, 1.10, 0.50), (x * 0.95, 1.30, 0.62), M["paint"], bevel=0.07)
        box("arch_r", (0.36, 1.10, 0.50), (x * 0.95, -1.30, 0.62), M["paint"], bevel=0.07)
        box("sill",  (0.10, 2.10, 0.14), (x * 0.99, 0.0, 0.36), M["stripe"], bevel=0.02)
        box("livery",(0.06, 2.40, 0.30), (x * 0.985, 0.0, 0.64), M["livery"], bevel=0.0)
        box("stripe",(0.06, 2.40, 0.06), (x * 0.99, 0.0, 0.78), M["stripe"], bevel=0.0)
    box("wing",   (1.76, 0.32, 0.06), (0, -2.00, 1.20), M["paint"], bevel=0.02)
    box("wing_lp",(0.12, 0.26, 0.18), (-0.72, -2.00, 1.10), M["trim"], bevel=0.0)
    box("wing_rp",(0.12, 0.26, 0.18), ( 0.72, -2.00, 1.10), M["trim"], bevel=0.0)
    box("bumper_f",(1.96, 0.20, 0.26), (0, 2.12, 0.38), M["trim"], bevel=0.04)
    box("bumper_r",(1.96, 0.20, 0.26), (0, -2.12, 0.38), M["trim"], bevel=0.04)
    box("grille", (1.10, 0.05, 0.20), (0, 2.13, 0.72), M["ink"], bevel=0.0)
    box("head_l", (0.38, 0.08, 0.26), (-0.62, 2.15, 0.76), M["head"], bevel=0.0)
    box("head_r", (0.38, 0.08, 0.26), ( 0.62, 2.15, 0.76), M["head"], bevel=0.0)
    box("tail",   (1.64, 0.08, 0.18), (0, -2.15, 0.80), M["tail"], bevel=0.0)
    box("plate",  (0.62, 0.04, 0.20), (0, -2.16, 0.56), M["livery"], bevel=0.0)
    # contact shadow: a flat purple disc under the car, half alpha, so the sprite
    # carries its own grounding the way a sheet should
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=1.0, depth=0.02, location=(0.1, 0.0, 0.01))
    sh = bpy.context.active_object; sh.name = "shadow"; sh.scale = (1.35, 2.35, 1.0); sh.parent = root
    sm = bpy.data.materials.new("shadow"); sm.use_nodes = True
    sp = sm.node_tree.nodes["Principled BSDF"]; sp.inputs["Base Color"].default_value = rgb("3c1228")
    sp.inputs["Alpha"].default_value = 0.55; sp.inputs["Roughness"].default_value = 1.0
    for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
        try: setattr(sm, attr, val)
        except Exception: pass
    sh.data.materials.append(sm)
    for x, r in ((-1.0, 0), (1.0, math.pi)):  # roundel with number on each door
        bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.30, depth=0.04, location=(x * 1.0, -0.15, 0.72), rotation=(0, math.pi / 2, 0))
        d = bpy.context.active_object; d.name = "roundel"; d.data.materials.append(M["livery"]); d.parent = root
        text("7", (x * 1.03, -0.15, 0.72), 0.42, M["ink"], rot=(math.pi / 2, 0, math.pi / 2 if x > 0 else -math.pi / 2))
    text("7", (0, -2.18, 0.60), 0.18, M["ink"], rot=(math.pi / 2, 0, math.pi))
    for y in (1.30, -1.30):
        wheel("wheel", (-0.98, y, 0.42)); wheel("wheel", (0.98, y, 0.42))
else:
    raise SystemExit(f"unknown body {BODY}")

# ------------------------------------------------------------------ light and camera
def sun(name, color, energy, direction):
    L = bpy.data.lights.new(name, "SUN"); L.energy = energy; L.color = color[:3]; L.angle = math.radians(6)
    o = bpy.data.objects.new(name, L); sc.collection.objects.link(o)
    # point the light along `direction` (from light toward the car)
    dx, dy, dz = direction; o.rotation_euler = (math.atan2(math.hypot(dx, dy), -dz), 0, math.atan2(dy, dx) - math.pi / 2)
    o.rotation_mode = "XYZ"
    return o
# key: the low sun, behind-right of the car (car faces +Y; "behind-right" = -Y, +X), low.
sun("key",  rgb("ffe3c4"), 3.2, (-0.55, 0.65, -0.35))   # v2: less orange, less hot, so red stays red
# fill: cool purple from the front-left, weak.
sun("fill", rgb("9a5ce6"), 0.9, (0.6, -0.6, -0.5))

aim = bpy.data.objects.new("aim", None); sc.collection.objects.link(aim); aim.location = (0, 0, 0.7)
cam_data = bpy.data.cameras.new("cam"); cam_data.lens = 50
cam = bpy.data.objects.new("cam", cam_data); sc.collection.objects.link(cam); sc.camera = cam
# above and off the rear-right shoulder, same feel as the garage stall camera
cam.location = (5.2, -6.0, 3.6)
tr = cam.constraints.new("TRACK_TO"); tr.target = aim; tr.track_axis = "TRACK_NEGATIVE_Z"; tr.up_axis = "UP_Y"

# ------------------------------------------------------------------ render the turnaround
for i in range(YAWS):
    root.rotation_euler = (0, 0, math.radians(360.0 * i / YAWS))
    sc.render.filepath = os.path.join(OUT, f"{BODY}-{PAINT}-yaw{i}.png")
    bpy.ops.render.render(write_still=True)
    print("BAKED", sc.render.filepath)
