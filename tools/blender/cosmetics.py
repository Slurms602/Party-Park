"""Builds the High graphics cosmetics (gloves, shoes, hats) and exports them as one glTF library.

Run from the repo root:
    $BLENDER -b -P tools/blender/cosmetics.py -- game/assets/models/cosmetics.glb

Coordinates: Blender Z is up and +Y is the bowler's forward (glTF turns that into Godot's -Z).
Hats are modelled in body space (the body is 1.5 tall, centred on the origin, top at z = 0.75).
Gloves are centred on the fist, shoes on the foot.
Material names are roles the game swaps per player: Accent, AccentDark, Body, BodyDark, ShoeA, ShoeB.
Every other material keeps its own colour.
"""
import math
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT = sys.argv[sys.argv.index("--") + 1]


def lin(hex_color):
    """sRGB hex -> linear RGB (glTF and Blender store linear colours)."""
    c = [int(hex_color[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


MATS = {}


def mat(name, hex_color="ffffff", rough=0.45, metal=0.0, emit=0.0):
    if name not in MATS:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*lin(hex_color), 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        if emit > 0.0:
            bsdf.inputs["Emission Color"].default_value = (*lin(hex_color), 1.0)
            bsdf.inputs["Emission Strength"].default_value = emit
        MATS[name] = m
    return MATS[name]


def active():
    return bpy.context.view_layer.objects.active


def finish(o, m=None, smooth=True, subsurf=0, bevel=0.0, decimate=1.0):
    """Apply transforms, optional bevel/subdivision, smooth shading and a material."""
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)  # bake placement into the mesh
    if bevel > 0.0:
        b = o.modifiers.new("bevel", "BEVEL")
        b.width = bevel
        b.segments = 3
        b.limit_method = "ANGLE"
    if subsurf > 0:
        s = o.modifiers.new("subsurf", "SUBSURF")
        s.levels = subsurf
        s.render_levels = subsurf
    if decimate < 1.0:
        d = o.modifiers.new("decimate", "DECIMATE")
        d.ratio = decimate
    for mod in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if smooth:
        bpy.ops.object.shade_smooth()
    if m is not None:
        o.data.materials.clear()
        o.data.materials.append(m)
    return o


def sphere(r, loc=(0, 0, 0), scale=(1, 1, 1), m=None, seg=32, rings=16, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, rotation=rot, segments=seg, ring_count=rings)
    o = active()
    o.scale = scale
    return finish(o, m)


def cone(r1, r2, depth, loc=(0, 0, 0), rot=(0, 0, 0), m=None, verts=40, subsurf=0, bevel=0.0, smooth=True):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth, location=loc, rotation=rot)
    return finish(active(), m, smooth, subsurf, bevel)


def torus(major, minor, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), m=None, seg=48, minor_seg=16):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=loc, rotation=rot,
                                     major_segments=seg, minor_segments=minor_seg)
    o = active()
    o.scale = scale
    return finish(o, m)


