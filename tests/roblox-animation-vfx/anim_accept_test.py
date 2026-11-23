"""anim_accept.py against real Blender (the `bpy` module) on the example manifest
(assets/examples/animations.json): R15 and R6 rigs with rigid box parts on their bones (like Roblox
parts), an in-place Walk solved with two-bone IK so the planted foot moves back at the game's speed
(ground contact) and a Chop with a katana in the right hand (prop). The clean scene passes; each
broken variant breaks one thing and must be reported: feet floating or sinking, sliding, root travel,
a loop pop, the prop leaving the hand, the blade through the body, a missing marker, R15/R6 drift,
a missing R6 rig. Also runs the command line in a fresh interpreter on a saved .blend.
Usage: python anim_accept_test.py <anim_accept.py> <examples/animations.json> <tmp dir>"""
import json
import math
import os
import subprocess
import sys

import bpy
from mathutils import Matrix, Vector

accept_path, example, tmp = sys.argv[1], sys.argv[2], sys.argv[3]
namespace = {"ANIM_ACCEPT_IMPORT": True, "__name__": "anim_accept"}
exec(compile(open(accept_path).read(), accept_path, "exec"), namespace)
run = namespace["run"]

passed = failed = 0


def ok(condition, message, report=None):
    global passed, failed
    passed += bool(condition)
    failed += not condition
    print(f"  {'ok  ' if condition else 'FAIL'} {message}")
    if not condition and report:
        for line in report.lines:
            print(f"       {line[0]:5} {line[1]}: {line[2]}")


def has(report, level, needle):
    return any(l == level and needle in f"{w}: {m}" for l, w, m in report.lines)


R15 = [  # name, head, tail, parent (rest pose stands on the floor z = 0, faces -Y)
    ("HumanoidRootNode", (0, 0, 2.0), (0, 0, 2.5), None),
    ("LowerTorso", (0, 0, 2.0), (0, 0, 2.6), "HumanoidRootNode"),
    ("UpperTorso", (0, 0, 2.6), (0, 0, 3.8), "LowerTorso"),
    ("Head", (0, 0, 3.8), (0, 0, 4.8), "UpperTorso"),
    ("LeftUpperArm", (1.5, 0, 3.8), (1.5, 0, 3.0), "UpperTorso"),
    ("LeftLowerArm", (1.5, 0, 3.0), (1.5, 0, 2.3), "LeftUpperArm"),
    ("LeftHand", (1.5, 0, 2.3), (1.5, 0, 1.9), "LeftLowerArm"),
    ("RightUpperArm", (-1.5, 0, 3.8), (-1.5, 0, 3.0), "UpperTorso"),
    ("RightLowerArm", (-1.5, 0, 3.0), (-1.5, 0, 2.3), "RightUpperArm"),
    ("RightHand", (-1.5, 0, 2.3), (-1.5, 0, 1.9), "RightLowerArm"),
    ("LeftUpperLeg", (0.5, 0, 2.0), (0.5, 0, 1.0), "LowerTorso"),
    ("LeftLowerLeg", (0.5, 0, 1.0), (0.5, 0, 0.3), "LeftUpperLeg"),
    ("LeftFoot", (0.5, 0, 0.3), (0.5, 0, 0.0), "LeftLowerLeg"),
    ("RightUpperLeg", (-0.5, 0, 2.0), (-0.5, 0, 1.0), "LowerTorso"),
    ("RightLowerLeg", (-0.5, 0, 1.0), (-0.5, 0, 0.3), "RightUpperLeg"),
    ("RightFoot", (-0.5, 0, 0.3), (-0.5, 0, 0.0), "RightLowerLeg"),
]
R6 = [
    ("HumanoidRootPart", (0, 0, 2.0), (0, 0, 2.5), None),
    ("Torso", (0, 0, 2.0), (0, 0, 4.0), "HumanoidRootPart"),
    ("Head", (0, 0, 4.0), (0, 0, 5.0), "Torso"),
    ("Left Arm", (1.5, 0, 3.8), (1.5, 0, 1.8), "Torso"),
    ("Right Arm", (-1.5, 0, 3.8), (-1.5, 0, 1.8), "Torso"),
    ("Left Leg", (0.5, 0, 2.0), (0.5, 0, 0.0), "Torso"),
    ("Right Leg", (-0.5, 0, 2.0), (-0.5, 0, 0.0), "Torso"),
]
WIDTH = {"LowerTorso": 2, "UpperTorso": 2, "Torso": 2, "Head": 1}


def update():
    bpy.context.view_layer.update()


