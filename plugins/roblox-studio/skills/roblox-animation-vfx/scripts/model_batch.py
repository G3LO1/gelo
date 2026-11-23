"""Batch preparation of 3D models for Roblox, run inside Blender (no UI needed).

Every model in a manifest is imported, cleaned, stood up the right way, scaled to its real size in
studs, given its pivot and grip points, brought under its triangle budget, checked with
blender_check.py, exported as a Roblox-ready FBX and rendered to an icon from one fixed camera.
A state file remembers what was made from which source and settings, so a second run only redoes
the models whose source or settings changed (and the ones that failed), and an interrupted run
resumes where it stopped.

Run it:
  blender -b --python model_batch.py -- models.json [--dry-run] [--only Katana,Spear] [--force]
  python model_batch.py models.json [...]          (a Python with the `bpy` module from PyPI)
  Blender MCP code tool: send this file with MANIFEST (and DRY_RUN) set below.
--dry-run does every step in memory and prints the plan (sizes, scale factors, triangle counts,
problems, what would be redone or skipped) but writes nothing: no FBX, icon, state or specs.

Manifest (paths relative to the manifest):
{
  "out": "build/models",
  "defaults": { "maxTriangles": 4000, "up": "+Z", "front": "-Y", "pivot": "bottom" },
  "icon": { "size": 256, "azimuth": 35, "elevation": 20, "fill": 0.85, "samples": 16 },
  "models": [
    { "name": "Katana", "source": "raw/katana.fbx", "studs": 4, "up": "+X", "front": "+Y",
      "pivot": "Grip", "points": { "Grip": [0.5, 0.5, 0.12], "BladeStart": [0.5, 0.5, 0.27] },
      "keep": ["Blade*", "Handle*"], "fillHoles": true, "maxTriangles": 3500 }
  ]
}
  up / front   which source axis points up / to the front (the sharp edge, the face players see);
               the model is turned so up is Blender +Z and front is Blender -Y (Front view), which
               the FBX export maps to Roblox up and the part's front (LookVector).
  studs        size of the longest side in studs, or { "z": 4 } for one axis (Blender axes, after
               turning: z = height). Uniform scale.
  pivot        "bottom" (center of the bottom face), "center", "top", or the name of a point.
  points       named points as fractions of the turned model's bounding box, [x, y, z] in 0..1
               (z 0 = bottom, 1 = top). Become Attachments in Studio via ModelSpecs.luau.
  keep         object-name patterns to keep; other imported objects are dropped (extra parts).
  fillHoles    close open boundaries (holes you can see through in game).
  maxTriangles budget; meshes above it are decimated (Roblox's hard limit is 20,000 per mesh).

Writes to out/: <name>.fbx, icons/<name>.png, models.json (results), ModelSpecs.luau (Size,
PivotOffset and Attachments in Roblox axes, relative to the MeshPart's center, plus apply()), and
model_batch_state.json.
"""

import fnmatch
import hashlib
import json
import math
import os
import sys
import time
import traceback

import bpy  # first: with the bpy module from PyPI, bmesh and mathutils only exist after it

import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

MANIFEST = None  # set when pasting into a Blender MCP code tool
DRY_RUN = False
VERSION = 1  # bump when processing changes, so every model is redone once

AXES = {
    "+X": Vector((1, 0, 0)),
    "-X": Vector((-1, 0, 0)),
    "+Y": Vector((0, 1, 0)),
    "-Y": Vector((0, -1, 0)),
    "+Z": Vector((0, 0, 1)),
    "-Z": Vector((0, 0, -1)),
}
MODEL_KEYS = {"name", "source", "studs", "up", "front", "pivot", "points", "keep", "fillHoles", "maxTriangles", "icon"}
DEFAULTS = {"up": "+Z", "front": "-Y", "pivot": "bottom", "maxTriangles": 4000, "fillHoles": False}
ICON = {"size": 256, "azimuth": 35, "elevation": 20, "fill": 0.85, "samples": 16, "background": None}


