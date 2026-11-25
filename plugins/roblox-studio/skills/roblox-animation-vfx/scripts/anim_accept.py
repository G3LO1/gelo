"""Acceptance checks for retargeted animations, run in Blender on the same animations.json that
anim_manifest.py validates. One repeatable pass per animation and rig, frame by frame:

  feet     grounded clips keep a foot on the floor on every frame (no floating, no sinking);
           a planted foot moves backwards at the speed the game moves the character (in-place
           clips: `speed` = WalkSpeed, 0 for idles), otherwise the feet slide
  root     HumanoidRootNode/Part stays in place (Roblox avatar animations play in place)
  grip     the hand stays on the prop's grip point (props that fly out of the hand)
  clip     the prop doesn't go through the body (every frame, every body part but the holding hand)
  loop     looped clips end on the pose they start with (no pop when they wrap)
  markers  every marker the manifest lists is on the action, with its time for re-adding after import
  R6       when the project ships R15 and R6 ("rigs": ["R15", "R6"]), the R6 version (action
           "<Name>_R6") passes the same checks and matches the R15 one in length and marker frames

Run it on a .blend that holds the rigs and actions (actions named like the manifest entries):
  blender -b scene.blend --python anim_accept.py -- animations.json [--only Walk,Chop] [--json report.json]
  python anim_accept.py animations.json scene.blend [...]     (a Python with the `bpy` module)
  Blender MCP code tool: set MANIFEST below and send the file (it checks the open scene).
Exit code 1 when any check fails. It never changes or saves the .blend.

animations.json additions (all optional; anim_manifest.py validates them):
  "rigs": ["R15", "R6"]                       project ships both rigs (R6 ids go in "idR6")
  "accept": { "floorTolerance": 0.1, "slideTolerance": 1.5, "rootTravel": 0.05, "gripGap": 0.15,
              "loopTolerance": 3 }            defaults for every animation (studs, studs/s, degrees)
  per animation "accept": {
    "grounded": true,                         at least one foot on the floor on every frame
    "speed": 16,                              studs/s the game moves the character while it plays
    "rootMotion": false,                      true allows the root to travel
    "prop": "Katana", "grips": { "RightHand": "Grip" },   prop object, hand bone -> grip Empty
    "ignore": ["RightLowerArm"]               extra body parts the prop may touch
  }
The grip point is an Empty parented to the prop and named "<prop>.<point>" or "<point>" (e.g. the
Grip point from model_batch.py). With both rigs in one file the R6 rig holds "<prop>_R6". Body parts are the meshes that follow the rig (bone-parented or
skinned). The floor is where the feet are in the rest pose.
"""

import json
import math
import os
import sys

import bpy  # first: with the bpy module from PyPI, mathutils only exists after it

from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

MANIFEST = None  # set when pasting into a Blender MCP code tool

DEFAULTS = {"floorTolerance": 0.1, "slideTolerance": 1.5, "rootTravel": 0.05, "gripGap": 0.15, "loopTolerance": 3.0}
ROOTS = ("HumanoidRootNode", "HumanoidRootPart")
RIG_PARTS = {
    "R15": {"feet": ("LeftFoot", "RightFoot"), "hands": ("LeftHand", "RightHand"), "arms": {"LeftHand": "LeftLowerArm", "RightHand": "RightLowerArm"}},
    "R6": {"feet": ("Left Leg", "Right Leg"), "hands": ("Left Arm", "Right Arm"), "arms": {}},
}
R6_BONES = {"Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg"}
# R15 hand names map to R6 limbs, so one manifest works for both rigs
R6_NAME = {"RightHand": "Right Arm", "LeftHand": "Left Arm", "RightFoot": "Right Leg", "LeftFoot": "Left Leg"}


class Report:
    def __init__(self):
        self.lines = []

    def add(self, level, where, message):
        self.lines.append((level, where, message))

    def count(self, level):
        return sum(1 for line in self.lines if line[0] == level)


