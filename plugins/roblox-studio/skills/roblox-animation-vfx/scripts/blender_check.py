"""Roblox readiness check (and export) for the open Blender scene.

Run it inside Blender:
  - through a Blender MCP server: send this whole file to its code-execution tool
    (e.g. execute_blender_code); set MODE / EXPORT_PATH below first if needed;
  - from a terminal: blender -b scene.blend --python blender_check.py -- [--mode animation|model|auto] [--export out.fbx]

It only reads the scene, except export_fbx(), which writes the file you ask for. It never
changes or saves the .blend.

Checks (from create.roblox.com: art/blender, art/modeling/export-requirements, specifications,
avatar/character-bodies/specifications, export-avatar-animations guides):
  scene    unit system None (1 Blender unit = 1 stud), degrees, frame rate 30 for animations
  meshes   <= 20,000 triangles, watertight, applied scale/rotation, UVs, one material
  rig      standard R15 bone names and hierarchy (when the armature looks like an R15 rig),
           no leaf/_end bones, armature scale 1
  anim     in place (no HumanoidRootNode/HumanoidRootPart travel), keyframes present, length
"""

import math
import sys

import bpy

MODE = "auto"  # "auto" | "animation" | "model"
EXPORT_PATH = None  # e.g. "/path/Chop.fbx": export with Roblox settings after a clean check

MAX_TRIANGLES = 20000
ROOT_TRAVEL_LIMIT = 0.05  # Blender units (= studs with unit system None)

R15_PARENTS = {
    "LowerTorso": "HumanoidRootNode",
    "UpperTorso": "LowerTorso",
    "Head": "UpperTorso",
    "LeftUpperArm": "UpperTorso",
    "LeftLowerArm": "LeftUpperArm",
    "LeftHand": "LeftLowerArm",
    "RightUpperArm": "UpperTorso",
    "RightLowerArm": "RightUpperArm",
    "RightHand": "RightLowerArm",
    "LeftUpperLeg": "LowerTorso",
    "LeftLowerLeg": "LeftUpperLeg",
    "LeftFoot": "LeftLowerLeg",
    "RightUpperLeg": "LowerTorso",
    "RightLowerLeg": "RightUpperLeg",
    "RightFoot": "RightLowerLeg",
}
ROOT_NAMES = ("HumanoidRootNode", "HumanoidRootPart")  # body spec vs. animation guides


class Report:
    def __init__(self):
        self.lines = []

    def add(self, level, where, message):
        self.lines.append((level, where, message))

    def count(self, level):
        return sum(1 for line in self.lines if line[0] == level)

    def text(self):
        out = [f"{level:5} {where}: {message}" for level, where, message in self.lines]
        out.append(f"{self.count('ERROR')} error(s), {self.count('WARN')} warning(s)")
        return "\n".join(out)


def fcurves_of(action, obj=None):
    """F-curves of an action in both the legacy (<4.4) and the slotted/layered (4.4+, 5.x) API."""
    legacy = getattr(action, "fcurves", None)
    if legacy is not None and len(legacy) > 0:
        return list(legacy)
    curves = []
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            slots = list(action.slots)
            if obj is not None and obj.animation_data and obj.animation_data.action_slot:
                slots = [obj.animation_data.action_slot]
            for slot in slots:
                bag = strip.channelbag(slot) if hasattr(strip, "channelbag") else None
                if bag is not None:
                    curves.extend(bag.fcurves)
    return curves


def mesh_stats(obj):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    try:
        triangles = sum(len(p.vertices) - 2 for p in mesh.polygons)
        edge_faces = {}
        for poly in mesh.polygons:
            for key in poly.edge_keys:
                edge_faces[key] = edge_faces.get(key, 0) + 1
        open_edges = sum(1 for key in (tuple(sorted(e.vertices)) for e in mesh.edges) if edge_faces.get(key, 0) != 2)
        has_uv = len(mesh.uv_layers) > 0
    finally:
        evaluated.to_mesh_clear()
    return triangles, open_edges, has_uv


def check_scene(report, mode):
    scene = bpy.context.scene
    units = scene.unit_settings
    if units.system != "NONE":
        report.add("WARN", "scene", f"Unit System is {units.system}; set it to None so 1 Blender unit = 1 stud")
    if units.system_rotation != "DEGREES":
        report.add("WARN", "scene", "Rotation units should be Degrees")
    fps = scene.render.fps / scene.render.fps_base
    if mode == "animation":
        if fps < 30:
            report.add("ERROR", "scene", f"{fps:g} FPS; animate at 30 FPS (at least 30) for Roblox")
        elif abs(fps - 30) > 0.01:
            report.add("WARN", "scene", f"{fps:g} FPS; Studio aligns keys to 30 FPS and warns about other rates")