def load_checker():
    here = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
    path = os.path.join(here, "blender_check.py")
    namespace = {"ROBLOX_CHECK_IMPORT": True, "__name__": "blender_check"}
    exec(compile(open(path, encoding="utf-8").read(), path, "exec"), namespace)
    return namespace


CHECK = load_checker()


class ManifestError(Exception):
    pass


# ---------------------------------------------------------------- manifest


def read_manifest(path):
    with open(path, encoding="utf-8") as f:
        manifest = json.load(f)
    base = os.path.dirname(os.path.abspath(path))
    if not isinstance(manifest.get("models"), list) or not manifest["models"]:
        raise ManifestError("'models' must be a non-empty list")
    defaults = {**DEFAULTS, **(manifest.get("defaults") or {})}
    icon = {**ICON, **(manifest.get("icon") or {})}
    names = set()
    models = []
    for index, raw in enumerate(manifest["models"]):
        where = f"models[{index}]"
        if not isinstance(raw, dict) or not isinstance(raw.get("name"), str) or not raw["name"].isidentifier():
            raise ManifestError(f"{where}: needs a 'name' that is a Luau identifier (it names the FBX and the MeshPart)")
        where = raw["name"]
        unknown = set(raw) - MODEL_KEYS
        if unknown:
            raise ManifestError(f"{where}: unknown key(s) {sorted(unknown)}")
        if raw["name"] in names:
            raise ManifestError(f"{where}: duplicate name")
        names.add(raw["name"])
        model = {**defaults, **raw, "icon": {**icon, **(raw.get("icon") or {})}}
        if not isinstance(model.get("source"), str):
            raise ManifestError(f"{where}: needs a 'source' file")
        model["sourcePath"] = os.path.normpath(os.path.join(base, model["source"]))
        for key in ("up", "front"):
            if model[key] not in AXES:
                raise ManifestError(f"{where}: {key} must be one of {', '.join(AXES)}")
        if abs(AXES[model["up"]].dot(AXES[model["front"]])) > 0.5:
            raise ManifestError(f"{where}: up {model['up']} and front {model['front']} must be different axes")
        studs = model.get("studs")
        if isinstance(studs, dict):
            if len(studs) != 1 or next(iter(studs)) not in ("x", "y", "z") or not _positive(next(iter(studs.values()))):
                raise ManifestError(f"{where}: studs must be a number or one axis like {{\"z\": 4}}")
        elif not _positive(studs):
            raise ManifestError(f"{where}: studs must be a positive number (longest side in studs)")
        points = model.get("points") or {}
        for point, value in points.items():
            if not point.isidentifier() or not (isinstance(value, list) and len(value) == 3 and all(isinstance(v, (int, float)) and -0.5 <= v <= 1.5 for v in value)):
                raise ManifestError(f"{where}: points.{point} must be [x, y, z] fractions of the bounding box")
        if model["pivot"] not in ("bottom", "center", "top") and model["pivot"] not in points:
            raise ManifestError(f"{where}: pivot must be bottom, center, top or a point name ({', '.join(points) or 'no points'})")
        budget = model["maxTriangles"]
        if not (isinstance(budget, int) and 12 <= budget <= CHECK["MAX_TRIANGLES"]):
            raise ManifestError(f"{where}: maxTriangles must be 12..{CHECK['MAX_TRIANGLES']}")
        models.append(model)
    out = os.path.normpath(os.path.join(base, manifest.get("out", "build/models")))
    return models, out