def ranges(frames):
    """[3, 4, 5, 9] -> '3-5, 9'"""
    out, start, prev = [], None, None
    for f in sorted(frames):
        if start is None:
            start = prev = f
        elif f == prev + 1:
            prev = f
        else:
            out.append(f"{start}-{prev}" if prev != start else f"{start}")
            start = prev = f
    if start is not None:
        out.append(f"{start}-{prev}" if prev != start else f"{start}")
    return ", ".join(out)


def rig_kind(armature):
    names = {b.name for b in armature.data.bones}
    if len(names & {"LowerTorso", "UpperTorso", "LeftUpperArm", "RightUpperLeg", "LeftFoot", "RightHand"}) >= 5:
        return "R15"
    if len(names & R6_BONES) >= 5:
        return "R6"
    return None


def find_rigs():
    rigs = {}
    for obj in bpy.context.scene.objects:
        if obj.type == "ARMATURE":
            kind = rig_kind(obj)
            if kind and kind not in rigs:
                rigs[kind] = obj
    return rigs


def low_end(armature, bone_name):
    """Which end of a bone touches the floor in the rest pose: ('head'|'tail', world z)."""
    bone = armature.data.bones[bone_name]
    head = (armature.matrix_world @ bone.head_local).z
    tail = (armature.matrix_world @ bone.tail_local).z
    return ("head", head) if head <= tail else ("tail", tail)


def bone_point(armature, bone_name, end):
    pose = armature.pose.bones[bone_name]
    return armature.matrix_world @ (pose.head if end == "head" else pose.tail)


def body_parts(armature, prop):
    """Meshes that follow the rig: parented to a bone or deformed by it. name -> object."""
    parts = {}
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or obj == prop or (prop and obj.parent == prop):
            continue
        if obj.parent == armature and obj.parent_type == "BONE":
            parts[obj.parent_bone] = obj
        elif obj.find_armature() == armature:
            parts[obj.name] = obj
    return parts


def world_bvh(obj, depsgraph):
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    try:
        matrix = evaluated.matrix_world
        verts = [matrix @ v.co for v in mesh.vertices]
        polys = [tuple(p.vertices) for p in mesh.polygons]
    finally:
        evaluated.to_mesh_clear()
    return BVHTree.FromPolygons(verts, polys)


def grip_point(prop, point):
    for child in bpy.context.scene.objects:
        if child.type == "EMPTY" and child.parent == prop and child.name in (f"{prop.name}.{point}", point):
            return child
    return None


def find_action(name):
    return bpy.data.actions.get(name)


def assign(armature, action):
    data = armature.animation_data or armature.animation_data_create()
    data.action = action
    if hasattr(data, "action_slot") and data.action_slot is None and getattr(action, "slots", None):
        data.action_slot = action.slots[0]


def pose_angles(armature):
    out = {}
    for pose in armature.pose.bones:
        out[pose.name] = (pose.matrix_basis.to_quaternion(), pose.matrix_basis.to_translation())
    return out


def markers_of(action, scene):
    found = {m.name: m.frame for m in getattr(action, "pose_markers", [])}
    for m in scene.timeline_markers:
        found.setdefault(m.name, m.frame)
    return found


