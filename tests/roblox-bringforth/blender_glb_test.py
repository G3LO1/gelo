"""make_model.py output in real Blender (the `bpy` module from PyPI): every example imports through
Blender's glTF importer with the expected meshes, triangle counts, size and materials, and passes the
plugin's own blender_check.py (model mode) with no errors and no open edges.
Usage: python blender_glb_test.py <roblox-bringforth skill dir> <blender_check.py> <tmp dir>"""

import json
import os
import subprocess
import sys

import bpy
import bmesh  # noqa: E402  (bpy must be imported first)

skill, check_path, tmp = sys.argv[1], sys.argv[2], sys.argv[3]
namespace = {"ROBLOX_CHECK_IMPORT": True, "__name__": "blender_check"}
exec(compile(open(check_path).read(), check_path, "exec"), namespace)
check = namespace["check"]

passed = failed = 0


def ok(condition, message, detail=""):
    global passed, failed
    if condition:
        passed += 1
        print(f"  ok   {message}")
    else:
        failed += 1
        print(f"  FAIL {message}")
        if detail:
            print("       " + str(detail).replace("\n", "\n       "))


for name in ("lowpoly_tree", "treasure_chest", "lamp_post"):
    spec_path = os.path.join(skill, "assets", "examples", f"{name}.json")
    out = os.path.join(tmp, f"{name}.glb")
    result = subprocess.run(
        [sys.executable, "-I", os.path.join(skill, "scripts", "make_model.py"), spec_path, "-o", out],
        capture_output=True, text=True,
    )
    ok(result.returncode == 0, f"{name}: make_model.py", result.stdout + result.stderr)
    spec = json.load(open(spec_path))
    colors = {(p.get("color"), p.get("material", "plastic")) for p in spec["parts"]}

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "NONE"
    bpy.ops.import_scene.gltf(filepath=out, merge_vertices=True)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    ok(len(meshes) == len(colors), f"{name}: Blender imports {len(meshes)} meshes (one per color/material)")
    reported = int(result.stdout.split(" triangles")[0].rsplit(" ", 1)[-1].replace(",", ""))
    triangles = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
    ok(triangles == reported, f"{name}: {triangles} triangles in Blender = {reported} reported")
    ok(all(len(o.data.materials) == 1 and o.data.materials[0] is not None for o in meshes), f"{name}: one material per mesh")

    # Blender converts glTF's Y-up to Z-up: the model's height is Blender Z.
    xs, ys, zs = [], [], []
    for obj in meshes:
        for v in obj.data.vertices:
            world = obj.matrix_world @ v.co
            xs.append(world.x)
            ys.append(world.y)
            zs.append(world.z)
    size_line = result.stdout.split("triangles, ")[1].split(" studs")[0]
    expected = [float(x) for x in size_line.split(" x ")]
    got = [max(xs) - min(xs), max(zs) - min(zs), max(ys) - min(ys)]
    ok(all(abs(a - b) < 0.02 for a, b in zip(got, expected)), f"{name}: size {got} = {expected} studs")
    ok(abs(min(zs)) < 1e-4, f"{name}: sits on the ground (min Z {min(zs):.5f})")

    report, _ = check("model")
    errors = [line for line in report.lines if line[0] == "ERROR"]
    warnings = [line for line in report.lines if line[0] == "WARN" and "open/non-manifold" not in line[2]]
    ok(not errors and not warnings, f"{name}: blender_check.py model mode: no errors, no warnings but split normals", report.text())
    # Flat shading = hard edges = split vertices, which Blender counts as open edges until merged.
    still_open = 0
    for obj in meshes:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        still_open += sum(1 for e in bm.edges if not e.is_manifold)
        bm.free()
    ok(still_open == 0, f"{name}: closed shells (0 open edges after Merge by Distance)")
    ok(all(o.data.uv_layers for o in meshes), f"{name}: UV map present")

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