def make_rig(name, bones, offset):
    data = bpy.data.armatures.new(name)
    rig = bpy.data.objects.new(name, data)
    rig.location = offset
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for bone_name, head, tail, parent in bones:
        bone = data.edit_bones.new(bone_name)
        bone.head, bone.tail, bone.roll = head, tail, 0
        if parent:
            bone.parent = made[parent]
        made[bone_name] = bone
    bpy.ops.object.mode_set(mode="OBJECT")
    update()
    for bone_name, head, tail, parent in bones:  # one rigid box part per bone (not the root)
        if parent is None:
            continue
        low, high = Vector(head), Vector(tail)
        width = WIDTH.get(bone_name, 1)
        size = Vector((width, 1, abs(high.z - low.z)))
        if "Foot" in bone_name:
            size = Vector((1, 1, 0.3))
        center = (low + high) / 2 + Vector(offset)
        attach(box(f"{name}_{bone_name}", center, size), rig, bone_name)
    return rig


def box(name, center, size, direction=None):
    mesh = bpy.data.meshes.new(name)
    hx, hy, hz = (s / 2 for s in size)
    verts = [(x, y, z) for x in (-hx, hx) for y in (-hy, hy) for z in (-hz, hz)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    mesh.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    rotation = Vector((0, 1, 0)).rotation_difference(direction).to_matrix().to_4x4() if direction else Matrix.Identity(4)
    obj.matrix_world = Matrix.Translation(center) @ rotation
    return obj


def attach(obj, rig, bone):
    world = obj.matrix_world.copy()
    obj.parent, obj.parent_type, obj.parent_bone = rig, "BONE", bone
    update()
    obj.matrix_world = world


def make_prop(name, rig, hand, grip, direction):
    """A katana: 0.3 studs of handle behind the grip, 4 studs of blade along `direction`."""
    d = Vector(direction).normalized()
    center = Vector(grip) + d * (4 - 0.3) / 2
    sword = box(name, center, (0.1, 4.3, 0.25), d)
    empty = bpy.data.objects.new(f"{name}.Grip", None)
    bpy.context.scene.collection.objects.link(empty)
    empty.matrix_world = Matrix.Translation(grip)
    empty.parent = sword
    update()
    empty.matrix_world = Matrix.Translation(grip)
    attach(sword, rig, hand)
    return sword


def pose(rig, bone, direction=None, head=None):
    """Points a bone along `direction` (armature space) with its head at `head`, then keys it."""
    pb = rig.pose.bones[bone]
    rest = rig.data.bones[bone]
    rest_dir = (rest.tail_local - rest.head_local).normalized()
    turn = rest_dir.rotation_difference(Vector(direction)) if direction else Matrix.Identity(3).to_quaternion()
    pb.matrix = Matrix.Translation(Vector(head) if head is not None else pb.head) @ turn.to_matrix().to_4x4() @ rest.matrix_local.to_3x3().to_4x4()
    update()


def key(rig, bones, frame):
    for bone in bones:
        pb = rig.pose.bones[bone]
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)


def new_action(rig, name):
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    update()
    rig.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True  # kept in the .blend while another action is on the rig
    rig.animation_data.action = action
    return action


def foot_target(c):
    """In-place walk, 24-frame cycle: stance 12 frames moving back 1.2 studs (3 studs/s at 30 FPS),
    swing 12 frames lifting up to 0.35 studs."""
    if c <= 12:
        return -0.6 + 1.2 * c / 12, 0.3
    u = (c - 12) / 12
    return 0.6 - 1.2 * u, 0.3 + 0.35 * math.sqrt(math.sin(math.pi * u))


def solve_knee(hip, ankle, l1=1.0, l2=0.7):
    d = ankle - hip
    dist = min(d.length, l1 + l2 - 1e-6)
    alpha = math.acos(max(-1, min(1, (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist))))
    base = d.normalized()
    best = None
    for sign in (1, -1):  # knee forward = smaller y
        rot = Matrix.Rotation(sign * alpha, 3, "X")
        knee = hip + rot @ base * l1
        if best is None or knee.y < best.y:
            best = knee
    return best