def _positive(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and value > 0


def model_key(model):
    """Hash of the source bytes, the model's settings and the processing version."""
    digest = hashlib.sha256()
    digest.update(f"v{VERSION}".encode())
    settings = {k: v for k, v in model.items() if k != "sourcePath"}
    digest.update(json.dumps(settings, sort_keys=True).encode())
    if os.path.exists(model["sourcePath"]):
        with open(model["sourcePath"], "rb") as f:
            for block in iter(lambda: f.read(1 << 20), b""):
                digest.update(block)
    return digest.hexdigest()[:16]


# ---------------------------------------------------------------- Blender steps


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"
    scene.unit_settings.system_rotation = "DEGREES"
    return scene


def import_source(path):
    ext = os.path.splitext(path)[1].lower()
    if not os.path.exists(path):
        raise FileNotFoundError(f"source not found: {path}")
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    elif ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".blend":
        with bpy.data.libraries.load(path) as (src, dst):
            dst.objects = list(src.objects)
        for obj in dst.objects:
            if obj is not None:
                bpy.context.scene.collection.objects.link(obj)
    else:
        raise ValueError(f"unsupported source type {ext} (fbx, obj, glb, gltf, blend)")


def collect_mesh(name, keep, notes):
    """Bakes transforms, drops non-mesh and unwanted objects, joins the rest into one mesh object."""
    scene = bpy.context.scene
    meshes = []
    for obj in list(scene.objects):
        if obj.type != "MESH":
            continue
        if keep and not any(fnmatch.fnmatchcase(obj.name, pattern) for pattern in keep):
            notes.append(f"dropped {obj.name} (not in keep)")
            continue
        meshes.append(obj)
    for obj in list(scene.objects):
        if obj not in meshes:
            bpy.data.objects.remove(obj, do_unlink=True)
    if not meshes:
        raise ValueError("no mesh left to export (check 'keep')")
    for obj in meshes:
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.data = obj.data.copy()
        obj.data.transform(world)
        obj.matrix_world = Matrix.Identity(4)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
        notes.append(f"joined {len(meshes)} objects")
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    return obj


def bounds(obj):
    coords = [v.co for v in obj.data.vertices]
    low = Vector((min(c.x for c in coords), min(c.y for c in coords), min(c.z for c in coords)))
    high = Vector((max(c.x for c in coords), max(c.y for c in coords), max(c.z for c in coords)))
    return low, high


def orientation(up, front):
    """Rotation that turns the source's up axis to +Z and its front axis to -Y."""
    u, f = AXES[up], AXES[front]
    r = u.cross(f)
    source = Matrix((r, f, u)).transposed()  # columns: right, front, up
    target = Matrix(((1, 0, 0), (0, -1, 0), (0, 0, 1))).transposed()
    return (target @ source.transposed()).to_4x4()


def fill_holes(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    boundary = [e for e in bm.edges if e.is_boundary]
    if boundary:
        bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return len(boundary)


def triangles(obj):
    return CHECK["mesh_stats"](obj)[0]


def decimate(obj, budget):
    for _ in range(4):
        count = triangles(obj)
        if count <= budget:
            break
        modifier = obj.modifiers.new("Budget", "DECIMATE")
        modifier.ratio = max(0.001, budget / count * 0.97)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return triangles(obj)


def to_roblox(v):
    """Blender vector -> Roblox axes, matching the FBX export (axis_up Y, axis_forward Z)."""
    return [round(-v.x, 4) + 0.0, round(v.z, 4) + 0.0, round(v.y, 4) + 0.0]


def prepare(model, notes):
    """Imports and fixes one model in the current (fresh) scene. Returns (object, result dict)."""
    reset_scene()
    import_source(model["sourcePath"])
    obj = collect_mesh(model["name"], model.get("keep"), notes)
    tris_in = triangles(obj)
    low, high = bounds(obj)
    size_in = high - low

    obj.data.transform(orientation(model["up"], model["front"]))
    low, high = bounds(obj)
    size = high - low
    studs = model["studs"]
    if isinstance(studs, dict):
        axis, target = next(iter(studs.items()))
        current = getattr(size, axis)
    else:
        target, current = studs, max(size)
    if current <= 1e-9:
        raise ValueError("the model has no size")
    factor = target / current
    obj.data.transform(Matrix.Scale(factor, 4))

    if model.get("fillHoles"):
        filled = fill_holes(obj)
        if filled:
            notes.append(f"closed holes ({filled} open edges)")
    tris = decimate(obj, model["maxTriangles"]) if tris_in > model["maxTriangles"] else triangles(obj)
    if tris < tris_in:
        notes.append(f"decimated {tris_in} -> {tris} triangles")

    low, high = bounds(obj)
    points = {}
    for name, frac in (model.get("points") or {}).items():
        points[name] = Vector(tuple(low[i] + (high[i] - low[i]) * frac[i] for i in range(3)))
    center = (low + high) / 2
    pivot = model["pivot"]
    if pivot == "bottom":
        origin = Vector((center.x, center.y, low.z))
    elif pivot == "top":
        origin = Vector((center.x, center.y, high.z))
    elif pivot == "center":
        origin = center
    else:
        origin = points[pivot].copy()
    obj.data.transform(Matrix.Translation(-origin))
    low, high = low - origin, high - origin
    center = (low + high) / 2
    size = high - low

    result = {
        "trianglesIn": tris_in,
        "triangles": tris,
        "sourceSize": [round(v, 4) for v in size_in],
        "scale": round(factor, 6),
        "studs": [round(v, 4) for v in size],
        # Roblox: MeshPart.Size, and offsets from the MeshPart's center (its CFrame)
        "robloxSize": [abs(v) for v in to_roblox(size)],
        "pivotOffset": to_roblox(-center),
        "attachments": {name: to_roblox(point - origin - center) for name, point in points.items()},
    }
    return obj, result


def render_icon(obj, cfg, path):
    """Orthographic icon from one fixed camera direction, framed on the model, transparent
    background, so every item card is lit and angled the same way."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = int(cfg["samples"])
    scene.cycles.use_denoising = False
    scene.render.resolution_x = scene.render.resolution_y = int(cfg["size"])
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = cfg.get("background") is None
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    world = bpy.data.worlds.new("IconWorld")
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    if background:
        background.inputs[0].default_value = (0.8, 0.82, 0.86, 1)
        background.inputs[1].default_value = 0.25
    scene.world = world

    low, high = bounds(obj)
    center = (low + high) / 2
    az, el = math.radians(cfg["azimuth"]), math.radians(cfg["elevation"])
    # camera looks at the model's front (-Y side), turned by azimuth around Z, raised by elevation
    direction = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    forward = -direction
    right = forward.cross(Vector((0, 0, 1))).normalized()
    up = right.cross(forward).normalized()
    corners = [Vector((x, y, z)) for x in (low.x, high.x) for y in (low.y, high.y) for z in (low.z, high.z)]
    width = max(c.dot(right) for c in corners) - min(c.dot(right) for c in corners)
    height = max(c.dot(up) for c in corners) - min(c.dot(up) for c in corners)
    distance = (high - low).length * 2 + 1

    camera_data = bpy.data.cameras.new("IconCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = max(width, height, 1e-3) / float(cfg["fill"])
    camera_data.clip_end = distance * 4
    camera = bpy.data.objects.new("IconCamera", camera_data)
    scene.collection.objects.link(camera)
    camera.location = center + direction * distance
    camera.rotation_euler = forward.to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera

    key = bpy.data.objects.new("IconKey", bpy.data.lights.new("IconKey", "SUN"))
    key.data.energy = 4.5
    # sunlight travels from above the camera's left shoulder down onto the model
    key.rotation_euler = (forward - up * 0.8 + right * 0.4).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(key)
    if not obj.data.materials:
        material = bpy.data.materials.new("IconGrey")
        material.diffuse_color = (0.7, 0.7, 0.72, 1)
        obj.data.materials.append(material)

    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for thing in (camera, key):
        bpy.data.objects.remove(thing, do_unlink=True)
    return path


# ---------------------------------------------------------------- state and outputs


def load_state(out):
    path = os.path.join(out, "model_batch_state.json")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            state = json.load(f)
        if state.get("version") == VERSION:
            return state
    return {"version": VERSION, "models": {}}


def save_state(out, state):
    path = os.path.join(out, "model_batch_state.json")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=1, sort_keys=True)
    os.replace(tmp, path)  # never a half-written state file


def luau_vector(v):
    return f"Vector3.new({v[0]:g}, {v[1]:g}, {v[2]:g})"


def write_specs(out, state, manifest_name):
    done = {name: entry for name, entry in sorted(state["models"].items()) if entry.get("status") == "done"}
    with open(os.path.join(out, "models.json"), "w", encoding="utf-8") as f:
        json.dump({name: entry["result"] for name, entry in done.items()}, f, indent=1, sort_keys=True)
    lines = [
        f"-- Generated by model_batch.py from {manifest_name}. Do not edit: change the manifest and run it again.",
        "-- Sizes in studs; PivotOffset and Attachments are relative to the MeshPart's center (its CFrame).",
        "-- In Studio, after importing the FBX files: ModelSpecs.apply(meshPart) sets the pivot and adds the",
        "-- grip Attachments (and warns when the part was imported at another scale).",
        "",
        "local ModelSpecs = {}",
        "",
        "ModelSpecs.Models = {",
    ]
    for name, entry in done.items():
        r = entry["result"]
        attachments = ", ".join(f"{point} = {luau_vector(v)}" for point, v in sorted(r["attachments"].items()))
        lines.append(f"\t{name} = {{")
        lines.append(f"\t\tSize = {luau_vector(r['robloxSize'])},")
        lines.append(f"\t\tPivotOffset = {luau_vector(r['pivotOffset'])},")
        lines.append(f"\t\tAttachments = {{ {attachments} }}," if attachments else "\t\tAttachments = {},")
        lines.append(f"\t\tTriangles = {r['triangles']},")
        lines.append("\t},")
    lines += [
        "}",
        "",
        "function ModelSpecs.apply(part: BasePart, name: string?): boolean",
        "\tlocal spec = ModelSpecs.Models[name or part.Name]",
        "\tif not spec then",
        '\t\twarn(`[ModelSpecs] no spec for "{name or part.Name}"`)',
        "\t\treturn false",
        "\tend",
        "\tlocal size = part.Size",
        "\tlocal expected = spec.Size",
        "\tif math.abs(size.Magnitude - expected.Magnitude) > 0.05 * expected.Magnitude then",
        "\t\twarn(`[ModelSpecs] {part.Name} is {size}, expected {expected}: check the importer's scale settings`)",
        "\tend",
        "\tpart.PivotOffset = CFrame.new(spec.PivotOffset)",
        "\tfor pointName, position in spec.Attachments do",
        "\t\tlocal attachment = part:FindFirstChild(pointName)",
        "\t\tif not (attachment and attachment:IsA(\"Attachment\")) then",
        "\t\t\tattachment = Instance.new(\"Attachment\")",
        "\t\t\tattachment.Name = pointName",
        "\t\t\tattachment.Parent = part",
        "\t\tend",
        "\t\t(attachment :: Attachment).Position = position",
        "\tend",
        "\treturn true",
        "end",
        "",
        "return ModelSpecs",
        "",
    ]
    with open(os.path.join(out, "ModelSpecs.luau"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


# ---------------------------------------------------------------- run


def run(manifest_path, dry_run=False, only=None, force=False):
    models, out = read_manifest(manifest_path)
    if only:
        unknown = set(only) - {m["name"] for m in models}
        if unknown:
            raise ManifestError(f"--only: unknown model(s) {sorted(unknown)}")
        models = [m for m in models if m["name"] in only]
    state = load_state(out)
    summary = {"done": 0, "skipped": 0, "failed": 0, "planned": 0}
    print(f"{'DRY RUN: ' if dry_run else ''}{len(models)} model(s) -> {out}")
    for model in models:
        name = model["name"]
        key = model_key(model)
        previous = state["models"].get(name, {})
        outputs = [os.path.join(out, f"{name}.fbx"), os.path.join(out, "icons", f"{name}.png")]
        if not force and previous.get("key") == key and previous.get("status") == "done" and all(os.path.exists(p) for p in outputs):
            summary["skipped"] += 1
            print(f"  skip  {name}: unchanged since {previous.get('time', '?')}")
            continue
        why = "new" if not previous else ("retry after failure" if previous.get("status") == "failed" else ("forced" if force and previous.get("key") == key else "changed"))
        notes = []
        try:
            obj, result = prepare(model, notes)
            report, _ = CHECK["check"]("model")
            problems = [f"{level} {message}" for level, where, message in report.lines if level in ("ERROR", "WARN")]
            if report.count("ERROR"):
                raise ValueError("blender_check: " + "; ".join(problems))
            result["warnings"] = problems
            line = (
                f"{name}: {why}; {'x'.join(f'{v:g}' for v in result['sourceSize'])} -> "
                f"{'x'.join(f'{v:g}' for v in result['studs'])} studs (x{result['scale']:g}), "
                f"{result['trianglesIn']} -> {result['triangles']} triangles (budget {model['maxTriangles']}), "
                f"pivot {model['pivot']}" + (f", points {', '.join(result['attachments'])}" if result["attachments"] else "")
            )
            for note in notes + problems:
                line += f"\n        {note}"
            if dry_run:
                summary["planned"] += 1
                print(f"  plan  {line}")
                continue
            os.makedirs(os.path.join(out, "icons"), exist_ok=True)
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            CHECK["export_fbx"](outputs[0], "model", selected_only=True)
            render_icon(obj, model["icon"], outputs[1])
            state["models"][name] = {"key": key, "status": "done", "time": time.strftime("%Y-%m-%d %H:%M:%S"), "outputs": [os.path.relpath(p, out) for p in outputs], "result": result, "notes": notes}
            save_state(out, state)
            summary["done"] += 1
            print(f"  done  {line}")
        except Exception as error:  # one bad model must not stop the batch
            summary["failed"] += 1
            message = f"{type(error).__name__}: {error}"
            print(f"  FAIL  {name}: {message}")
            if os.environ.get("MODEL_BATCH_TRACE"):
                traceback.print_exc()
            if not dry_run:
                state["models"][name] = {"key": key, "status": "failed", "time": time.strftime("%Y-%m-%d %H:%M:%S"), "error": message}
                save_state(out, state)
    if not dry_run and (summary["done"] or summary["failed"] or not os.path.exists(os.path.join(out, "ModelSpecs.luau"))):
        os.makedirs(out, exist_ok=True)
        save_state(out, state)
        write_specs(out, state, os.path.basename(manifest_path))
    verb = "would make" if dry_run else "made"
    count = summary["planned"] if dry_run else summary["done"]
    print(f"{verb} {count}, skipped {summary['skipped']} unchanged, {summary['failed']} failed" + (" (nothing written)" if dry_run else ""))
    return summary


def main(argv):
    args = argv[argv.index("--") + 1 :] if "--" in argv else argv[1:]
    manifest, dry_run, only, force = MANIFEST, DRY_RUN, None, False
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--dry-run":
            dry_run = True
        elif arg == "--force":
            force = True
        elif arg == "--only" and i + 1 < len(args):
            only = [n.strip() for n in args[i + 1].split(",") if n.strip()]
            i += 1
        elif not arg.startswith("--"):
            manifest = arg
        i += 1
    if not manifest:
        print(__doc__)
        return 2
    try:
        summary = run(manifest, dry_run, only, force)
    except ManifestError as error:
        print(f"manifest error: {error}")
        return 2
    return 1 if summary["failed"] else 0


# Runs on `blender -b --python`, `python model_batch.py` and when pasted into an MCP code tool
# (which keeps Blender open: no exit there). Tests set MODEL_BATCH_IMPORT = True and call run().
if not globals().get("MODEL_BATCH_IMPORT"):
    EXIT_CODE = main(sys.argv)
    if bpy.app.background:
        sys.exit(EXIT_CODE)