def box(size, loc=(0, 0, 0), rot=(0, 0, 0), m=None, bevel=0.02, subsurf=0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    o = active()
    o.scale = size
    return finish(o, m, smooth=subsurf > 0 or bevel > 0.0, subsurf=subsurf, bevel=bevel)


def tube(points, radii, m=None, sides=16):
    """A smooth tapered tube through `points` (horn, finger, ear...)."""
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(points):
        p = Vector(p)
        a = Vector(points[max(i - 1, 0)])
        b = Vector(points[min(i + 1, len(points) - 1)])
        t = (b - a).normalized()
        n = t.orthogonal().normalized()
        bn = t.cross(n)
        ring = []
        for k in range(sides):
            ang = 2 * math.pi * k / sides
            ring.append(bm.verts.new(p + (n * math.cos(ang) + bn * math.sin(ang)) * radii[i]))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(sides):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides], rings[i + 1][k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    me = bpy.data.meshes.new("tube")
    bm.to_mesh(me)
    o = bpy.data.objects.new("tube", me)
    bpy.context.collection.objects.link(o)
    return finish(o, m)


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = active()
    o.name = name
    o.data.name = name
    return o


def arc(center, radius, a0, a1, z, n=12):
    return [(center[0] + math.cos(a0 + (a1 - a0) * i / (n - 1)) * radius, center[1],
             z + math.sin(a0 + (a1 - a0) * i / (n - 1)) * radius) for i in range(n)]


# ------------------------------------------------------------------------------------------------- gloves

def glove_mitt():
    body = mat("BodyDark")
    palm = sphere(0.155, scale=(1.0, 1.12, 0.86), m=body)
    knuckles = sphere(0.1, loc=(0, 0.07, 0.035), scale=(1.35, 0.9, 0.85), m=body)
    thumb = tube([(-0.12, -0.02, -0.02), (-0.15, 0.05, 0.0), (-0.1, 0.11, 0.02)], [0.05, 0.048, 0.04], body)
    cuff = torus(0.105, 0.04, loc=(0, -0.15, 0), rot=(math.pi / 2, 0, 0), m=mat("Accent"))
    return join([palm, knuckles, thumb, cuff], "glove_mitt")


def glove_boxing():
    red = mat("BoxingRed", "d4202a", 0.22)
    white = mat("White", "f6f2ea", 0.5)
    fist = sphere(0.175, loc=(0, 0.02, 0.0), scale=(1.0, 1.15, 0.95), m=red)
    roll = sphere(0.13, loc=(0, 0.1, 0.07), scale=(1.25, 0.8, 0.75), m=red)  # the padded knuckle roll
    thumb = tube([(-0.15, -0.04, 0.0), (-0.18, 0.05, 0.03), (-0.12, 0.13, 0.06)], [0.06, 0.058, 0.045], red)
    cuff = cone(0.12, 0.13, 0.13, loc=(0, -0.2, 0), rot=(math.pi / 2, 0, 0), m=white, bevel=0.02)
    band = torus(0.128, 0.018, loc=(0, -0.145, 0), rot=(math.pi / 2, 0, 0), m=red)
    lace = [box((0.012, 0.012, 0.09), loc=(0.0, -0.19 + i * 0.03, 0.125), rot=(0, 0.5 * (1 if i % 2 else -1), 0),
                m=mat("Lace", "1d2340", 0.6), bevel=0.0) for i in range(3)]
    return join([fist, roll, thumb, cuff, band] + lace, "glove_boxing")


def glove_cartoon():
    white = mat("White", "f6f2ea", 0.5)
    palm = sphere(0.13, scale=(1.05, 1.0, 0.85), m=white)
    parts = [palm]
    for i, x in enumerate([-0.065, 0.0, 0.065]):  # three chunky curled fingers
        parts.append(tube([(x, 0.06, 0.06), (x, 0.15, 0.04), (x, 0.16, -0.04), (x, 0.09, -0.07)],
                          [0.045, 0.047, 0.045, 0.04], white))
    parts.append(tube([(-0.11, 0.0, 0.0), (-0.16, 0.07, 0.02), (-0.12, 0.13, 0.03)], [0.045, 0.043, 0.035], white))
    parts.append(torus(0.1, 0.045, loc=(0, -0.13, 0), rot=(math.pi / 2, 0, 0), m=white))  # rolled cuff
    for k in range(3):  # the three stitched lines on the back
        parts.append(box((0.008, 0.07, 0.006), loc=(-0.035 + k * 0.035, -0.02, 0.108), m=mat("Lace", "1d2340"), bevel=0.0))
    return join(parts, "glove_cartoon")


# ------------------------------------------------------------------------------------------------- shoes

def shoe_bowling():
    a = mat("ShoeA")
    b = mat("ShoeB")
    sole = mat("Sole", "f4f1ea", 0.7)
    s = box((0.25, 0.42, 0.05), loc=(0, 0.01, -0.07), m=sole, bevel=0.022, subsurf=1)
    upper = sphere(0.15, loc=(0, -0.02, -0.02), scale=(0.82, 1.38, 0.62), m=a)
    toe = sphere(0.11, loc=(0, 0.11, -0.04), scale=(1.05, 1.05, 0.62), m=b)
    heel = sphere(0.1, loc=(0, -0.13, -0.02), scale=(1.15, 0.8, 0.75), m=b)
    tongue = sphere(0.07, loc=(0, 0.04, 0.045), scale=(0.9, 1.3, 0.35), m=a)
    laces = [box((0.1, 0.012, 0.01), loc=(0, 0.0 + i * 0.035, 0.056 - i * 0.004), m=mat("White", "f6f2ea"), bevel=0.0)
             for i in range(3)]
    return join([s, upper, toe, heel, tongue] + laces, "shoe_bowling")


# ------------------------------------------------------------------------------------------------- hats

def hat_cap():
    acc = mat("Accent")
    dark = mat("AccentDark")
    crown = sphere(0.39, loc=(0, 0, 0.53), scale=(1.03, 1.06, 0.92), m=acc, seg=48, rings=24)
    bpy.ops.object.mode_set(mode="EDIT")  # keep the top half: a dome
    bpy.ops.object.mode_set(mode="OBJECT")
    bm = bmesh.new()
    bm.from_mesh(crown.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < 0.53 - 0.02], context="VERTS")
    bm.to_mesh(crown.data)
    bm.free()
    button = sphere(0.035, loc=(0, 0, 0.53 + 0.36), scale=(1, 1, 0.6), m=acc)
    # A curved brim reaching forward, built as a bent, bevelled slab.
    brim = box((0.42, 0.3, 0.025), loc=(0, 0.38, 0.555), m=dark, bevel=0.012)
    bm = bmesh.new()
    bm.from_mesh(brim.data)
    for v in bm.verts:
        v.co.z -= (v.co.x ** 2) * 0.55 + max(v.co.y - 0.3, 0.0) * 0.25  # droop at the sides and the tip
        w = 1.0 - max(v.co.y - 0.25, 0.0) * 1.6  # round the front off
        v.co.x *= max(w, 0.55)
    bm.to_mesh(brim.data)
    bm.free()
    band = torus(0.395, 0.022, loc=(0, 0, 0.535), scale=(1.03, 1.06, 1), m=dark)
    seams = [box((0.01, 0.01, 0.36), loc=(math.sin(a) * 0.2, math.cos(a) * 0.2, 0.74), rot=(math.cos(a) * 0.98, -math.sin(a) * 0.98, 0),
                 m=dark, bevel=0.0) for a in [i * math.pi / 3 + math.pi / 6 for i in range(6)]]
    return join([crown, button, brim, band] + seams, "hat_cap")