def walk_r15(rig, root_offset=lambda f: Vector(), pop_last=False):
    action = new_action(rig, "Walk")
    for frame in range(1, 26):
        c = (frame - 1) % 24
        pose(rig, "HumanoidRootNode", head=(0, 0, 1.85))
        for side, x, phase in (("Left", 0.5, c), ("Right", -0.5, (c + 12) % 24)):
            y, z = foot_target(phase)
            hip = rig.pose.bones[f"{side}UpperLeg"].head.copy()
            ankle = Vector((x, y, z))
            knee = solve_knee(hip, ankle)
            pose(rig, f"{side}UpperLeg", knee - hip)
            pose(rig, f"{side}LowerLeg", ankle - knee)
            pose(rig, f"{side}Foot", (0, 0, -1))
        key(rig, [b for b in rig.pose.bones.keys() if "Leg" in b or "Foot" in b], frame)
        pose(rig, "HumanoidRootNode", head=Vector((0, 0, 1.85)) + root_offset(frame))
        key(rig, ["HumanoidRootNode"], frame)
        if pop_last and frame == 25:
            pose(rig, "RightUpperArm", (0, -0.64, -0.77))
            key(rig, ["RightUpperArm"], frame)
        elif pop_last:
            key(rig, ["RightUpperArm"], frame)
    for name, frame in (("Footstep", 1), ("Footstep", 13)):
        action.pose_markers.new(name).frame = frame
    return action


def walk_r6(rig):
    action = new_action(rig, "Walk_R6")
    for frame in range(1, 26):
        c = (frame - 1) % 24
        for side, sign, phase in (("Left", -1, c), ("Right", 1, (c + 12) % 24)):
            y, _ = foot_target(phase)
            theta = math.asin(y / 2)  # one-bone leg: no knee, so it can only swing
            leg = Vector((0, math.sin(theta), -math.cos(theta)))
            if phase > 12:  # swing: lift the foot by turning the leg out (no knee to bend)
                beta = math.radians(30) * math.sqrt(math.sin(math.pi * (phase - 12) / 12))
                leg = Matrix.Rotation(sign * beta, 3, "Y") @ leg
            pose(rig, f"{side} Leg", leg)
        key(rig, ["Left Leg", "Right Leg"], frame)
    for name, frame in (("Footstep", 1), ("Footstep", 13)):
        action.pose_markers.new(name).frame = frame
    return action


def chop(rig, arm, name, last=21, hit=12, end_swing=16):
    action = new_action(rig, name)
    for frame in range(1, last + 1):
        phi = math.radians(-170 + 160 * min(1, (frame - 1) / (end_swing - 1)))
        pose(rig, arm, (0, math.sin(phi), -math.cos(phi)))
        key(rig, [arm], frame)
    action.pose_markers.new("Hit").frame = hit
    return action


def build(r6=True, float_by=0.0, root_travel=False, pop=False, blade=(0, -1, 0), grip_slip=False, hit_marker=True, r6_short=False):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps, scene.render.fps_base = 30, 1
    scene.unit_settings.system = "NONE"
    r15 = make_rig("R15", R15, (0, 0, 0))
    katana = make_prop("Katana", r15, "RightHand", (-1.5, 0, 1.9), blade)
    offset = lambda f: Vector((0, 2.0 * (f - 1) / 24 if root_travel else 0, float_by))
    walk_r15(r15, offset, pop)
    action = chop(r15, "RightUpperArm", "Chop")
    if not hit_marker:
        action.pose_markers.remove(action.pose_markers["Hit"])
    if grip_slip:
        katana.animation_data_create()
        base = katana.location.copy()
        for frame, shift in ((1, 0), (7, 0), (8, 1.2), (12, 1.2), (13, 0)):
            katana.location = base + Vector((shift, 0, 0))
            katana.keyframe_insert("location", frame=frame)
    if r6:
        rig6 = make_rig("R6", R6, (10, 0, 0))
        make_prop("Katana_R6", rig6, "Right Arm", (8.5, 0, 1.8), (0, -1, 0))
        walk_r6(rig6)
        if r6_short:
            chop(rig6, "Right Arm", "Chop_R6", last=19, hit=14, end_swing=14)
        else:
            chop(rig6, "Right Arm", "Chop_R6")
    return scene


def manifest_with(path, **accept):
    data = json.load(open(example))
    for anim in data["animations"]:
        anim.setdefault("accept", {}).update(accept.get(anim["name"], {}))
    json.dump(data, open(path, "w"), indent=1)
    return path


os.makedirs(tmp, exist_ok=True)

