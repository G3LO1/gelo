"""blender_check.py against real Blender (the `bpy` module from PyPI): a clean R15 rig with an
in-place 30 FPS animation, a broken one, model mode, and the FBX export call itself.
Usage: python blender_test.py <path to blender_check.py> <tmp dir>"""
import math
import os
import sys

import bpy

check_path, tmp = sys.argv[1], sys.argv[2]
namespace = {"ROBLOX_CHECK_IMPORT": True, "__name__": "blender_check"}
exec(compile(open(check_path).read(), check_path, "exec"), namespace)
check, export_fbx = namespace["check"], namespace["export_fbx"]

passed = failed = 0


def ok(condition, message, report=None):
    global passed, failed
    if condition:
        passed += 1
        print(f"  ok   {message}")
    else:
        failed += 1
        print(f"  FAIL {message}")
        if report:
            print("       " + report.text().replace("\n", "\n       "))


def has(report, level, needle):
    return any(l == level and needle in f"{w}: {m}" for l, w, m in report.lines)


R15 = [
    ("HumanoidRootNode", None, (0, 0, 2.0)),
    ("LowerTorso", "HumanoidRootNode", (0, 0, 2.1)),
    ("UpperTorso", "LowerTorso", (0, 0, 2.6)),
    ("Head", "UpperTorso", (0, 0, 3.4)),
    ("LeftUpperArm", "UpperTorso", (0.8, 0, 3.2)),
    ("LeftLowerArm", "LeftUpperArm", (1.0, 0, 2.7)),
    ("LeftHand", "LeftLowerArm", (1.1, 0, 2.2)),
    ("RightUpperArm", "UpperTorso", (-0.8, 0, 3.2)),
    ("RightLowerArm", "RightUpperArm", (-1.0, 0, 2.7)),
    ("RightHand", "RightLowerArm", (-1.1, 0, 2.2)),
    ("LeftUpperLeg", "LowerTorso", (0.3, 0, 2.0)),
    ("LeftLowerLeg", "LeftUpperLeg", (0.3, 0, 1.1)),
    ("LeftFoot", "LeftLowerLeg", (0.3, 0, 0.3)),
    ("RightUpperLeg", "LowerTorso", (-0.3, 0, 2.0)),
    ("RightLowerLeg", "RightUpperLeg", (-0.3, 0, 1.1)),
    ("RightFoot", "RightLowerLeg", (-0.3, 0, 0.3)),
]


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"
    scene.unit_settings.system_rotation = "DEGREES"
    scene.render.fps = 30
    scene.render.fps_base = 1
    return scene


def make_rig(bones, name="Rig"):
    data = bpy.data.armatures.new(name)
    rig = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for bone_name, parent, head in bones:
        bone = data.edit_bones.new(bone_name)
        bone.head = head
        bone.tail = (head[0], head[1] + 0.2, head[2])
        if parent:
            bone.parent = made[parent]
        made[bone_name] = bone
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def animate(rig, root_travel=0.0):
    rig.animation_data_create()
    root = rig.pose.bones[next(n for n in ("HumanoidRootNode", "HumanoidRootPart") if n in rig.pose.bones)]
    arm = rig.pose.bones["RightUpperArm"]
    arm.rotation_mode = "XYZ"
    for frame, angle, y in ((1, 0, 0), (15, 80, root_travel / 2), (30, 0, root_travel)):
        arm.rotation_euler = (math.radians(angle), 0, 0)
        arm.keyframe_insert("rotation_euler", frame=frame)
        root.location = (0, y, 0)
        root.keyframe_insert("location", frame=frame)


def add_mesh(name, subdivisions=1, materials=1, scale=1.0, closed=True):
    if closed:
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions)
    else:
        bpy.ops.mesh.primitive_plane_add()
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (scale, scale, scale)
    for i in range(materials):
        obj.data.materials.append(bpy.data.materials.new(f"{name}_mat{i}"))
    bpy.ops.mesh.uv_texture_add() if not obj.data.uv_layers else None
    return obj


print("clean R15 animation")
reset()
rig = make_rig(R15)
animate(rig)
add_mesh("Sword", subdivisions=3)
report, mode = check("auto")
ok(mode == "animation", "auto mode detects an animation")
ok(report.count("ERROR") == 0 and report.count("WARN") == 0, "no errors or warnings", report)
ok(has(report, "INFO", "frames 1-30"), "action length reported", report)
fbx = os.path.join(tmp, "Swing.fbx")
export_fbx(fbx, mode)
ok(os.path.getsize(fbx) > 1000, "export_fbx writes an FBX with Roblox settings (kwargs valid in this Blender)")

print("broken scene")
reset()
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.render.fps = 24
bad = [b for b in R15 if b[0] not in ("LeftFoot",)]
bad = [(n, ("UpperTorso" if n == "RightUpperLeg" else p), h) for n, p, h in bad] + [("Head_end", "Head", (0, 0, 3.9))]
rig = make_rig(bad)
rig.scale = (100, 100, 100)
animate(rig, root_travel=6.0)
add_mesh("Rock", subdivisions=7)  # 81,920 triangles
add_mesh("Crate", materials=2, scale=2.0)
add_mesh("Flag", closed=False)
report, mode = check("animation")
expect = [
    ("WARN", "Unit System is METRIC"),
    ("ERROR", "24 FPS"),
    ("ERROR", "mesh Rock: 81920 triangles"),
    ("WARN", "mesh Crate: 2 materials"),
    ("WARN", "mesh Crate: unapplied scale"),
    ("WARN", "mesh Flag: 4 open/non-manifold edges"),
    ("ERROR", "armature object scale"),
    ("WARN", "leaf bones ['Head_end']"),
    ("ERROR", "missing R15 bone LeftFoot"),
    ("ERROR", "RightUpperLeg is parented to UpperTorso, R15 needs LowerTorso"),
    ("ERROR", "HumanoidRootNode travels 6.00 units"),
]
for level, needle in expect:
    ok(has(report, level, needle), f"{level} {needle}", report if not has(report, level, needle) else None)
namespace["EXPORT_PATH"] = None

print("model mode and custom rigs")
reset()
add_mesh("Tree", subdivisions=2)
make_rig([("Spine", None, (0, 0, 0)), ("Neck", "Spine", (0, 0, 1))], name="Dragon")
report, mode = check("auto")
ok(mode == "model", "no action -> model mode")
ok(has(report, "INFO", "not an R15 naming scheme"), "custom rig recognised, no R15 errors", report)
ok(report.count("ERROR") == 0, "clean model has no errors", report)
legacy_root = [("HumanoidRootPart" if n == "HumanoidRootNode" else n, ("HumanoidRootPart" if p == "HumanoidRootNode" else p), h) for n, p, h in R15]
reset()
rig = make_rig(legacy_root)
animate(rig)
report, _ = check("animation")
ok(report.count("ERROR") == 0, "HumanoidRootPart naming (animation guides) is accepted too", report)

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