def hat_beanie():
    acc = mat("Accent")
    crown = sphere(0.4, loc=(0, 0, 0.5), scale=(1.04, 1.04, 1.12), m=acc, seg=48, rings=24)
    bm = bmesh.new()
    bm.from_mesh(crown.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < 0.52], context="VERTS")
    for v in bm.verts:  # knit ribs running up the dome
        ang = math.atan2(v.co.y, v.co.x)
        r = Vector((v.co.x, v.co.y)).length
        k = 1.0 + 0.025 * math.cos(ang * 24) * min(r / 0.3, 1.0)
        v.co.x *= k
        v.co.y *= k
    bm.to_mesh(crown.data)
    bm.free()
    cuff = cone(0.425, 0.425, 0.14, loc=(0, 0, 0.6), m=mat("AccentDark"), verts=64, bevel=0.03)
    pom = sphere(0.11, loc=(0, 0, 0.98), m=mat("Pom", "f6f2ea", 0.9), seg=24, rings=12)
    bm = bmesh.new()
    bm.from_mesh(pom.data)
    for v in bm.verts:  # fluffy
        n = v.co.normalized()
        v.co += n * 0.02 * math.sin(n.x * 23.0) * math.sin(n.y * 19.0) * math.sin(n.z * 17.0)
    bm.to_mesh(pom.data)
    bm.free()
    return join([crown, cuff, pom], "hat_beanie")


def hat_tophat():
    black = mat("Silk", "1a1724", 0.3)
    brim = cone(0.42, 0.42, 0.03, loc=(0, 0, 0.7), m=black, verts=64, bevel=0.012)
    curl = torus(0.41, 0.025, loc=(0, 0, 0.715), m=black, seg=64)
    crown = cone(0.25, 0.27, 0.48, loc=(0, 0, 0.96), m=black, verts=64, bevel=0.02)
    band = cone(0.258, 0.262, 0.08, loc=(0, 0, 0.77), m=mat("Accent"), verts=64, bevel=0.01)
    return join([brim, curl, crown, band], "hat_tophat")


