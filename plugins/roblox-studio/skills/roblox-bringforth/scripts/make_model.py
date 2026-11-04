#!/usr/bin/env python3
"""Builds a low-poly 3D model (.glb) from a JSON description, without Blender.

Claude uses it to make props, kit pieces and simple buildings itself: describe the model as
primitives, get a glTF 2.0 binary that bringforth.py uploads to Roblox.

Usage:
  make_model.py model.json [-o out.glb] [--preview preview.png]

Spec (all sizes and positions in studs, Y up, rotation in degrees XYZ):
  {
    "name": "Crate",
    "unitsPerStud": 1,                 # glTF units per stud (see references/pipeline.md)
    "pivot": "bottom",                 # bottom | center | origin: where the model's origin sits
    "parts": [
      {"shape": "box", "size": [4, 4, 4], "position": [0, 2, 0], "color": "#9c6b3c", "material": "wood"},
      {"shape": "cylinder", "size": [1, 6, 1], "position": [0, 3, 0], "segments": 8, "color": "#5b3a1e"},
      {"shape": "cone" | "sphere" | "wedge" | "pyramid" | "ring", ...}
    ]
  }
Shapes: box, wedge (slope rising toward -Z), pyramid, cylinder, cone, sphere (low-poly UV sphere),
ring (torus with `thickness`). `segments` (3-48) controls roundness. Parts with the same color and
material are merged into one mesh (one MeshPart in Roblox: fewer draw calls); every mesh is checked
against Roblox's 20,000-triangle limit. Flat-shaded normals for the low-poly look (hard edges, so
each face has its own vertices: closed after Merge by Distance), planar UVs one tile per 4 studs. Materials:
plastic (default), wood, metal, glass, neon, stone, fabric: they set roughness/metalness/emission.
--preview renders a small z-buffered PNG (needs Pillow) so the model can be looked at before upload.
"""

import argparse
import json
import math
import os
import struct
import sys

MAX_TRIANGLES = 20000
UV_STUDS = 4  # planar UVs: one texture tile per 4 studs (MaterialVariant / SurfaceAppearance ready)
MATERIALS = {
    "plastic": {"roughness": 0.6, "metallic": 0.0},
    "wood": {"roughness": 0.85, "metallic": 0.0},
    "stone": {"roughness": 0.95, "metallic": 0.0},
    "fabric": {"roughness": 1.0, "metallic": 0.0},
    "metal": {"roughness": 0.35, "metallic": 1.0},
    "glass": {"roughness": 0.1, "metallic": 0.0, "alpha": 0.4},
    "neon": {"roughness": 0.5, "metallic": 0.0, "emissive": True},
}


class Fail(Exception):
    pass


# Geometry ----------------------------------------------------------------------------------
# Every shape returns a list of polygons (lists of [x, y, z]) wound counter-clockwise seen from outside,
# centered on the origin with its bounding box = size.


def box(sx, sy, sz, _segments):
    x, y, z = sx / 2, sy / 2, sz / 2
    v = [[-x, -y, -z], [x, -y, -z], [x, y, -z], [-x, y, -z], [-x, -y, z], [x, -y, z], [x, y, z], [-x, y, z]]
    faces = [(4, 5, 6, 7), (1, 0, 3, 2), (5, 1, 2, 6), (0, 4, 7, 3), (7, 6, 2, 3), (0, 1, 5, 4)]
    return [[v[i] for i in face] for face in faces]


def wedge(sx, sy, sz, _segments):
    x, y, z = sx / 2, sy / 2, sz / 2
    a, b, c, d = [-x, -y, z], [x, -y, z], [x, -y, -z], [-x, -y, -z]
    e, f = [x, y, -z], [-x, y, -z]
    return [[d, c, b, a], [d, f, e, c], [a, b, e, f], [b, c, e], [a, f, d]]


def pyramid(sx, sy, sz, _segments):
    x, y, z = sx / 2, sy / 2, sz / 2
    a, b, c, d, top = [-x, -y, z], [x, -y, z], [x, -y, -z], [-x, -y, -z], [0, y, 0]
    return [[d, c, b, a], [a, b, top], [b, c, top], [c, d, top], [d, a, top]]


