"""Genera los personajes chibi anime de MinSee en Blender headless.

    blender -b -P Tools/generar_personajes.py -- [id ...]

Sin argumentos genera todos. Exporta a scenes/world/3d/chars/<id>.glb con
rig humanoide y las acciones "idle" y "walk".

Dos cosas que condicionan todo el modelado:

1. El personaje se construye mirando a +Y de Blender. El exportador glTF
   convierte (x, y, z) -> (x, z, -y), así que +Y acaba siendo -Z en Godot,
   que es su "adelante". Mirando a -Y saldría de espaldas.

2. Las mallas van con sombreado suave SIEMPRE. El contorno del shader toon
   es por casco invertido: infla la malla a lo largo de la normal. Con
   normales partidas el contorno se abre por cada arista dura.
"""

import bmesh
import bpy
import math
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
OUT_DIR = PROJECT / "scenes" / "world" / "3d" / "chars"

# Proporción chibi: la cabeza se come casi un tercio de la altura.
HEIGHT = 1.32
HEAD_R = 0.255
HEAD_Z = 1.035
NECK_Z = 0.80
TORSO_TOP = 0.785
TORSO_BOT = 0.47
HIP_Z = 0.455
SHOULDER_Z = 0.735
FOOT_Z = 0.035

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chars_spec import CHARS  # noqa: E402

FACES_DIR = OUT_DIR / "faces"


# ---------------------------------------------------------------- utilidades


def ensure_object_mode():
    """mode_set revienta sin objeto activo, y tras wipe() no hay ninguno."""
    if bpy.context.view_layer.objects.active is not None:
        bpy.ops.object.mode_set(mode="OBJECT")


def wipe():
    ensure_object_mode()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.armatures, bpy.data.actions):
        for item in list(block):
            block.remove(item)