def hat_cowboy():
    leather = mat("Leather", "8a5a32", 0.6)
    brim = cone(0.6, 0.6, 0.03, loc=(0, 0, 0.68), m=leather, verts=72, bevel=0.012)
    bm = bmesh.new()
    bm.from_mesh(brim.data)
    for v in bm.verts:  # sides curl up, front and back dip
        x, y = v.co.x, v.co.y
        v.co.z += (x * x) * 1.1 - (y * y) * 0.25
        v.co.y *= 0.82
    bm.to_mesh(brim.data)
    bm.free()
    crown = sphere(0.29, loc=(0, -0.01, 0.84), scale=(1.0, 1.15, 0.85), m=leather, seg=48, rings=24)
    bm = bmesh.new()
    bm.from_mesh(crown.data)
    for v in bm.verts:  # the pinched top: a crease along the middle and two dents in front
        if v.co.z > 0.84:
            v.co.z -= 0.09 * math.exp(-(v.co.x / 0.07) ** 2) * (v.co.z - 0.84) / 0.25
        if v.co.y > 0.15 and v.co.z > 0.9:
            v.co.x *= 0.85
    bm.to_mesh(crown.data)
    bm.free()
    band = torus(0.27, 0.025, loc=(0, -0.01, 0.73), scale=(1.0, 1.15, 1.0), m=mat("AccentDark"))
    return join([brim, crown, band], "hat_cowboy")


def hat_crown():
    gold = mat("Gold", "ffcc33", 0.2, 0.6)
    gem = mat("Ruby", "e01e45", 0.1)
    ring = cone(0.28, 0.28, 0.17, loc=(0, 0, 0.77), m=gold, verts=64, bevel=0.015)
    parts = [ring, torus(0.282, 0.02, loc=(0, 0, 0.69), m=gold), torus(0.282, 0.02, loc=(0, 0, 0.85), m=gold)]
    for i in range(6):
        a = i * math.pi / 3
        p = (math.sin(a) * 0.27, math.cos(a) * 0.27)
        parts.append(cone(0.07, 0.0, 0.18, loc=(p[0], p[1], 0.94), m=gold, verts=4, smooth=False, bevel=0.01))
        parts.append(sphere(0.028, loc=(p[0] * 1.02, p[1] * 1.02, 1.03), m=gold))
        if i % 2 == 0:
            parts.append(sphere(0.04, loc=(p[0] * 1.06, p[1] * 1.06, 0.77), scale=(1, 1, 1.2), m=gem))
    return join(parts, "hat_crown")


def dome(r, z, scale=(1, 1, 1), m=None, cut=0.0):
    """The top of a sphere: everything above z + cut."""
    o = sphere(r, loc=(0, 0, z), scale=scale, m=m, seg=48, rings=24)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < z + cut - 1e-4], context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    return o


def hat_viking():
    metal = mat("Steel", "a7adba", 0.3, 0.7)
    bone = mat("Horn", "f3e7c9", 0.5)
    helm = dome(0.4, 0.5, scale=(1.06, 1.06, 0.95), m=metal, cut=0.02)
    rim = torus(0.418, 0.035, loc=(0, 0, 0.53), scale=(1.03, 1.03, 1), m=mat("Bronze", "b98a3e", 0.35, 0.6))
    ridge = torus(0.39, 0.025, loc=(0, 0, 0.53), rot=(0, math.pi / 2, 0), scale=(1.0, 1.0, 0.98), m=mat("Bronze", "b98a3e", 0.35, 0.6))
    parts = [helm, rim, ridge]
    for i in range(10):  # rivets around the rim
        a = i * math.pi / 5 + math.pi / 10
        parts.append(sphere(0.022, loc=(math.sin(a) * 0.43, math.cos(a) * 0.43, 0.53), m=mat("Bronze", "b98a3e", 0.35, 0.6)))
    for s in (-1, 1):  # curved horns sweeping up and out
        pts = [(s * (0.33 + 0.12 * t), -0.02, 0.72 + 0.1 * math.sin(t * 2.2) + 0.32 * t * t) for t in [i / 6 for i in range(7)]]
        parts.append(tube(pts, [0.075 * (1 - i / 7.0) + 0.006 for i in range(7)], bone))
    return join(parts, "hat_viking")


