"""model_batch.py against real Blender (the `bpy` module): the example manifest
(assets/examples/models.json) on generated sources that come out wrong the way image-to-3D models
do (1 m long, lying down, facing the wrong way, too dense, a hole, an extra part), dry run, real run,
the exported FBX measured again, icons, ModelSpecs.luau, and resuming / redoing only what changed.
Usage: python model_batch_test.py <model_batch.py> <examples/models.json> <tmp dir>"""
import json
import math
import os
import shutil
import sys

import bpy
from mathutils import Vector

batch_path, example, tmp = sys.argv[1], sys.argv[2], sys.argv[3]
namespace = {"MODEL_BATCH_IMPORT": True, "__name__": "model_batch", "__file__": batch_path}
exec(compile(open(batch_path).read(), batch_path, "exec"), namespace)
run, ManifestError = namespace["run"], namespace["ManifestError"]

passed = failed = 0


def ok(condition, message):
    global passed, failed
    passed += bool(condition)
    failed += not condition
    print(f"  {'ok  ' if condition else 'FAIL'} {message}")


def box(name, low, high):
    bpy.ops.mesh.primitive_cube_add()
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = [(h - l) / 2 for l, h in zip(low, high)]
    obj.location = [(h + l) / 2 for l, h in zip(low, high)]
    return obj


def export_obj(path):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.wm.obj_export(filepath=path, export_selected_objects=True, export_materials=False)  # Y-up file, like most OBJs


def make_sources(raw, pedestal_radius=0.4, only=None):
    """Sources in metric-ish 'one meter' sizes, lying down and facing the wrong way."""
    os.makedirs(raw, exist_ok=True)
    if only == "Pedestal":
        make_pedestal(raw, pedestal_radius)
        return
    # Katana: 1 m along +X (lying down), edge toward +Y, plus a scabbard that must be dropped
    bpy.ops.wm.read_factory_settings(use_empty=True)
    box("Handle", (0.0, -0.012, -0.012), (0.22, 0.012, 0.012))
    box("Guard", (0.22, -0.04, -0.03), (0.24, 0.05, 0.03))
    box("Blade", (0.24, -0.006, -0.004), (1.0, 0.03, 0.004))  # mass toward +Y: the edge side
    box("Scabbard", (0.3, 0.2, -0.02), (1.0, 0.26, 0.02))
    export_obj(os.path.join(raw, "Katana.obj"))
    # Spear: 1 m along -Y, far too dense (budget 1500)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.mesh.primitive_cylinder_add(vertices=512, radius=0.015, depth=0.85, location=(0, -0.425, 0), rotation=(math.pi / 2, 0, 0))
    bpy.context.active_object.name = "Shaft"
    bpy.ops.mesh.primitive_cone_add(vertices=512, radius1=0.04, depth=0.15, location=(0, -0.925, 0), rotation=(math.pi / 2, 0, 0))
    bpy.context.active_object.name = "Tip"
    bpy.ops.mesh.primitive_uv_sphere_add(segments=128, ring_count=64, radius=0.02, location=(0, 0, 0))
    export_obj(os.path.join(raw, "Spear.obj"))
    make_pedestal(raw, pedestal_radius)


def make_pedestal(raw, pedestal_radius):
    # Pedestal: standing, 1 m tall, open at the top (a hole you can see through)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=pedestal_radius, depth=1.0, location=(0, 0, 0.5), end_fill_type="NOTHING")
    bpy.context.active_object.name = "Pedestal"
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.fbx(filepath=os.path.join(raw, "Pedestal.fbx"), use_selection=True)


