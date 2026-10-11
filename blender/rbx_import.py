"""
Rebuilds a Roblox export (from the bridge's export_to_blender tool) in Blender.

    live (blender-mcp):  exec(open("<dir>/rbx_import.py").read()); import_roblox("<dir>")
    headless:            Blender --background --python rbx_import.py -- <dir> [--save out.blend]

Only ADDS a new collection; never deletes or edits anything already in the file.

Coordinates: Blender (x, y, z) = Roblox (x, -z, y), a +90 degree turn about X
(no mirror), 1 stud = 1 Blender unit. Each part's local axes are converted the
same way, so an object's local Z is the part's up and its scale stays 1 with
the real size baked into the geometry.
"""
import json
import math
import os
import struct
import sys
from array import array

import bmesh
import bpy
from mathutils import Matrix, Vector

C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
CT = C.transposed()
NONE = 0xFFFFFFFF


def rbx_rotation(cf):
    r = cf[3:]
    return Matrix(((r[0], r[1], r[2]), (r[3], r[4], r[5]), (r[6], r[7], r[8])))


def part_matrix(cf):
    """Roblox CFrame -> Blender world matrix for an object whose geometry was built with to_b()."""
    m = (C @ rbx_rotation(cf) @ CT).to_4x4()
    m.translation = C @ Vector(cf[:3])
    return m


def camera_matrix(cf):
    """Cameras look down local -Z with +Y up in both apps, so only the world side is converted."""
    m = (C @ rbx_rotation(cf)).to_4x4()
    m.translation = C @ Vector(cf[:3])
    return m


def to_b(x, y, z):
    return (x, -z, y)


# ---------- primitive geometry, in Roblox local space (Y up) ----------

def box_geo(sx, sy, sz):
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    v = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz),
         (-hx, hy, -hz), (hx, hy, -hz), (hx, hy, hz), (-hx, hy, hz)]
    f = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    return v, f, None


def wedge_geo(sx, sy, sz):
    # full faces on the bottom and the back (+Z); the slope faces front (-Z) and up
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    v = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz), (-hx, hy, hz), (hx, hy, hz)]
    f = [(0, 1, 2, 3), (3, 2, 5, 4), (0, 4, 5, 1), (0, 3, 4), (1, 5, 2)]
    return v, f, None


def corner_wedge_geo(sx, sy, sz):
    # bottom face full, apex above the (+X, -Z) corner
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    v = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz), (hx, hy, -hz)]
    f = [(0, 1, 2, 3), (0, 4, 1), (1, 4, 2), (2, 4, 3), (3, 4, 0)]
    return v, f, None


def cylinder_geo(sx, sy, sz, ry=None, rz=None, segments=48):
    # axis along local X; a Part uses diameter min(Y, Z), a SpecialMesh stretches to Y and Z
    if ry is None:
        ry = rz = min(sy, sz) / 2
    hx = sx / 2
    v = []
    for side in (-hx, hx):
        for i in range(segments):
            a = 2 * math.pi * i / segments
            v.append((side, math.cos(a) * ry, math.sin(a) * rz))
    f = [tuple(range(segments - 1, -1, -1)), tuple(range(segments, 2 * segments))]
    sides = []
    for i in range(segments):
        j = (i + 1) % segments
        sides.append(len(f))
        f.append((i, j, segments + j, segments + i))
    return v, f, sides


def ball_geo(rx, ry, rz, rings=24, segments=48):
    v = [(0, ry, 0)]
    for r in range(1, rings):
        t = math.pi * r / rings
        for s in range(segments):
            a = 2 * math.pi * s / segments
            v.append((math.sin(t) * math.cos(a) * rx, math.cos(t) * ry, math.sin(t) * math.sin(a) * rz))
    v.append((0, -ry, 0))
    bottom = len(v) - 1
    f = []
    ring = lambda r, s: 1 + (r - 1) * segments + (s % segments)
    for s in range(segments):
        f.append((0, ring(1, s + 1), ring(1, s)))
    for r in range(1, rings - 1):
        for s in range(segments):
            f.append((ring(r, s), ring(r, s + 1), ring(r + 1, s + 1), ring(r + 1, s)))
    for s in range(segments):
        f.append((ring(rings - 1, s), ring(rings - 1, s + 1), bottom))
    return v, f, list(range(len(f)))