def hat_afro():
    hair = mat("AccentDark")
    puffs = []
    import random
    rnd = random.Random(7)
    for i in range(46):  # a cloud of curls over the top and back of the head
        u = rnd.uniform(0, 2 * math.pi)
        v = rnd.uniform(-0.25, 1.0)
        r = 0.43 + rnd.uniform(-0.02, 0.05)
        x = math.cos(u) * math.cos(v * 1.3) * r
        y = math.sin(u) * math.cos(v * 1.3) * r * 0.95 - 0.03
        z = 0.72 + math.sin(v * 1.3) * r * 0.9
        if y > 0.25 and z < 0.75:
            continue  # leave the face clear
        puffs.append(sphere(0.13 + rnd.uniform(-0.02, 0.03), loc=(x, y, z), m=hair, seg=16, rings=8))
    o = join(puffs, "hat_afro")
    rem = o.modifiers.new("remesh", "REMESH")  # melt the curls into one fluffy shape
    rem.mode = "VOXEL"
    rem.voxel_size = 0.03
    return finish(o, hair, subsurf=1, decimate=0.18)


def hat_mohawk():
    acc = mat("Accent")
    parts = []
    for i in range(5):  # bold blades fanning from front to back
        y = 0.2 - i * 0.11
        h = 0.42 - abs(i - 1.6) * 0.05
        parts.append(cone(0.11, 0.0, h, loc=(0, y, 0.7 + h * 0.5 - abs(i - 2.0) * 0.03), rot=(-0.35 + i * 0.16, 0, 0),
                          m=acc, verts=24))
    for p in parts:
        bm = bmesh.new()
        bm.from_mesh(p.data)
        for v in bm.verts:
            v.co.x *= 0.38  # flat blades, side to side
        bm.to_mesh(p.data)
        bm.free()
    return finish(join(parts, "hat_mohawk"), subsurf=1)


def hat_propeller():
    stripes = []
    for k in range(4):  # a four-colour beanie dome
        o = dome(0.39, 0.53, scale=(1.03, 1.03, 0.95), m=mat(["Accent", "PropYellow", "AccentDark", "PropBlue"][k] if k else "Accent", ["ffffff", "ffd23f", "ffffff", "2f6bff"][k]), cut=0.02)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if not (k * math.pi / 2 <= (math.atan2(f.calc_center_median().y, f.calc_center_median().x) % (2 * math.pi)) < (k + 1) * math.pi / 2)], context="FACES")
        bm.to_mesh(o.data)
        bm.free()
        stripes.append(o)
    stem = cone(0.02, 0.02, 0.14, loc=(0, 0, 0.97), m=mat("Steel", "a7adba", 0.3, 0.7))
    cap = join(stripes + [stem], "hat_propeller")
    hub = sphere(0.035, loc=(0, 0, 0.0), m=mat("Steel", "a7adba", 0.3, 0.7))
    blades = [hub]
    for s in (-1, 1):
        b = sphere(0.12, loc=(s * 0.15, 0, 0), scale=(1.5, 0.45, 0.12), rot=(s * 0.35, 0, 0), m=mat("PropRed", "e8323c", 0.3))
        blades.append(b)
    join(blades, "hat_propeller_blades")  # spun by the game, origin at the hub
    return cap


def hat_party():
    parts = []
    parts.append(cone(0.22, 0.012, 0.5, loc=(0, 0, 0.95), m=mat("Accent"), verts=48))
    for k in range(9):  # polka dots
        z = 0.75 + (k % 3) * 0.13 + 0.03
        r = 0.22 * (1.2 - (z - 0.7) / 0.5) * 0.93  # sunk into the cone
        a = k * 2.4
        parts.append(sphere(0.03, loc=(math.cos(a) * r, math.sin(a) * r, z), scale=(1, 1, 0.6), m=mat("PartyWhite", "f6f2ea", 0.5), seg=12, rings=6))
    parts.append(sphere(0.06, loc=(0, 0, 1.22), m=mat("PartyWhite", "f6f2ea", 0.5), seg=16, rings=8))
    o = join(parts, "hat_party")
    o.rotation_euler = (0.15, -0.2, 0)  # jaunty
    return finish(o)


def hat_headband():
    # Hugs the head just above the brows (the body is about 0.32 across there).
    band = torus(0.322, 0.042, loc=(0, 0, 0.6), scale=(1.0, 1.0, 1.35), m=mat("Accent"), seg=64)
    knot = sphere(0.06, loc=(0, -0.35, 0.6), scale=(1.2, 0.8, 0.9), m=mat("Accent"))
    tails = [tube([(s * 0.03, -0.36, 0.59), (s * 0.09, -0.45, 0.52), (s * 0.13, -0.5, 0.43)], [0.03, 0.028, 0.02], mat("Accent")) for s in (-1, 1)]
    return join([band, knot] + tails, "hat_headband")