print("clean scene: R15 + R6, Walk (ground contact) and Chop (katana)")
build()
report = run(example)
ok(report.count("FAIL") == 0 and report.count("WARN") == 0, f"everything passes ({report.count('PASS')} checks)", report)
for rig in ("R15", "R6"):
    ok(has(report, "PASS", f"Walk [{rig}]: feet: a foot on the floor on every frame"), f"{rig} Walk keeps a foot on the floor", report)
    ok(has(report, "PASS", f"Walk [{rig}]: planted feet move at 3 studs/s"), f"{rig} Walk planted feet move at the game's speed", report)
    ok(has(report, "PASS", f"Walk [{rig}]: loop closes"), f"{rig} Walk loop closes", report)
    ok(has(report, "PASS", f"Chop [{rig}]: Katana stays out of the body") or has(report, "PASS", f"Chop [{rig}]: Katana_R6 stays out of the body"), f"{rig} Chop: katana never inside the body", report)
    ok(has(report, "PASS", f"Chop [{rig}]: marker Hit at frame 12 (0.37 s)"), f"{rig} Chop: Hit marker with its time", report)
ok(has(report, "PASS", "Chop [R15]: RightHand stays on the Katana grip") and has(report, "PASS", "Chop [R6]: Right Arm stays on the Katana_R6 grip"), "grip holds on R15 (RightHand) and R6 (Right Arm)", report)
ok(has(report, "PASS", "Walk [R15 vs R6]: same length and marker frames") and has(report, "PASS", "Chop [R15 vs R6]"), "R15 and R6 versions match", report)
blend = os.path.join(tmp, "anims.blend")
bpy.ops.wm.save_as_mainfile(filepath=blend)

print("broken variants")
cases = [
    ("feet float", dict(float_by=0.3), None, "FAIL", "Walk [R15]: no foot on the floor on frames 1-25 (lowest foot 0.30 studs up): feet float"),
    ("feet sink", dict(float_by=-0.3), None, "FAIL", "Walk [R15]: a foot sinks into the floor on frames"),
    ("feet slide", {}, {"Walk": {"speed": 6}}, "FAIL", "Walk [R15]: planted feet slide"),
    ("root travels", dict(root_travel=True), None, "FAIL", "Walk [R15]: HumanoidRootNode travels 2.00 studs"),
    ("loop pops", dict(pop=True), None, "FAIL", "Walk [R15]: pops when it loops: RightUpperArm turns"),
    ("prop leaves the hand", dict(grip_slip=True), None, "FAIL", "Chop [R15]: Katana leaves RightHand on frames 8-12"),
    ("blade through the body", dict(blade=(1, 0, 0)), None, "FAIL", "Chop [R15]: Katana goes through the body"),
    ("marker missing", dict(hit_marker=False), None, "FAIL", "Chop [R15]: marker Hit from the manifest is not on the action"),
    ("R6 drifts from R15", dict(r6_short=True), None, "WARN", "Chop [R15 vs R6]: lengths differ: R15 20 frames, R6 18"),
    ("R6 rig missing", dict(r6=False), None, "FAIL", "scene: the project ships R6 but the scene has no R6 armature"),
]
for label, flags, accept, level, needle in cases:
    build(**flags)
    path = manifest_with(os.path.join(tmp, "variant.json"), **accept) if accept else example
    report = run(path)
    ok(has(report, level, needle), f"{label}: {level} '{needle[:70]}'", report)
build(blade=(1, 0, 0))
report = run(example)
clip = next(m for l, w, m in report.lines if l == "FAIL" and w == "Chop [R15]" and "through the body" in m)
ok("LeftUpperLeg" in clip or "RightUpperLeg" in clip, f"clipping names the parts and frames: {clip[:90]}")
build(r6_short=True)
report = run(example)
ok(has(report, "WARN", "Chop [R15 vs R6]: marker Hit: R15 frame 12, R6 frame 14"), "R6 marker frame drift reported", report)

print("command line (fresh interpreter, like `blender -b scene.blend --python anim_accept.py -- animations.json`)")
cli = subprocess.run([sys.executable, accept_path, example, blend, "--json", os.path.join(tmp, "accept.json")], capture_output=True, text=True)
lines = json.load(open(os.path.join(tmp, "accept.json"))) if os.path.exists(os.path.join(tmp, "accept.json")) else []
ok(cli.returncode == 0 and "0 failed" in cli.stdout and any(l["level"] == "PASS" for l in lines), f"clean .blend: exit {cli.returncode}, JSON report written")
build(pop=True)
bad = os.path.join(tmp, "bad.blend")
bpy.ops.wm.save_as_mainfile(filepath=bad)
cli = subprocess.run([sys.executable, accept_path, example, bad, "--only", "Walk"], capture_output=True, text=True)
ok(cli.returncode == 1 and "pops when it loops" in cli.stdout and "Chop" not in cli.stdout, f"broken .blend with --only Walk: exit {cli.returncode}")

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