def check_clip(entry, settings, rig, armature, action, report):
    """Runs every check for one animation on one rig. Returns facts for the R15/R6 comparison."""
    scene = bpy.context.scene
    name = entry["name"]
    where = f"{name} [{rig}]"
    fps = scene.render.fps / scene.render.fps_base
    start, end = (int(round(v)) for v in action.frame_range)
    assign(armature, action)
    frames = list(range(start, end + 1))
    parts = RIG_PARTS[rig]
    accept = {**settings, **(entry.get("accept") or {})}
    facts = {"frames": end - start, "markers": {}, "contacts": {}}
    report.add("INFO", where, f"frames {start}-{end} ({(end - start) / fps:.2f} s at {fps:g} FPS)")

    feet = {foot: low_end(armature, foot) for foot in parts["feet"] if foot in armature.pose.bones}
    root = next((r for r in ROOTS if r in armature.pose.bones), None)
    prop = None
    if accept.get("prop"):  # the R6 rig holds its own copy, "<prop>_R6", when both rigs share a file
        prop = (bpy.data.objects.get(f"{accept['prop']}_{rig}") if rig != "R15" else None) or bpy.data.objects.get(accept["prop"])
    if accept.get("prop") and prop is None:
        report.add("FAIL", where, f"prop object {accept['prop']} not in the scene")
    grips = {}
    for hand, point in (accept.get("grips") or {}).items():
        bone = hand if rig == "R15" else R6_NAME.get(hand, hand)
        empty = grip_point(prop, point) if prop else None
        if bone not in armature.pose.bones:
            report.add("FAIL", where, f"grip hand {bone} is not a bone of the rig")
        elif prop and empty is None:
            report.add("FAIL", where, f"no grip point '{point}' on {prop.name} (an Empty parented to it)")
        elif empty:
            grips[bone] = empty
    ignore = set(grips) | {parts["arms"].get(h) for h in grips} | set(accept.get("ignore") or [])
    ignore |= {R6_NAME.get(n, n) for n in accept.get("ignore") or []} if rig == "R6" else set()
    bodies = {n: o for n, o in body_parts(armature, prop).items() if n not in ignore} if prop else {}
    if prop and not bodies:
        report.add("INFO", where, "no body part meshes on the rig: prop clipping not checked (parent the character's parts to its bones)")

    contact_frames = {foot: [] for foot in feet}
    heights, floating, sinking, grip_gaps, clipping, root_xy = {}, [], [], {}, {}, []
    foot_xy = {foot: {} for foot in feet}
    for frame in frames:
        scene.frame_set(frame)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        down = []
        for foot, (end_name, rest_z) in feet.items():
            p = bone_point(armature, foot, end_name)
            dz = p.z - rest_z
            heights.setdefault(foot, []).append(dz)
            foot_xy[foot][frame] = (p.x, p.y)
            if abs(dz) <= accept["floorTolerance"]:
                contact_frames[foot].append(frame)
                down.append(foot)
            elif dz < -accept["floorTolerance"]:
                sinking.append(frame)
        if accept.get("grounded") and feet and not down and not any(h[-1] < -accept["floorTolerance"] for h in heights.values()):
            floating.append(frame)  # no foot on the floor and none below it: the body floats
        if root:
            p = armature.matrix_world @ armature.pose.bones[root].head
            root_xy.append((p.x, p.y))
        for bone, empty in grips.items():
            gap = (bone_point(armature, bone, "tail") - empty.matrix_world.translation).length
            if gap > accept["gripGap"]:
                grip_gaps.setdefault(bone, {})[frame] = gap
        if prop and bodies:
            prop_tree = world_bvh(prop, depsgraph)
            for part, obj in bodies.items():
                if prop_tree.overlap(world_bvh(obj, depsgraph)):
                    clipping.setdefault(part, []).append(frame)

    # feet on the floor
    if accept.get("grounded"):
        if floating:
            worst = max(min(h[i] for h in heights.values()) for i in range(len(frames)) if frames[i] in floating)
            report.add("FAIL", where, f"no foot on the floor on frames {ranges(floating)} (lowest foot {worst:.2f} studs up): feet float")
        if sinking:
            worst = min(min(h) for h in heights.values())
            report.add("FAIL", where, f"a foot sinks into the floor on frames {ranges(sorted(set(sinking)))} ({-worst:.2f} studs down)")
        if not floating and not sinking:
            report.add("PASS", where, "feet: a foot on the floor on every frame, none below it")
    # sliding: while planted, a foot must move back at the game's speed
    speed = float(accept.get("speed", 0))
    slides = []
    for foot, planted in contact_frames.items():
        facts["contacts"][foot] = len(planted) / max(1, len(frames))
        for a, b in zip(planted, planted[1:]):
            if b != a + 1:
                continue
            (x0, y0), (x1, y1) = foot_xy[foot][a], foot_xy[foot][b]
            moved = math.hypot(x1 - x0, y1 - y0) * fps
            if abs(moved - speed) > accept["slideTolerance"]:
                slides.append((foot, a, moved))
    if accept.get("grounded") or "speed" in (entry.get("accept") or {}):
        if slides:
            foot, frame, moved = max(slides, key=lambda s: abs(s[2] - speed))
            report.add("FAIL", where, f"planted feet slide on {len(slides)} frame step(s): {foot} moves {moved:.1f} studs/s at frame {frame}, the character moves {speed:g} (accept.speed)")
        else:
            report.add("PASS", where, f"planted feet move at {speed:g} studs/s (no sliding)")
    # root in place
    if root and root_xy and not accept.get("rootMotion"):
        travel = max(math.hypot(x - root_xy[0][0], y - root_xy[0][1]) for x, y in root_xy)
        if travel > accept["rootTravel"]:
            report.add("FAIL", where, f"{root} travels {travel:.2f} studs; Roblox plays avatar animations in place (move the character in code, set accept.rootMotion for non-avatar rigs)")
        else:
            report.add("PASS", where, f"root in place ({travel:.3f} studs)")
    # grip
    for bone in grips:
        gaps = grip_gaps.get(bone, {})
        if gaps:
            report.add("FAIL", where, f"{prop.name} leaves {bone} on frames {ranges(gaps)} (up to {max(gaps.values()):.2f} studs from its grip)")
        else:
            report.add("PASS", where, f"{bone} stays on the {prop.name} grip (within {accept['gripGap']:g} studs)")
    # clipping
    if prop and bodies:
        if clipping:
            worst = max(clipping, key=lambda p: len(clipping[p]))
            total = sorted({f for fs in clipping.values() for f in fs})
            detail = "; ".join(f"{p} {ranges(fs)}" for p, fs in sorted(clipping.items()))
            report.add("FAIL", where, f"{prop.name} goes through the body on {len(total)} frame(s): {detail} (worst: {worst})")
        else:
            report.add("PASS", where, f"{prop.name} stays out of the body on all {len(frames)} frames")
    # loop
    if entry.get("looped"):
        scene.frame_set(start)
        first = pose_angles(armature)
        scene.frame_set(end)
        last = pose_angles(armature)
        turned = max(((math.degrees(first[b][0].rotation_difference(last[b][0]).angle), b) for b in first), default=(0.0, None))
        moved = max((((last[b][1] - first[b][1]).length, b) for b in first), default=(0.0, None))
        if turned[0] > accept["loopTolerance"]:
            report.add("FAIL", where, f"pops when it loops: {turned[1]} turns {turned[0]:.0f} deg between frame {start} and {end} (end on the first pose)")
        elif moved[0] > 0.02:
            report.add("FAIL", where, f"pops when it loops: {moved[1]} is {moved[0]:.2f} studs off between frame {start} and {end}")
        else:
            report.add("PASS", where, "loop closes (last pose = first pose)")
    # markers
    found = markers_of(action, scene)
    for marker in entry.get("markers") or []:
        if marker in found:
            frame = found[marker]
            facts["markers"][marker] = frame
            if not start <= frame <= end:
                report.add("FAIL", where, f"marker {marker} at frame {frame} is outside the clip ({start}-{end})")
            else:
                report.add("PASS", where, f"marker {marker} at frame {frame} ({(frame - start) / fps:.2f} s): after import, check it in the events track or with AnimCheck.luau")
        else:
            report.add("FAIL", where, f"marker {marker} from the manifest is not on the action (add a pose marker at the {marker} frame)")
    return facts