def hat_chef():
    white = mat("Chef", "fbfaf6", 0.75)
    band = cone(0.31, 0.31, 0.2, loc=(0, 0, 0.73), m=white, verts=64, bevel=0.03)
    puffs = [sphere(0.18, loc=(math.cos(a) * 0.17, math.sin(a) * 0.17, 0.95), m=white, seg=24, rings=12) for a in [i * 2 * math.pi / 5 for i in range(5)]]
    puffs.append(sphere(0.21, loc=(0, 0, 1.02), m=white, seg=24, rings=12))
    top = join(puffs, "chef_top")
    rem = top.modifiers.new("remesh", "REMESH")
    rem.mode = "VOXEL"
    rem.voxel_size = 0.025
    top = finish(top, white, subsurf=1, decimate=0.3)
    return join([band, top], "hat_chef")


def hat_bunny():
    fur = mat("Fur", "fbfaf6", 0.8)
    pink = mat("EarPink", "ff9ec4", 0.6)
    parts = []
    for s in (-1, 1):
        pts = [(s * 0.15, 0.02, 0.62), (s * 0.19, 0.0, 0.85), (s * 0.22, -0.04, 1.05), (s * 0.24, -0.1, 1.18)]
        ear = tube(pts, [0.075, 0.095, 0.085, 0.03], fur)
        bm = bmesh.new()
        bm.from_mesh(ear.data)
        for v in bm.verts:
            v.co.y = 0.0 + (v.co.y - 0.0) * 0.45 - 0.02  # flatten front to back
        bm.to_mesh(ear.data)
        bm.free()
        inner = tube([(p[0] * 1.0, 0.03, p[2]) for p in pts], [0.04, 0.06, 0.055, 0.015], pink)
        bm = bmesh.new()
        bm.from_mesh(inner.data)
        for v in bm.verts:
            v.co.y = 0.035 + (v.co.y - 0.03) * 0.2
        bm.to_mesh(inner.data)
        bm.free()
        parts += [ear, inner]
    return finish(join(parts, "hat_bunny"), subsurf=2)


def hat_wizard():
    robe = mat("WizardBlue", "3b2a9a", 0.55)
    brim = cone(0.48, 0.48, 0.03, loc=(0, 0, 0.68), m=robe, verts=64, bevel=0.012)
    pts = [(0, 0, 0.68), (0, 0.0, 0.85), (0, -0.03, 1.02), (0, -0.12, 1.17), (0, -0.26, 1.24)]
    tip = tube(pts, [0.3, 0.22, 0.14, 0.07, 0.015], robe, sides=32)
    band = torus(0.29, 0.025, loc=(0, 0, 0.72), m=mat("WizardGold", "ffd23f", 0.3, 0.3))
    stars = []
    for p in [(0.16, 0.23, 0.86), (-0.12, 0.2, 1.0), (0.05, 0.16, 1.08)]:
        st = cone(0.05, 0.05, 0.015, loc=p, rot=(math.pi / 2 - 0.4, 0, 0), m=mat("WizardGold", "ffd23f", 0.3, 0.3), verts=5, smooth=False)
        stars.append(st)
    return join([brim, tip, band] + stars, "hat_wizard")


def hat_dunce():
    white = mat("Dunce", "fbfaf6", 0.6)
    tip = cone(0.27, 0.01, 0.9, loc=(0, 0, 1.12), m=white, verts=48)
    band = cone(0.272, 0.255, 0.07, loc=(0, 0, 0.71), m=mat("DunceRed", "e8323c", 0.5), verts=48)
    return join([tip, band], "hat_dunce")


BUILDERS = [glove_mitt, glove_boxing, glove_cartoon, shoe_bowling, hat_cap, hat_beanie, hat_tophat, hat_cowboy, hat_crown,
            hat_viking, hat_afro, hat_mohawk, hat_propeller, hat_party, hat_headband, hat_chef, hat_bunny, hat_wizard, hat_dunce]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    built = []
    for make in BUILDERS:
        o = make()
        o.location = (0, 0, 0)
        o.hide_set(False)
        built.append(o)
        print("BUILT", o.name, len(o.data.polygons), "faces")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("EXPORTED", OUT)


main()