def ring_points(rx, rz, y, segments):
    return [[rx * math.cos(2 * math.pi * i / segments), y, -rz * math.sin(2 * math.pi * i / segments)] for i in range(segments)]


def cylinder(sx, sy, sz, segments, top_scale=1.0):
    bottom = ring_points(sx / 2, sz / 2, -sy / 2, segments)
    polys = [list(reversed(bottom))]
    if top_scale > 0:
        top = ring_points(sx / 2 * top_scale, sz / 2 * top_scale, sy / 2, segments)
        polys.append(top)
        for i in range(segments):
            j = (i + 1) % segments
            polys.append([bottom[i], bottom[j], top[j], top[i]])
    else:
        apex = [0, sy / 2, 0]
        for i in range(segments):
            polys.append([bottom[i], bottom[(i + 1) % segments], apex])
    return polys


def cone(sx, sy, sz, segments):
    return cylinder(sx, sy, sz, segments, top_scale=0)


def sphere(sx, sy, sz, segments):
    rings = max(2, segments // 2)
    rows = []
    for r in range(rings + 1):
        phi = math.pi * r / rings
        y = math.cos(phi) * sy / 2
        k = math.sin(phi)
        rows.append(ring_points(sx / 2 * k, sz / 2 * k, y, segments))
    polys = []
    for r in range(rings):
        upper, lower = rows[r], rows[r + 1]
        for i in range(segments):
            j = (i + 1) % segments
            if r == 0:
                polys.append([lower[i], lower[j], upper[i]])
            elif r == rings - 1:
                polys.append([lower[i], upper[j], upper[i]])
            else:
                polys.append([lower[i], lower[j], upper[j], upper[i]])
    return polys


def ring(sx, sy, sz, segments, thickness=0.25):
    tube = max(3, segments // 3)
    major_x, major_z = sx / 2 - thickness / 2, sz / 2 - thickness / 2
    grid = []
    for i in range(segments):
        theta = 2 * math.pi * i / segments
        cx, cz = math.cos(theta), -math.sin(theta)
        row = []
        for t in range(tube):
            psi = 2 * math.pi * t / tube
            radial = math.cos(psi) * thickness / 2
            row.append([cx * (major_x + radial), math.sin(psi) * sy / 2, cz * (major_z + radial)])
        grid.append(row)
    polys = []
    for i in range(segments):
        a, b = grid[i], grid[(i + 1) % segments]
        for t in range(tube):
            u = (t + 1) % tube
            polys.append([a[t], b[t], b[u], a[u]])
    return polys


SHAPES = {"box": box, "wedge": wedge, "pyramid": pyramid, "cylinder": cylinder, "cone": cone, "sphere": sphere, "ring": ring}
DEFAULT_SEGMENTS = {"cylinder": 12, "cone": 12, "sphere": 10, "ring": 16}


def rotation_matrix(degrees):
    rx, ry, rz = (math.radians(a) for a in degrees)
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    # R = Rz * Ry * Rx (X applied first)
    return [
        [cy * cz, sx * sy * cz - cx * sz, cx * sy * cz + sx * sz],
        [cy * sz, sx * sy * sz + cx * cz, cx * sy * sz - sx * cz],
        [-sy, sx * cy, cx * cy],
    ]


def transform(point, matrix, offset):
    return [sum(matrix[r][c] * point[c] for c in range(3)) + offset[r] for r in range(3)]


def normal(a, b, c):
    u = [b[i] - a[i] for i in range(3)]
    v = [c[i] - a[i] for i in range(3)]
    n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
    length = math.sqrt(sum(x * x for x in n))
    return [x / length for x in n] if length > 1e-12 else None


# Spec --------------------------------------------------------------------------------------


def parse_color(value, where):
    if isinstance(value, str) and len(value) == 7 and value.startswith("#"):
        try:
            return [int(value[i : i + 2], 16) / 255 for i in (1, 3, 5)]
        except ValueError:
            pass
    raise Fail(f"{where}: color must look like #a1b2c3")


def vec3(value, where, name, default=None, positive=False):
    if value is None and default is not None:
        return list(default)
    if not (isinstance(value, list) and len(value) == 3 and all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in value)):
        raise Fail(f"{where}: {name} must be [x, y, z] numbers")
    if positive and any(x <= 0 for x in value):
        raise Fail(f"{where}: {name} must be above 0 on every axis")
    return [float(x) for x in value]


def build(spec):
    if not isinstance(spec, dict) or not isinstance(spec.get("parts"), list) or not spec["parts"]:
        raise Fail("the spec needs a non-empty \"parts\" list")
    scale = spec.get("unitsPerStud", 1)
    if not isinstance(scale, (int, float)) or scale <= 0:
        raise Fail("unitsPerStud must be a positive number")
    groups = {}  # (color, material) -> list of triangles [(a, b, c, n)]
    for index, part in enumerate(spec["parts"]):
        where = f"parts[{index}]" + (f" ({part.get('name')})" if isinstance(part, dict) and part.get("name") else "")
        if not isinstance(part, dict):
            raise Fail(f"{where}: must be an object")
        shape = part.get("shape", "box")
        if shape not in SHAPES:
            raise Fail(f"{where}: shape must be one of {', '.join(SHAPES)}")
        size = vec3(part.get("size"), where, "size", positive=True)
        position = vec3(part.get("position"), where, "position", default=[0, 0, 0])
        rotation = vec3(part.get("rotation"), where, "rotation", default=[0, 0, 0])
        segments = part.get("segments", DEFAULT_SEGMENTS.get(shape, 4))
        if not isinstance(segments, int) or not 3 <= segments <= 48:
            raise Fail(f"{where}: segments must be a whole number from 3 to 48")
        color = parse_color(part.get("color", "#a3a2a5"), where)
        material = part.get("material", "plastic")
        if material not in MATERIALS:
            raise Fail(f"{where}: material must be one of {', '.join(MATERIALS)}")
        if shape == "ring":
            thickness = part.get("thickness", min(size[0], size[2]) * 0.15)
            if not isinstance(thickness, (int, float)) or not 0 < thickness < min(size[0], size[2]) / 2:
                raise Fail(f"{where}: thickness must be above 0 and under half the ring's width")
            polys = ring(*size, segments, thickness)
        else:
            polys = SHAPES[shape](*size, segments)
        matrix = rotation_matrix(rotation)
        triangles = groups.setdefault((tuple(color), material), [])
        for poly in polys:
            points = [transform(p, matrix, position) for p in poly]
            for i in range(1, len(points) - 1):
                a, b, c = points[0], points[i], points[i + 1]
                n = normal(a, b, c)
                if n:
                    triangles.append((a, b, c, n))
    every = [p for tris in groups.values() for t in tris for p in t[:3]]
    low = [min(p[i] for p in every) for i in range(3)]
    high = [max(p[i] for p in every) for i in range(3)]
    pivot = spec.get("pivot", "bottom")
    if pivot not in ("bottom", "center", "origin"):
        raise Fail("pivot must be bottom, center or origin")
    shift = [0.0, 0.0, 0.0]
    if pivot in ("bottom", "center"):
        shift = [-(low[0] + high[0]) / 2, -low[1] if pivot == "bottom" else -(low[1] + high[1]) / 2, -(low[2] + high[2]) / 2]
    meshes = []
    for (color, material), triangles in groups.items():
        moved = [tuple([[(p[i] + shift[i]) * scale for i in range(3)] for p in t[:3]] + [t[3]]) for t in triangles]
        meshes.append({"color": list(color), "material": material, "triangles": moved})
    size = [high[i] - low[i] for i in range(3)]
    return meshes, size


# glTF writer -------------------------------------------------------------------------------


def pad(data, byte=b"\x00"):
    return data + byte * ((4 - len(data) % 4) % 4)


def to_glb(name, meshes):
    binary = bytearray()
    buffer_views, accessors, gltf_meshes, materials, nodes = [], [], [], [], []
    for index, mesh in enumerate(meshes):
        positions, normals, uvs, indices = [], [], [], []
        for a, b, c, n in mesh["triangles"]:
            axis = max(range(3), key=lambda i: abs(n[i]))  # planar UVs along the face's main axis
            u_axis, v_axis = [(2, 1), (0, 2), (0, 1)][axis]
            for p in (a, b, c):
                indices.append(len(positions))
                positions.append(p)
                normals.append(n)
                uvs.append((p[u_axis] / UV_STUDS, -p[v_axis] / UV_STUDS))
        if len(positions) > 65535:
            index_format, index_type = "<I", 5125
        else:
            index_format, index_type = "<H", 5123

        def add_view(data, target):
            nonlocal binary
            offset = len(binary)
            binary += pad(bytes(data))
            buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
            return len(buffer_views) - 1

        pos_view = add_view(b"".join(struct.pack("<3f", *p) for p in positions), 34962)
        nrm_view = add_view(b"".join(struct.pack("<3f", *n) for n in normals), 34962)
        uv_view = add_view(b"".join(struct.pack("<2f", *uv) for uv in uvs), 34962)
        idx_view = add_view(b"".join(struct.pack(index_format, i) for i in indices), 34963)
        accessors.append({
            "bufferView": pos_view, "componentType": 5126, "count": len(positions), "type": "VEC3",
            "min": [min(p[i] for p in positions) for i in range(3)],
            "max": [max(p[i] for p in positions) for i in range(3)],
        })
        accessors.append({"bufferView": nrm_view, "componentType": 5126, "count": len(normals), "type": "VEC3"})
        accessors.append({"bufferView": idx_view, "componentType": index_type, "count": len(indices), "type": "SCALAR"})
        accessors.append({"bufferView": uv_view, "componentType": 5126, "count": len(uvs), "type": "VEC2"})
        props = MATERIALS[mesh["material"]]
        material = {
            "name": f"{mesh['material']}_{''.join(f'{round(c * 255):02x}' for c in mesh['color'])}",
            "pbrMetallicRoughness": {
                "baseColorFactor": mesh["color"] + [props.get("alpha", 1.0)],
                "metallicFactor": props["metallic"],
                "roughnessFactor": props["roughness"],
            },
        }
        if props.get("alpha", 1.0) < 1:
            material["alphaMode"] = "BLEND"
        if props.get("emissive"):
            material["emissiveFactor"] = mesh["color"]
        materials.append(material)
        gltf_meshes.append({
            "name": f"{name}_{index + 1}",
            "primitives": [{
                "attributes": {"POSITION": index * 4, "NORMAL": index * 4 + 1, "TEXCOORD_0": index * 4 + 3},
                "indices": index * 4 + 2,
                "material": index,
                "mode": 4,
            }],
        })
        nodes.append({"name": f"{name}_{index + 1}", "mesh": index})
    doc = {
        "asset": {"version": "2.0", "generator": "roblox-bringforth make_model.py"},
        "scene": 0,
        "scenes": [{"name": name, "nodes": [len(nodes)]}],
        "nodes": nodes + [{"name": name, "children": list(range(len(nodes)))}],
        "meshes": gltf_meshes,
        "materials": materials,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(binary)}],
    }
    json_chunk = pad(json.dumps(doc, separators=(",", ":")).encode(), b" ")
    bin_chunk = bytes(binary)
    total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    return (
        struct.pack("<4sII", b"glTF", 2, total)
        + struct.pack("<I4s", len(json_chunk), b"JSON") + json_chunk
        + struct.pack("<I4s", len(bin_chunk), b"BIN\x00") + bin_chunk
    )