def build_mesh(name, verts, faces, smooth_faces=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([to_b(*p) for p in verts], [], faces)
    if smooth_faces is not None:
        smooth = set(smooth_faces)
        for i, p in enumerate(me.polygons):
            p.use_smooth = i in smooth
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.faces.ensure_lookup_table()
        for e in bm.edges:
            if len({f.smooth for f in e.link_faces}) > 1:
                e.smooth = False
        bm.to_mesh(me)
        bm.free()
    me.update()
    return me


# ---------- EditableMesh geometry ----------

def read_mesh_bin(path):
    data = open(path, "rb").read()
    nv, nuv, nn, nf = struct.unpack_from("<4I", data, 0)
    o = 16
    pos = array("f"); pos.frombytes(data[o:o + nv * 12]); o += nv * 12
    uv = array("f"); uv.frombytes(data[o:o + nuv * 8]); o += nuv * 8
    nrm = array("f"); nrm.frombytes(data[o:o + nn * 12]); o += nn * 12
    face = array("I"); face.frombytes(data[o:o + nf * 36])
    if sys.byteorder != "little":
        for a in (pos, uv, nrm, face):
            a.byteswap()
    return nv, pos, uv, nrm, nf, face


def mesh_from_bin(name, raw, size=None, scale=None, offset=(0, 0, 0)):
    """size: fit the mesh's bounds to it (MeshPart). scale: multiply native size (SpecialMesh FileMesh)."""
    nv, pos, uv, nrm, nf, face = raw
    xs, ys, zs = pos[0::3], pos[1::3], pos[2::3]
    lo = (min(xs), min(ys), min(zs)) if nv else (0, 0, 0)
    hi = (max(xs), max(ys), max(zs)) if nv else (0, 0, 0)
    centre = [(lo[k] + hi[k]) / 2 for k in range(3)]
    if size is not None:
        k = [size[i] / (hi[i] - lo[i]) if hi[i] - lo[i] > 1e-6 else 1.0 for i in range(3)]
    else:
        k = list(scale or (1, 1, 1))
        centre = [0, 0, 0]
    verts = [to_b((pos[i * 3] - centre[0]) * k[0] + offset[0],
                  (pos[i * 3 + 1] - centre[1]) * k[1] + offset[1],
                  (pos[i * 3 + 2] - centre[2]) * k[2] + offset[2]) for i in range(nv)]
    faces, uvs, normals = [], [], []
    has_uv = has_n = True
    for f in range(nf):
        b = f * 9
        tri = face[b:b + 3]
        if len(set(tri)) < 3 or NONE in tri:
            continue
        faces.append(tuple(tri))
        for c in range(3):
            ui = face[b + 3 + c]
            if ui == NONE or ui * 2 + 1 >= len(uv):
                has_uv = False
                uvs.append((0.0, 0.0))
            else:
                uvs.append((uv[ui * 2], 1.0 - uv[ui * 2 + 1]))
            ni = face[b + 6 + c]
            if ni == NONE or ni * 3 + 2 >= len(nrm):
                has_n = False
                normals.append((0.0, 0.0, 1.0))
            else:
                # normals transform with the inverse of the non-uniform scale
                n = Vector(to_b(nrm[ni * 3] / k[0], nrm[ni * 3 + 1] / k[1], nrm[ni * 3 + 2] / k[2]))
                normals.append(tuple(n.normalized()) if n.length > 1e-12 else (0.0, 0.0, 1.0))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    if has_uv and uvs:
        layer = me.uv_layers.new(name="UVMap")
        layer.data.foreach_set("uv", [c for p in uvs for c in p])
    for p in me.polygons:
        p.use_smooth = True
    if has_n and normals:
        me.normals_split_custom_set(normals)
    me.update()
    return me


# ---------- materials ----------

ROUGHNESS = {"SmoothPlastic": 0.2, "Glass": 0.05, "Ice": 0.1, "Marble": 0.25, "Neon": 0.5, "Foil": 0.15,
             "Metal": 0.35, "DiamondPlate": 0.35, "CorrodedMetal": 0.7}
METALLIC = {"Metal": 1.0, "DiamondPlate": 1.0, "CorrodedMetal": 0.8, "Foil": 1.0}


def placeholder_image():
    img = bpy.data.images.get("RBX_MissingTexture")
    if img:
        return img
    img = bpy.data.images.new("RBX_MissingTexture", 64, 64)
    px = []
    for y in range(64):
        for x in range(64):
            px += [1, 0, 1, 1] if (x // 8 + y // 8) % 2 == 0 else [0, 0, 0, 1]
    img.pixels = px
    return img


def linear(c):
    """Roblox Color3 is sRGB; Blender colour sockets are scene-linear."""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def sock(sockets, ident):
    return next(x for x in sockets if x.identifier == ident)


class Materials:
    def __init__(self, root, scene):
        self.root, self.scene, self.cache, self.images = root, scene, {}, {}
        self.missing = set()

    def image(self, tex_id):
        if tex_id in self.images:
            return self.images[tex_id]
        entry = self.scene["textures"].get(tex_id, {})
        img = None
        if entry.get("file") and os.path.exists(os.path.join(self.root, entry["file"])):
            img = bpy.data.images.load(os.path.join(self.root, entry["file"]), check_existing=True)
        else:
            self.missing.add((tex_id, entry.get("error", "not exported")))
            img = placeholder_image()
        self.images[tex_id] = img
        return img

    def get(self, node):
        surf = node.get("surface") or {}
        tex = surf.get("colorMap") or node.get("texture") or ""
        tint = surf.get("tint") if surf.get("colorMap") else None
        alpha_mode = surf.get("alphaMode", "Overlay") if surf.get("colorMap") else "Overlay"
        key = (tuple(round(c, 4) for c in node["color"]), node["material"], round(node["transparency"], 4),
               tex, alpha_mode, tuple(round(c, 4) for c in tint) if tint else None)
        if key in self.cache:
            return self.cache[key]
        hexcol = "".join(f"{round(c * 255):02X}" for c in node["color"])
        name = f"{node['material']} #{hexcol}"
        if node["transparency"] > 0:
            name += f" t{node['transparency']:.2f}"
        if tex:
            name += f" tex{tex.split('//')[-1][-6:]}"
        mat = bpy.data.materials.new(name)
        if bpy.app.version < (5, 0, 0):
            mat.use_nodes = True
        mat["rbx_material"] = node["material"]
        mat["rbx_color"] = hexcol
        nt = mat.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        colour = (*(linear(c) for c in node["color"]), 1.0)
        bsdf.inputs["Base Color"].default_value = colour
        bsdf.inputs["Roughness"].default_value = ROUGHNESS.get(node["material"], 0.5)
        bsdf.inputs["Metallic"].default_value = METALLIC.get(node["material"], 0.0)
        alpha = 1.0 - node["transparency"]
        if tex:
            img_node = nt.nodes.new("ShaderNodeTexImage")
            img_node.image = self.image(tex)
            img_node.location = (-700, 300)
            rgb = img_node.outputs["Color"]
            if tint and any(abs(c - 1) > 1e-4 for c in tint):
                mul = nt.nodes.new("ShaderNodeMix")
                mul.data_type, mul.blend_type = "RGBA", "MULTIPLY"
                sock(mul.inputs, "Factor_Float").default_value = 1.0
                nt.links.new(rgb, sock(mul.inputs, "A_Color"))
                sock(mul.inputs, "B_Color").default_value = (*(linear(c) for c in tint), 1.0)
                rgb = sock(mul.outputs, "Result_Color")
            if alpha_mode == "Transparency":
                nt.links.new(rgb, bsdf.inputs["Base Color"])
                if alpha < 1:
                    m = nt.nodes.new("ShaderNodeMath")
                    m.operation = "MULTIPLY"
                    nt.links.new(img_node.outputs["Alpha"], m.inputs[0])
                    m.inputs[1].default_value = alpha
                    nt.links.new(m.outputs[0], bsdf.inputs["Alpha"])
                else:
                    nt.links.new(img_node.outputs["Alpha"], bsdf.inputs["Alpha"])
            else:
                # Overlay: the part colour shows where the texture is transparent
                mix = nt.nodes.new("ShaderNodeMix")
                mix.data_type = "RGBA"
                nt.links.new(img_node.outputs["Alpha"], sock(mix.inputs, "Factor_Float"))
                sock(mix.inputs, "A_Color").default_value = colour
                nt.links.new(rgb, sock(mix.inputs, "B_Color"))
                nt.links.new(sock(mix.outputs, "Result_Color"), bsdf.inputs["Base Color"])
        if node["material"] == "Neon":
            bsdf.inputs["Emission Color"].default_value = colour
            bsdf.inputs["Emission Strength"].default_value = 2.0
        if node["material"] == "Glass" and alpha >= 1:
            alpha = 0.6
        if alpha < 1 and not (tex and alpha_mode == "Transparency"):
            bsdf.inputs["Alpha"].default_value = alpha
        if alpha < 1 or (tex and alpha_mode == "Transparency"):
            for attr, value in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
                try:
                    setattr(mat, attr, value)
                    break
                except (AttributeError, TypeError):
                    pass
        mat.diffuse_color = colour[:3] + (alpha,)
        self.cache[key] = mat
        return mat


def placeholder_material():
    mat = bpy.data.materials.get("RBX Placeholder")
    if mat:
        return mat
    mat = bpy.data.materials.new("RBX Placeholder")
    if bpy.app.version < (5, 0, 0):
        mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (1, 0, 1, 1)
    bsdf.inputs["Emission Color"].default_value = (1, 0, 1, 1)
    bsdf.inputs["Emission Strength"].default_value = 0.5
    mat.diffuse_color = (1, 0, 1, 1)
    return mat


# ---------- import ----------

def import_roblox(export_dir, collection_name=None, camera=True):
    export_dir = os.path.abspath(os.path.expanduser(export_dir))
    scene = json.load(open(os.path.join(export_dir, "scene.json")))
    nodes = scene["nodes"]
    col = bpy.data.collections.new(collection_name or nodes[0]["name"])
    bpy.context.scene.collection.children.link(col)
    col["rbx_source"] = f"{scene['source']['path']} @ place {scene['source']['placeId']}"

    mats = Materials(export_dir, scene)
    raws, shared = {}, {}
    objects, worlds = {}, {}
    report = {"shape": 0, "mesh": 0, "placeholder": [], "hidden": 0, "empty": 0}

    for node in nodes:
        kind = node.get("kind")
        name = node["name"]
        hidden = False
        if kind is None:
            world = part_matrix(node["pivot"]) if node.get("pivot") else Matrix.Identity(4)
            obj = bpy.data.objects.new(name, None)
            obj.empty_display_type = "PLAIN_AXES"
            obj.empty_display_size = 0.5
            report["empty"] += 1
        else:
            world = part_matrix(node["cf"])
            size = node["size"]
            special = node.get("special")
            me, mat = None, None
            if kind == "mesh":
                entry = scene["meshes"][node["mesh"]]
                if node["mesh"] not in raws:
                    raws[node["mesh"]] = read_mesh_bin(os.path.join(export_dir, entry["file"]))
                if special:
                    key = (node["mesh"], "special", tuple(special["scale"]), tuple(special["offset"]))
                    if key not in shared:
                        shared[key] = mesh_from_bin(name, raws[node["mesh"]], scale=special["scale"], offset=special["offset"])
                else:
                    key = (node["mesh"], tuple(round(s, 6) for s in size))
                    if key not in shared:
                        shared[key] = mesh_from_bin(name, raws[node["mesh"]], size=size)
                me = shared[key]
                mat = mats.get(node)
                report["mesh"] += 1
            elif kind == "shape":
                shape = node["shape"]
                sx, sy, sz = size
                off = (0, 0, 0)
                if special:
                    sc, off = special["scale"], special["offset"]
                    sx, sy, sz = sx * sc[0], sy * sc[1], sz * sc[2]
                if shape == "Block":
                    geo = box_geo(sx, sy, sz)
                elif shape == "Wedge":
                    geo = wedge_geo(sx, sy, sz)
                elif shape == "CornerWedge":
                    geo = corner_wedge_geo(sx, sy, sz)
                elif shape == "Cylinder":
                    geo = cylinder_geo(sx, sy, sz, sy / 2, sz / 2) if special else cylinder_geo(sx, sy, sz)
                else:
                    geo = ball_geo(sx / 2, sy / 2, sz / 2) if special else ball_geo(*[min(size) / 2] * 3)
                v, f, smooth = geo
                if any(off):
                    v = [(p[0] + off[0], p[1] + off[1], p[2] + off[2]) for p in v]
                me = build_mesh(name, v, f, smooth)
                mat = mats.get(node)
                report["shape"] += 1
            else:
                v, f, _ = box_geo(*size)
                me = build_mesh("[PH] " + name, v, f)
                mat = placeholder_material()
                name = "[PH] " + name
                report["placeholder"].append((node["path"], node["class"], node.get("reason", "")))
            obj = bpy.data.objects.new(name, me)
            if not me.materials:
                me.materials.append(mat)
            obj.material_slots[0].link = "OBJECT"
            obj.material_slots[0].material = mat
            if kind == "placeholder":
                obj.display_type = "WIRE"
                obj["rbx_placeholder"] = node.get("reason", "")
            for key in ("material", "transparency"):
                obj[f"rbx_{key}"] = node[key]
            obj["rbx_size"] = node["size"]
            hidden = node["transparency"] >= 1
        obj["rbx_name"] = node["name"]
        obj["rbx_class"] = node["class"]
        obj["rbx_path"] = node["path"]
        col.objects.link(obj)
        if kind is not None and hidden:
            # hidden like Alt+H, so it stays evaluated and comes back with Alt+H
            obj.hide_render = True
            obj.hide_set(True)
            report["hidden"] += 1
        parent = objects.get(node.get("parent"))
        if parent is not None:
            obj.parent = parent
            obj.matrix_basis = worlds[node["parent"]].inverted() @ world
        else:
            obj.matrix_basis = world
        objects[node["id"]], worlds[node["id"]] = obj, world

    cam_obj = None
    if camera and scene.get("camera"):
        cam = scene["camera"]
        data = bpy.data.cameras.new("Studio Camera")
        data.sensor_fit = "VERTICAL"
        data.angle_y = math.radians(cam["fov"])
        data.clip_start, data.clip_end = 0.1, 10000
        cam_obj = bpy.data.objects.new("Studio Camera", data)
        cam_obj.matrix_basis = camera_matrix(cam["cf"])
        cam_obj["rbx_viewport"] = cam["viewport"]
        col.objects.link(cam_obj)

    lines = [
        f"# Import report: {col.name}",
        "",
        f"- Collection `{col.name}` from {col['rbx_source']}",
        f"- Built {report['shape']} primitive parts, {report['mesh']} mesh parts, {report['empty']} empties, "
        f"{len(report['placeholder'])} placeholders; {report['hidden']} fully transparent parts hidden",
        "",
        "## Placeholders (wireframe, named [PH])",
    ]
    lines += [f"- `{p}` ({c}): {r}" for p, c, r in report["placeholder"]] or ["- none"]
    lines += ["", "## Textures shown as the magenta checker"]
    lines += [f"- {t}: {e}" for t, e in sorted(mats.missing)] or ["- none"]
    with open(os.path.join(export_dir, "import_report.md"), "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return {"collection": col.name, "camera": cam_obj.name if cam_obj else None, **{k: (len(v) if isinstance(v, list) else v) for k, v in report.items()}}


if __name__ == "__main__" and "--" in sys.argv:
    argv = sys.argv[sys.argv.index("--") + 1:]
    import_roblox(argv[0])
    if "--save" in argv:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(argv[argv.index("--save") + 1]))