def compare(entry, r15, r6, report):
    where = f"{entry['name']} [R15 vs R6]"
    problems = 0
    if r15["frames"] != r6["frames"]:
        report.add("WARN", where, f"lengths differ: R15 {r15['frames']} frames, R6 {r6['frames']} (gameplay timing should match)")
        problems += 1
    for marker, frame in r15["markers"].items():
        other = r6["markers"].get(marker)
        if other is not None and abs(other - frame) > 1:
            report.add("WARN", where, f"marker {marker}: R15 frame {frame}, R6 frame {other}")
            problems += 1
    if not problems:
        report.add("PASS", where, "same length and marker frames on both rigs")


def load_manifest(path):
    with open(path, encoding="utf-8") as f:
        manifest = json.load(f)
    rigs = manifest.get("rigs") or [manifest.get("rig", "R15")]
    settings = {**DEFAULTS, **(manifest.get("accept") or {})}
    return manifest, rigs, settings


def run(manifest_path, only=None):
    manifest, rigs, settings = load_manifest(manifest_path)
    report = Report()
    scene_rigs = find_rigs()
    for rig in rigs:
        if rig in ("R15", "R6") and rig not in scene_rigs:
            report.add("FAIL", "scene", f"the project ships {rig} but the scene has no {rig} armature")
    for entry in manifest.get("animations", []):
        name = entry.get("name")
        if entry.get("graph") or (only and name not in only):
            continue
        facts = {}
        for rig in rigs:
            if rig not in scene_rigs:
                continue
            action = find_action(name if rig == rigs[0] else f"{name}_{rig}") or (find_action(name) if rig == rigs[0] else None)
            if action is None:
                level = "FAIL" if rig != rigs[0] or entry.get("accept") else "INFO"
                report.add(level, f"{name} [{rig}]", f"no action '{name if rig == rigs[0] else f'{name}_{rig}'}' in the file (name it like the manifest; Blender drops actions with no users on save: turn on Fake User)")
                continue
            facts[rig] = check_clip(entry, settings, rig, scene_rigs[rig], action, report)
        if "R15" in facts and "R6" in facts:
            compare(entry, facts["R15"], facts["R6"], report)
    return report