def check_meshes(report, mode):
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or not obj.visible_get():
            continue
        triangles, open_edges, has_uv = mesh_stats(obj)
        where = f"mesh {obj.name}"
        if triangles > MAX_TRIANGLES:
            report.add("ERROR", where, f"{triangles} triangles; a Roblox mesh can't exceed {MAX_TRIANGLES} (decimate or split)")
        if open_edges:
            report.add("WARN", where, f"{open_edges} open/non-manifold edges; Roblox meshes should be watertight")
        if any(abs(s - 1) > 1e-4 for s in obj.scale) and not obj.find_armature():
            report.add("WARN", where, f"unapplied scale {tuple(round(s, 3) for s in obj.scale)}; apply it (Ctrl+A) before export")
        if obj.find_armature() and (any(abs(s - 1) > 1e-4 for s in obj.scale) or any(abs(r) > 1e-4 for r in obj.rotation_euler)):
            report.add("ERROR", where, "skinned mesh has transforms; meshes must have zero transforms and scale 1 before skinning")
        materials = [slot.material for slot in obj.material_slots if slot.material]
        if len(materials) > 1:
            report.add("WARN", where, f"{len(materials)} materials; Roblox imports one material per MeshPart (split it or use one texture)")
        if materials and not has_uv:
            report.add("WARN", where, "has a material but no UV map")
        report.add("INFO", where, f"{triangles} triangles")


def looks_like_r15(armature):
    names = {bone.name for bone in armature.data.bones}
    return len(names & set(R15_PARENTS)) >= 8


def check_rig(report, armature):
    where = f"armature {armature.name}"
    bones = {bone.name: bone for bone in armature.data.bones}
    if any(abs(s - 1) > 1e-4 for s in armature.scale):
        report.add("ERROR", where, f"armature object scale {tuple(round(s, 3) for s in armature.scale)}; skeletons must have scale 1")
    leaf = [name for name in bones if name.lower().endswith("_end")]
    if leaf:
        report.add("WARN", where, f"leaf bones {leaf[:4]}; disable Add Leaf Bones on export")
    if not looks_like_r15(armature):
        report.add("INFO", where, "not an R15 naming scheme: treated as a custom rig (import as Custom; Adaptive Animation can map it to R15)")
        return
    root = next((name for name in ROOT_NAMES if name in bones), None)
    if root is None:
        report.add("ERROR", where, "no HumanoidRootNode (or HumanoidRootPart) bone")
    for name, parent in R15_PARENTS.items():
        bone = bones.get(name)
        if bone is None:
            report.add("ERROR", where, f"missing R15 bone {name}")
            continue
        expected = root if parent == "HumanoidRootNode" else parent
        actual = bone.parent.name if bone.parent else None
        if expected and actual != expected:
            report.add("ERROR", where, f"{name} is parented to {actual}, R15 needs {expected}")


def check_animation(report, armature):
    where = f"animation on {armature.name}"
    data = armature.animation_data
    action = data.action if data else None
    if action is None:
        report.add("ERROR", where, "no action assigned; nothing to export")
        return
    curves = fcurves_of(action, armature)
    if not curves:
        report.add("ERROR", f"action {action.name}", "has no keyframes")
        return
    start, end = action.frame_range
    fps = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base
    length = (end - start) / fps
    report.add("INFO", f"action {action.name}", f"frames {start:g}-{end:g} ({length:.2f} s at {fps:g} FPS), {len(curves)} curves")
    for name in ROOT_NAMES:
        bone = armature.pose.bones.get(name)
        if bone is None:
            continue
        travel = 0.0
        for curve in curves:
            if curve.data_path == f'pose.bones["{name}"].location':
                values = [point.co[1] for point in curve.keyframe_points]
                if values:
                    travel = max(travel, max(values) - min(values))
        if travel > ROOT_TRAVEL_LIMIT:
            report.add("ERROR", f"action {action.name}", f"{name} travels {travel:.2f} units; Roblox avatar animations play in place: key the root at a fixed position (move the character in code)")


def check(mode=MODE):
    report = Report()
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    if mode == "auto":
        mode = "animation" if any(a.animation_data and a.animation_data.action for a in armatures) else "model"
    report.add("INFO", "check", f"mode {mode}, Blender {bpy.app.version_string}")
    check_scene(report, mode)
    check_meshes(report, mode)
    for armature in armatures:
        check_rig(report, armature)
        if mode == "animation":
            check_animation(report, armature)
    if mode == "animation" and not armatures:
        report.add("ERROR", "scene", "animation mode but no armature")
    return report, mode


def export_fbx(path, mode, selected_only=False):
    """FBX export with the settings Roblox documents for Blender."""
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=selected_only,
        path_mode="COPY",
        embed_textures=True,
        apply_scale_options="FBX_SCALE_UNITS",
        add_leaf_bones=False,
        bake_anim=(mode == "animation"),
        axis_forward="Z",
        axis_up="Y",
    )
    return path


def main():
    mode, export_path = MODE, EXPORT_PATH
    if "--" in sys.argv:
        args = sys.argv[sys.argv.index("--") + 1 :]
        for i, arg in enumerate(args):
            if arg == "--mode" and i + 1 < len(args):
                mode = args[i + 1]
            elif arg == "--export" and i + 1 < len(args):
                export_path = args[i + 1]
    report, mode = check(mode)
    print(report.text())
    if export_path:
        if report.count("ERROR"):
            print(f"not exported: fix the errors first ({export_path})")
        else:
            print(f"exported {export_fbx(export_path, mode)}")
    return report


# Runs on `blender --python` and when pasted into an MCP code tool; tests load the module with
# ROBLOX_CHECK_IMPORT = True to call check()/export_fbx() themselves.
if not globals().get("ROBLOX_CHECK_IMPORT"):
    RESULT = main()