def material(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    # Roughness alta y metallic a cero: el .glb no lleva el toon, lo pone
    # Godot encima. Esto solo es el color base que toonify lee.
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def face_material(name, image_path):
    """Material de la cara: el dibujo va en la textura, no en la geometría."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(image_path))
    tex.interpolation = "Linear"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def spherical_uv(obj, radii):
    """UV equirectangular impuesta a mano, no la que trae la primitiva.

        u = 0.5 + atan2(x, y) / 2pi   ->  el frente (+Y) cae en u = 0.5
        v = 0.5 + asin(nz) / pi       ->  la coronilla en v = 1

    Fijarla aquí es lo que permite a generar_caras.py pintar a ciegas: sabe
    exactamente dónde va a caer cada píxel.
    """
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uvs = me.uv_layers.active.data
    for poly in me.polygons:
        vals = []
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            nx, ny, nz = co.x / radii[0], co.y / radii[1], co.z / radii[2]
            length = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
            nx, ny, nz = nx / length, ny / length, nz / length
            u = 0.5 + math.atan2(nx, ny) / (2.0 * math.pi)
            v = 0.5 + math.asin(max(-1.0, min(1.0, nz))) / math.pi
            vals.append([li, u, v])
        # Costura: un polígono que cruza u=0/1 se estiraría por toda la
        # textura. Se desplazan sus u bajos al otro lado.
        us = [x[1] for x in vals]
        if max(us) - min(us) > 0.5:
            for x in vals:
                if x[1] < 0.5:
                    x[1] += 1.0
        for li, u, v in vals:
            uvs[li].uv = (u, v)


def cut_below(obj, plane_z, slope_y):
    """Corta la malla por un plano inclinado y tira lo de abajo.

    Sirve para el nacimiento del pelo: alto por delante (deja la frente y las
    cejas al aire) y bajo por detrás (tapa la nuca).
    """
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.bisect_plane(
        bm,
        geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
        plane_co=(0.0, 0.0, plane_z),
        plane_no=(0.0, -slope_y, 1.0),
        clear_inner=True,
    )
    bm.to_mesh(me)
    bm.free()
    me.update()


def finish(obj, mat):
    obj.data.materials.append(mat)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.ops.object.shade_smooth()
    return obj


def sphere(name, loc, scale, mat, segments=20, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1.0, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    return finish(obj, mat)


def capsule(name, loc, radius, height, mat, rot=(0, 0, 0), verts=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=height, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    return finish(obj, mat)


def box(name, loc, scale, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    return finish(obj, mat)


def cone(name, loc, r1, r2, depth, mat, rot=(0, 0, 0), verts=16):
    bpy.ops.mesh.primitive_cone_add(
        vertices=verts, radius1=r1, radius2=r2, depth=depth, location=loc, rotation=rot
    )
    obj = bpy.context.active_object
    obj.name = name
    return finish(obj, mat)


# ------------------------------------------------------------------- modelado


def build_mesh(char_id, spec):
    mats = {k: material(k, spec[k]) for k in ("skin", "hair", "shirt", "trim", "pants", "boots")}
    face_png = FACES_DIR / f"{char_id}.png"
    if not face_png.exists():
        raise SystemExit(f"Falta {face_png}. Lanza antes: python3 Tools/generar_caras.py")
    mats["face"] = face_material("face", face_png)
    parts = []

    # Cabeza. Los ojos NO son geometría: van pintados en la textura. Unos ojos
    # modelados sobresalen menos que el casco del contorno y se los traga.
    head_radii = (HEAD_R, HEAD_R * 0.92, HEAD_R * 0.98)
    head = sphere("head", (0, 0, HEAD_Z), head_radii, mats["face"], 32, 22)
    spherical_uv(head, head_radii)
    parts.append(head)

    # Pelo: la propia cabeza inflada y recortada por un plano inclinado. Así
    # el nacimiento queda limpio y por delante no pisa las cejas.
    cap = sphere("hair_cap", (0, -0.012, HEAD_Z + 0.012), (HEAD_R * 1.10, HEAD_R * 1.04, HEAD_R * 1.10), mats["hair"], 32, 22)
    cut_below(cap, plane_z=0.0, slope_y=0.88)
    parts.append(cap)

    # Mechones del flequillo, colgando del nacimiento hacia la frente.
    for i, t in enumerate((-1.0, -0.55, 0.0, 0.55, 1.0)):
        ang = t * math.radians(56)
        # Radio mayor que el del casquete: si no, el mechón queda dentro y no
        # se ve nada por fuera.
        px = math.sin(ang) * 0.200
        py = math.cos(ang) * 0.185
        parts.append(
            sphere(
                f"lock.{i}",
                (px, py, HEAD_Z + 0.175 - abs(t) * 0.016),
                (0.075, 0.058, 0.075),
                mats["hair"],
                16,
                12,
            )
        )

    if spec["hair_style"] == "long":
        parts.append(sphere("hair_back", (0, -0.15, HEAD_Z - 0.12), (0.205, 0.135, 0.265), mats["hair"], 22, 14))
        for side, sx in (("L", 0.215), ("R", -0.215)):
            parts.append(capsule(f"tail.{side}", (sx, -0.05, HEAD_Z - 0.14), 0.053, 0.31, mats["hair"], verts=10))

    # Cuello
    parts.append(capsule("neck", (0, 0, NECK_Z), 0.058, 0.09, mats["skin"], verts=12))

    # Torso: cono truncado, hombros más anchos que cintura.
    parts.append(
        cone("torso", (0, 0, (TORSO_TOP + TORSO_BOT) / 2.0), 0.155, 0.125, TORSO_TOP - TORSO_BOT, mats["shirt"], verts=20)
    )
    # Cuello de otro color: corta la silueta justo bajo la cabeza, que es
    # donde más se lee. De peto en mitad del pecho parecía un babero.
    parts.append(sphere("collar", (0, 0, 0.775), (0.125, 0.115, 0.042), mats["trim"], 18, 10))
    # Cadera
    parts.append(sphere("hips", (0, 0, HIP_Z), (0.135, 0.105, 0.085), mats["pants"], 18, 10))

    # Brazos: hombro, brazo, antebrazo y mano.
    for side, sx in (("L", 1.0), ("R", -1.0)):
        parts.append(sphere(f"shoulder.{side}", (sx * 0.145, 0, SHOULDER_Z), (0.062, 0.062, 0.058), mats["shirt"], 14, 10))
        parts.append(
            capsule(f"upperarm.{side}", (sx * 0.172, 0, 0.655), 0.047, 0.17, mats["shirt"], rot=(0, math.radians(sx * 7), 0), verts=12)
        )
        parts.append(
            capsule(f"forearm.{side}", (sx * 0.192, 0, 0.515), 0.041, 0.15, mats["shirt"], rot=(0, math.radians(sx * 5), 0), verts=12)
        )
        parts.append(sphere(f"hand.{side}", (sx * 0.203, 0, 0.428), (0.048, 0.040, 0.050), mats["skin"], 14, 10))

    # Piernas: muslo, pantorrilla y bota.
    for side, sx in (("L", 1.0), ("R", -1.0)):
        parts.append(capsule(f"thigh.{side}", (sx * 0.072, 0, 0.345), 0.062, 0.21, mats["pants"], verts=12))
        parts.append(capsule(f"shin.{side}", (sx * 0.072, 0, 0.165), 0.051, 0.19, mats["pants"], verts=12))
        parts.append(box(f"boot.{side}", (sx * 0.072, 0.028, FOOT_Z), (0.105, 0.155, 0.07), mats["boots"]))

    # Unir en una sola malla: así Godot recibe un MeshInstance3D con una
    # superficie por material, y el skinning es uno solo en vez de 30.
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    # La cabeza manda: el join conserva las UV del objeto activo como base.
    bpy.context.view_layer.objects.active = head
    bpy.ops.object.join()
    body = bpy.context.active_object
    body.name = "Body"
    # El join deja los datos de malla con el nombre del primer trozo ("Sphere").
    body.data.name = "Body"
    return body


# ----------------------------------------------------------------------- rig

BONES = [
    # nombre,          cabeza,                   cola,                     padre
    ("hips",           (0, 0, HIP_Z),            (0, 0, 0.56),             None),
    ("spine",          (0, 0, 0.56),             (0, 0, 0.70),             "hips"),
    ("chest",          (0, 0, 0.70),             (0, 0, NECK_Z),           "spine"),
    ("neck",           (0, 0, NECK_Z),           (0, 0, 0.855),            "chest"),
    ("head",           (0, 0, 0.855),            (0, 0, HEAD_Z + HEAD_R),  "neck"),
    ("shoulder.L",     (0.045, 0, SHOULDER_Z),   (0.145, 0, SHOULDER_Z),   "chest"),
    ("upperarm.L",     (0.145, 0, SHOULDER_Z),   (0.185, 0, 0.575),        "shoulder.L"),
    ("forearm.L",      (0.185, 0, 0.575),        (0.203, 0, 0.452),        "upperarm.L"),
    ("hand.L",         (0.203, 0, 0.452),        (0.203, 0, 0.395),        "forearm.L"),
    ("shoulder.R",     (-0.045, 0, SHOULDER_Z),  (-0.145, 0, SHOULDER_Z),  "chest"),
    ("upperarm.R",     (-0.145, 0, SHOULDER_Z),  (-0.185, 0, 0.575),       "shoulder.R"),
    ("forearm.R",      (-0.185, 0, 0.575),       (-0.203, 0, 0.452),       "upperarm.R"),
    ("hand.R",         (-0.203, 0, 0.452),       (-0.203, 0, 0.395),       "forearm.R"),
    ("thigh.L",        (0.072, 0, HIP_Z),        (0.072, 0, 0.245),        "hips"),
    ("shin.L",         (0.072, 0, 0.245),        (0.072, 0, 0.072),        "thigh.L"),
    ("foot.L",         (0.072, 0, 0.072),        (0.072, 0.11, 0.03),      "shin.L"),
    ("thigh.R",        (-0.072, 0, HIP_Z),       (-0.072, 0, 0.245),       "hips"),
    ("shin.R",         (-0.072, 0, 0.245),       (-0.072, 0, 0.072),       "thigh.R"),
    ("foot.R",         (-0.072, 0, 0.072),       (-0.072, 0.11, 0.03),     "shin.R"),
]


def build_armature():
    data = bpy.data.armatures.new("Skeleton")
    obj = bpy.data.objects.new("Skeleton", data)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    created = {}
    for name, head, tail, parent in BONES:
        b = data.edit_bones.new(name)
        b.head = head
        b.tail = tail
        if parent:
            b.parent = created[parent]
            b.use_connect = False
        created[name] = b
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def bind(body, skel):
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    skel.select_set(True)
    bpy.context.view_layer.objects.active = skel
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")


# ------------------------------------------------------------------ animación


def new_action(skel, name):
    """Crea una acción y la deja activa.

    Blender 4.4 metió las "slotted actions": una acción sin slot no recibe
    curvas. keyframe_insert crea el slot solo, pero si la API lo expone se
    fuerza aquí para no depender de ese detalle.
    """
    if skel.animation_data is None:
        skel.animation_data_create()
    act = bpy.data.actions.new(name)
    skel.animation_data.action = act
    slots = getattr(act, "slots", None)
    if slots is not None and len(slots) == 0:
        try:
            slot = slots.new(id_type="OBJECT", name=skel.name)
            skel.animation_data.action_slot = slot
        except Exception:
            pass
    return act


def key(skel, bone, frame, rot=None, loc=None):
    pb = skel.pose.bones[bone]
    pb.rotation_mode = "XYZ"
    if rot is not None:
        pb.rotation_euler = [math.radians(a) for a in rot]
        pb.keyframe_insert("rotation_euler", frame=frame)
    if loc is not None:
        pb.location = loc
        pb.keyframe_insert("location", frame=frame)


def anim_idle(skel):
    """Respiración: el pecho sube, los hombros caen un poco, la cabeza acompaña."""
    act = new_action(skel, "idle")
    for f, amp in ((1, 0.0), (24, 1.0), (48, 0.0)):
        key(skel, "spine", f, rot=(-1.6 * amp, 0, 0))
        key(skel, "chest", f, rot=(-1.2 * amp, 0, 0))
        key(skel, "head", f, rot=(1.4 * amp, 0, 0))
        key(skel, "hips", f, loc=(0, 0, 0.012 * amp))
        key(skel, "upperarm.L", f, rot=(0, 0, -3.5 * amp))
        key(skel, "upperarm.R", f, rot=(0, 0, 3.5 * amp))
    act.use_cyclic = True
    return act


def anim_walk(skel):
    """Paso de 24 fotogramas: piernas alternas y brazos en contra."""
    act = new_action(skel, "walk")
    swing = 26.0
    knee = 20.0
    for phase, f in ((0, 1), (1, 7), (2, 13), (3, 19), (0, 25)):
        s = (1, 0, -1, 0)[phase]
        key(skel, "thigh.L", f, rot=(swing * s, 0, 0))
        key(skel, "thigh.R", f, rot=(-swing * s, 0, 0))
        key(skel, "shin.L", f, rot=(-knee * max(-s, 0) - 6, 0, 0))
        key(skel, "shin.R", f, rot=(-knee * max(s, 0) - 6, 0, 0))
        key(skel, "foot.L", f, rot=(8 * s, 0, 0))
        key(skel, "foot.R", f, rot=(-8 * s, 0, 0))
        # Los brazos van al revés que las piernas; sin esto parece un muñeco.
        key(skel, "upperarm.L", f, rot=(-swing * 0.7 * s, 0, 0))
        key(skel, "upperarm.R", f, rot=(swing * 0.7 * s, 0, 0))
        key(skel, "forearm.L", f, rot=(-10, 0, 0))
        key(skel, "forearm.R", f, rot=(-10, 0, 0))
        # Rebote vertical: dos por ciclo, no uno.
        bounce = 0.016 if phase in (1, 3) else 0.0
        key(skel, "hips", f, loc=(0, 0, bounce))
        key(skel, "spine", f, rot=(0, 0, 2.5 * s))
    act.use_cyclic = True
    return act


def stage_actions(skel, actions):
    """Cada acción a su pista NLA: así el exportador saca un clip por pista."""
    ad = skel.animation_data
    ad.action = None
    for act in actions:
        track = ad.nla_tracks.new()
        track.name = act.name
        start = int(act.frame_range[0])
        strip = track.strips.new(act.name, start, act)
        strip.name = act.name
        track.mute = False


# -------------------------------------------------------------------- export


def export(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=False,
        export_apply=False,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_bake_animation=True,
        export_optimize_animation_size=False,
        export_yup=True,
        export_skins=True,
        export_morph=False,
        export_cameras=False,
        export_lights=False,
    )


def build(char_id, spec):
    wipe()
    body = build_mesh(char_id, spec)
    skel = build_armature()
    bind(body, skel)
    bpy.ops.object.select_all(action="DESELECT")
    skel.select_set(True)
    bpy.context.view_layer.objects.active = skel
    bpy.ops.object.mode_set(mode="POSE")
    actions = [anim_idle(skel), anim_walk(skel)]
    bpy.ops.object.mode_set(mode="OBJECT")
    stage_actions(skel, actions)
    out = OUT_DIR / f"{char_id}.glb"
    export(out)
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    print(f"[ok] {char_id}: {len(body.data.polygons)} caras (~{tris} tris), "
          f"{len(body.data.materials)} materiales, {len(skel.pose.bones)} huesos -> {out.name}")


def main():
    argv = sys.argv
    wanted = argv[argv.index("--") + 1:] if "--" in argv else []
    ids = wanted or list(CHARS)
    for char_id in ids:
        if char_id not in CHARS:
            print(f"[skip] {char_id}: no está en CHARS")
            continue
        build(char_id, CHARS[char_id])


main()