def main(argv):
    args = argv[argv.index("--") + 1 :] if "--" in argv else argv[1:]
    manifest, only, json_out, blend = MANIFEST, None, None, None
    i = 0
    while i < len(args):
        if args[i] == "--only" and i + 1 < len(args):
            only = [n.strip() for n in args[i + 1].split(",")]
            i += 1
        elif args[i] == "--json" and i + 1 < len(args):
            json_out = args[i + 1]
            i += 1
        elif args[i].endswith(".blend"):
            blend = args[i]
        elif not args[i].startswith("--"):
            manifest = args[i]
        i += 1
    if not manifest:
        print(__doc__)
        return 2
    if blend:
        bpy.ops.wm.open_mainfile(filepath=blend)
    report = run(manifest, only)
    for level, where, message in report.lines:
        print(f"{level:5} {where}: {message}")
    print(f"{report.count('PASS')} passed, {report.count('FAIL')} failed, {report.count('WARN')} warning(s)")
    if json_out:
        with open(json_out, "w", encoding="utf-8") as f:
            json.dump([{"level": l, "where": w, "message": m} for l, w, m in report.lines], f, indent=1)
    return 1 if report.count("FAIL") else 0


# Runs on `blender -b --python`, `python anim_accept.py` and when pasted into an MCP code tool
# (no exit there). Tests set ANIM_ACCEPT_IMPORT = True and call run().
if not globals().get("ANIM_ACCEPT_IMPORT"):
    EXIT_CODE = main(sys.argv)
    if bpy.app.background:
        sys.exit(EXIT_CODE)