# Preview -----------------------------------------------------------------------------------


def preview(meshes, path, size=512):
    """Small z-buffered render (3/4 view from the front-right, flat shading, outlines) to eyeball a model."""
    try:
        from PIL import Image, ImageFilter
    except ImportError:
        raise Fail("--preview needs Pillow: pip install pillow")
    yaw, pitch = math.radians(35), math.radians(25)
    light = [0.4, 0.8, 0.45]
    length = math.sqrt(sum(x * x for x in light))
    light = [x / length for x in light]

    def project(p):
        x = p[0] * math.cos(yaw) - p[2] * math.sin(yaw)
        z = p[0] * math.sin(yaw) + p[2] * math.cos(yaw)
        y = p[1] * math.cos(pitch) - z * math.sin(pitch)
        depth = p[1] * math.sin(pitch) + z * math.cos(pitch)  # larger = closer to the camera
        return x, y, depth

    tris = []
    for mesh in meshes:
        for a, b, c, n in mesh["triangles"]:
            if project(n)[2] <= 0:
                continue  # back face
            shade = 0.4 + 0.6 * max(0.0, sum(n[i] * light[i] for i in range(3)))
            color = tuple(int(min(255, ch * 255 * shade)) for ch in mesh["color"])
            tris.append(([project(a), project(b), project(c)], color))
    if not tris:
        raise Fail("nothing to preview")
    xs = [p[0] for tri, _ in tris for p in tri]
    ys = [p[1] for tri, _ in tris for p in tri]
    span = max(max(xs) - min(xs), max(ys) - min(ys)) or 1
    k = size * 0.84 / span
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    zbuf = [[-math.inf] * size for _ in range(size)]
    ids = [[-1] * size for _ in range(size)]
    pixels = [[(34, 36, 46)] * size for _ in range(size)]
    for index, (tri, color) in enumerate(tris):
        pts = [(size / 2 + (x - cx) * k, size / 2 - (y - cy) * k, d) for x, y, d in tri]
        (x0, y0, d0), (x1, y1, d1), (x2, y2, d2) = pts
        area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if abs(area) < 1e-9:
            continue
        for py in range(max(0, int(min(y0, y1, y2))), min(size - 1, int(max(y0, y1, y2)) + 1) + 1):
            for px in range(max(0, int(min(x0, x1, x2))), min(size - 1, int(max(x0, x1, x2)) + 1) + 1):
                sx, sy = px + 0.5, py + 0.5
                w0 = ((x1 - sx) * (y2 - sy) - (x2 - sx) * (y1 - sy)) / area
                w1 = ((x2 - sx) * (y0 - sy) - (x0 - sx) * (y2 - sy)) / area
                w2 = 1 - w0 - w1
                if w0 < 0 or w1 < 0 or w2 < 0:
                    continue
                depth = w0 * d0 + w1 * d1 + w2 * d2
                if depth > zbuf[py][px]:
                    zbuf[py][px] = depth
                    ids[py][px] = index
                    pixels[py][px] = color
    image = Image.new("RGB", (size, size))
    image.putdata([pixels[y][x] for y in range(size) for x in range(size)])
    # Dark outline where the visible triangle changes and depth jumps (silhouettes and creases between parts).
    edge = Image.new("L", (size, size), 0)
    marks = []
    for y in range(size):
        for x in range(size):
            here = ids[y][x]
            mark = 0
            for nx, ny in ((x + 1, y), (x, y + 1)):
                if nx < size and ny < size:
                    other = ids[ny][nx]
                    if other != here and (here < 0 or other < 0 or abs(zbuf[ny][nx] - zbuf[y][x]) * k > 2):
                        mark = 255
            marks.append(mark)
    edge.putdata(marks)
    image.paste((18, 18, 24), mask=edge.filter(ImageFilter.MaxFilter(3)))
    image.save(path)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("spec")
    parser.add_argument("-o", "--output")
    parser.add_argument("--preview")
    args = parser.parse_args(argv)
    try:
        try:
            with open(args.spec, encoding="utf-8") as f:
                spec = json.load(f)
        except (OSError, json.JSONDecodeError) as e:
            raise Fail(f"{args.spec}: {e}")
        name = spec.get("name") or os.path.splitext(os.path.basename(args.spec))[0]
        if not isinstance(name, str) or not name.strip():
            raise Fail("name must be a non-empty string")
        meshes, size = build(spec)
        status = 0
        for mesh in meshes:
            count = len(mesh["triangles"])
            if count > MAX_TRIANGLES:
                print(f"ERROR mesh {mesh['material']} {mesh['color']} has {count:,} triangles (limit {MAX_TRIANGLES:,}): lower segments")
                status = 1
        if status:
            return status
        output = args.output or os.path.splitext(args.spec)[0] + ".glb"
        os.makedirs(os.path.dirname(os.path.abspath(output)), exist_ok=True)
        with open(output, "wb") as f:
            f.write(to_glb(name, meshes))
        triangles = sum(len(m["triangles"]) for m in meshes)
        print(
            f"wrote {output}: {len(meshes)} meshes (one per color/material), {triangles:,} triangles, "
            f"{size[0]:.2f} x {size[1]:.2f} x {size[2]:.2f} studs"
        )
        if args.preview:
            preview(meshes, args.preview)
            print(f"wrote {args.preview}")
        return 0
    except Fail as e:
        print(f"ERROR {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