def measure_fbx(path):
    """Re-imports an exported FBX with the same axis settings and returns (bounds low, high, triangles, centroid, open edges)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=path, axis_forward="Z", axis_up="Y")
    obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    points = [obj.matrix_world @ v.co for v in obj.data.vertices]
    low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    tris, open_edges, _ = namespace["CHECK"]["mesh_stats"](obj)
    return low, high, tris, points, open_edges, len([o for o in bpy.context.scene.objects if o.type == "MESH"])


def mtimes(out):
    return {f: os.path.getmtime(os.path.join(out, f)) for f in ("Katana.fbx", "Spear.fbx", "Pedestal.fbx")}


work = os.path.join(tmp, "models")
shutil.rmtree(work, ignore_errors=True)
os.makedirs(work)
manifest = os.path.join(work, "models.json")
shutil.copy(example, manifest)
make_sources(os.path.join(work, "raw"))
out = os.path.join(work, "build", "models")

print("dry run")
summary = run(manifest, dry_run=True)
ok(summary == {"done": 0, "skipped": 0, "failed": 0, "planned": 3}, f"plans all 3 models ({summary})")
ok(not os.path.exists(out), "writes nothing (no out folder, no state)")

print("real run")
summary = run(manifest)
ok(summary["done"] == 3 and summary["failed"] == 0, f"makes all 3 ({summary})")
files = ["Katana.fbx", "Spear.fbx", "Pedestal.fbx", "icons/Katana.png", "icons/Spear.png", "icons/Pedestal.png", "models.json", "ModelSpecs.luau", "model_batch_state.json"]
ok(all(os.path.exists(os.path.join(out, f)) for f in files), "FBX, icon, models.json, ModelSpecs.luau and state written")
results = json.load(open(os.path.join(out, "models.json")))

low, high, tris, points, _, meshes = measure_fbx(os.path.join(out, "Katana.fbx"))
size = high - low
ok(abs(size.z - 4) < 0.01 and size.z > 10 * max(size.x, size.y), f"Katana stands tip up, 4 studs tall ({size.z:.3f} x {size.x:.3f} x {size.y:.3f})")
ok(size.y < 0.5 and meshes == 1, f"scabbard dropped, one mesh ({size.y:.3f} deep)")
blade_y = [p.y for p in points if p.z > 1.0]  # blade: well above the guard
handle_y = [p.y for p in points if p.z < -0.1]  # handle: below the grip
edge = min(blade_y) - min(handle_y), max(blade_y) - max(handle_y)
ok(edge[0] < -0.05 and edge[1] < 0.05, f"sharp edge faces front (-Y, Roblox LookVector): blade reaches {-edge[0]:.3f} past the handle on -Y")
ok(abs(low.z + 0.4) < 0.01, f"pivot at the grip (10% up the 4-stud model): bottom at z {low.z:.3f}")
grip, blade = results["Katana"]["attachments"]["Grip"], results["Katana"]["attachments"]["BladeStart"]
ok(abs(grip[1] + 1.6) < 1e-3 and abs(blade[1] + 0.96) < 1e-3, f"Grip 1.6 and BladeStart 0.96 studs below the center (Roblox Y up): {grip} {blade}")
ok(results["Katana"]["robloxSize"][1] == max(results["Katana"]["robloxSize"]), "Roblox size: the long side is Y (up)")

low, high, tris, _, _, _ = measure_fbx(os.path.join(out, "Spear.fbx"))
ok(abs((high - low).z - 6.5) < 0.01, f"Spear turned upright and scaled to 6.5 studs ({(high - low).z:.3f})")
ok(tris <= 1500 and results["Spear"]["trianglesIn"] > 1500, f"Spear decimated {results['Spear']['trianglesIn']} -> {tris} triangles (budget 1500)")

low, high, tris, _, open_edges, _ = measure_fbx(os.path.join(out, "Pedestal.fbx"))
ok(abs((high - low).z - 1.5) < 0.01 and abs(low.z) < 1e-3, f"Pedestal 1.5 studs tall with its pivot at the bottom (z {low.z:.4f})")
ok(open_edges == 0, "Pedestal hole closed (watertight)")
ok(abs(results["Pedestal"]["pivotOffset"][1] + 0.75) < 1e-3, f"PivotOffset at the bottom: {results['Pedestal']['pivotOffset']}")

icon = bpy.data.images.load(os.path.join(out, "icons", "Katana.png"))
w, h = icon.size
pixels = list(icon.pixels)
alpha = lambda x, y: pixels[(y * w + x) * 4 + 3]
rows = [y for y in range(h) if any(alpha(x, y) > 0.1 for x in range(0, w, 2))]
cols = [x for x in range(w) if any(alpha(x, y) > 0.1 for y in range(0, h, 2))]
ok((w, h) == (256, 256) and alpha(0, 0) == 0 and alpha(w - 1, h - 1) == 0, "icon 256x256 with a transparent background")
ok(rows and cols and (rows[-1] - rows[0]) > 2 * (cols[-1] - cols[0]) and (rows[-1] - rows[0]) > 0.7 * h, "icon framed on the model, standing upright")

specs = open(os.path.join(out, "ModelSpecs.luau")).read()
ok("Katana = {" in specs and "Grip = Vector3.new(" in specs and "function ModelSpecs.apply" in specs, "ModelSpecs.luau lists sizes, pivots and grip attachments")

print("resume and redo only what changed")
before = mtimes(out)
summary = run(manifest)
ok(summary["skipped"] == 3 and summary["done"] == 0 and mtimes(out) == before, f"second run skips all 3, files untouched ({summary})")
data = json.load(open(manifest))
data["models"][1]["studs"] = 7
json.dump(data, open(manifest, "w"), indent=1)
summary = run(manifest)
ok(summary["done"] == 1 and summary["skipped"] == 2 and mtimes(out)["Spear.fbx"] != before["Spear.fbx"] and mtimes(out)["Katana.fbx"] == before["Katana.fbx"], f"changed setting: only Spear redone ({summary})")
make_sources(os.path.join(work, "raw"), pedestal_radius=0.3, only="Pedestal")
summary = run(manifest)
ok(summary["done"] == 1 and json.load(open(os.path.join(out, "models.json")))["Pedestal"]["studs"][0] < results["Pedestal"]["studs"][0], f"changed source file: only Pedestal redone ({summary})")
summary = run(manifest, force=True, only=["Katana"])
ok(summary["done"] == 1 and summary["skipped"] == 0, "--force --only Katana redoes just Katana")

print("failures, retries, manifest errors")
data["models"].append({"name": "Hammer", "source": "raw/Hammer.obj", "studs": 5})
json.dump(data, open(manifest, "w"), indent=1)
summary = run(manifest)
state = json.load(open(os.path.join(out, "model_batch_state.json")))
ok(summary["failed"] == 1 and summary["skipped"] == 3 and state["models"]["Hammer"]["status"] == "failed" and "source not found" in state["models"]["Hammer"]["error"], "a missing source fails that model only; the others stay done")
bpy.ops.wm.read_factory_settings(use_empty=True)
box("Head", (-0.2, -0.1, 0.8), (0.2, 0.1, 1.0))
box("Handle", (-0.02, -0.02, 0.0), (0.02, 0.02, 0.8))
export_obj(os.path.join(work, "raw", "Hammer.obj"))
summary = run(manifest)
ok(summary["done"] == 1 and summary["skipped"] == 3, f"next run retries the failed model ({summary})")
for bad, needle in (
    ({"name": "X", "source": "a.obj", "studs": 1, "up": "+Z", "front": "-Z"}, "must be different axes"),
    ({"name": "X", "source": "a.obj", "studs": 1, "pivot": "Grip"}, "pivot must be"),
    ({"name": "X", "source": "a.obj", "studs": 0}, "studs must be"),
    ({"name": "X", "source": "a.obj", "studs": 1, "maxTriangles": 50000}, "maxTriangles must be"),
    ({"name": "Bad Name", "source": "a.obj", "studs": 1}, "Luau identifier"),
    ({"name": "X", "source": "a.obj", "studs": 1, "colour": 1}, "unknown key"),
):
    json.dump({"models": [bad]}, open(os.path.join(work, "bad.json"), "w"))
    try:
        run(os.path.join(work, "bad.json"), dry_run=True)
        ok(False, f"manifest error: {needle}")
    except ManifestError as error:
        ok(needle in str(error), f"manifest error: {needle}")

print("command line (fresh interpreter, like `python model_batch.py` / `blender -b --python`)")
import subprocess  # noqa: E402

cli = subprocess.run([sys.executable, batch_path, manifest, "--dry-run"], capture_output=True, text=True)
ok(cli.returncode == 0 and "would make 0, skipped 4 unchanged, 0 failed (nothing written)" in cli.stdout, f"--dry-run from the command line: exit {cli.returncode}")
cli = subprocess.run([sys.executable, batch_path, os.path.join(work, "bad.json")], capture_output=True, text=True)
ok(cli.returncode == 2 and "manifest error:" in cli.stdout, f"bad manifest from the command line: exit {cli.returncode}")

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
