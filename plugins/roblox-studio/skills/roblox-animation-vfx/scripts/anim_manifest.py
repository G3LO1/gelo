#!/usr/bin/env python3
"""Validates an animation manifest and generates the Luau module the game loads it from.

Usage: anim_manifest.py animations.json [-o src/shared/Animations.luau] [--allow-todo]

animations.json:
{
  "rig": "R15",                       # R15 | R6 | Custom (rig of the characters these play on)
  "rigs": ["R15", "R6"],              # optional: the game ships both; every clip then needs "idR6"
  "accept": { "slideTolerance": 1.5 },  # optional: acceptance defaults for anim_accept.py
  "owner": "group 1234567",           # who uploads them (must own the experience, or grant it permission)
  "animations": [
    {"name": "Idle", "id": "rbxassetid://123", "priority": "Idle", "looped": true},
    {"name": "Chop", "id": 456, "priority": "Action", "looped": false, "markers": ["Hit"]},
    {"name": "Locomotion", "id": 789, "graph": true, "parameters": ["Speed", "Grounded"]}
  ]
}
"id": 0 or missing = not uploaded yet (an error unless --allow-todo). "graph": true marks an
Animation Graph asset (driven with AnimationTrack:SetParameter). An animation's optional "accept"
block (grounded, speed, rootMotion, prop, grips, ignore, tolerances) is what anim_accept.py checks in
Blender after retargeting. Exit code 1 on errors.
"""

import argparse
import json
import re
import sys

PRIORITIES = ["Core", "Idle", "Movement", "Action", "Action2", "Action3", "Action4"]
RIGS = {"R15", "R6", "Custom"}
LOCOMOTION = re.compile(r"^(idle|walk|run|sprint|jump|fall|climb|swim|crouch|strafe)", re.I)
LOOPING = re.compile(r"^(idle|walk|run|sprint|climb|swim|crouch|carry|hold|loop)", re.I)
ACTIONS = re.compile(r"(attack|slash|swing|punch|kick|throw|shoot|fire|chop|stab|hit|block|parry|cast|emote|dance|wave|cheer|death|die|land|use|interact|pickup|equip)", re.I)
TIMED = re.compile(r"(attack|slash|swing|punch|kick|throw|shoot|fire|chop|stab|cast|footstep|step)", re.I)
NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
TOLERANCES = {"floorTolerance", "slideTolerance", "rootTravel", "gripGap", "loopTolerance"}
ACCEPT_KEYS = TOLERANCES | {"grounded", "speed", "rootMotion", "prop", "grips", "ignore"}


def check_accept(block, where, errors, per_animation):
    if not isinstance(block, dict):
        errors.append(f"{where}: accept must be an object")
        return
    allowed = ACCEPT_KEYS if per_animation else TOLERANCES
    for key, value in block.items():
        if key not in allowed:
            errors.append(f"{where}: accept.{key} is not a known setting ({', '.join(sorted(allowed))})")
        elif key in TOLERANCES or key == "speed":
            if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0:
                errors.append(f"{where}: accept.{key} must be a number >= 0")
        elif key in ("grounded", "rootMotion") and not isinstance(value, bool):
            errors.append(f"{where}: accept.{key} must be true or false")
        elif key == "grips" and not (isinstance(value, dict) and value and all(isinstance(v, str) for v in value.values())):
            errors.append(f"{where}: accept.grips must map hand bones to grip points, e.g. {{\"RightHand\": \"Grip\"}}")
        elif key == "ignore" and not (isinstance(value, list) and all(isinstance(v, str) for v in value)):
            errors.append(f"{where}: accept.ignore must be a list of body part names")
    if per_animation and "grips" in block and not block.get("prop"):
        errors.append(f"{where}: accept.grips needs accept.prop (the prop object)")


def parse_id(value):
    if value is None:
        return None
    if isinstance(value, int):
        return value if value > 0 else None
    m = re.fullmatch(r"(?:rbxassetid://)?(\d+)", str(value).strip())
    if not m or int(m.group(1)) == 0:
        return None
    return int(m.group(1))


def validate(manifest, allow_todo):
    errors, warnings, todos = [], [], []
    rigs = manifest.get("rigs")
    rig = manifest.get("rig", rigs[0] if isinstance(rigs, list) and rigs else "R15")
    if rig not in RIGS:
        errors.append(f"rig '{rig}' must be one of {sorted(RIGS)}")
    if rigs is not None:
        if not (isinstance(rigs, list) and rigs and all(r in RIGS for r in rigs) and len(set(rigs)) == len(rigs)):
            errors.append(f"rigs must be a list of different rigs from {sorted(RIGS)}")
            rigs = [rig]
        elif rigs[0] != rig:
            errors.append(f"rigs starts with {rigs[0]} but rig is {rig}; the first of rigs is the main rig")
    else:
        rigs = [rig]
    if "accept" in manifest:
        check_accept(manifest["accept"], "manifest", errors, per_animation=False)
    if not manifest.get("owner"):
        warnings.append("no 'owner': animations must be uploaded by the account/group that owns the experience (or granted to it), or they fail for players")
    seen_names, seen_ids = {}, {}
    for index, anim in enumerate(manifest.get("animations", [])):
        name = anim.get("name", "")
        where = f"animations[{index}] {name or '?'}"
        if not NAME.match(name):
            errors.append(f"{where}: name must be a Luau identifier (letters, digits, _)")
        if name in seen_names:
            errors.append(f"{where}: duplicate name")
        seen_names[name] = True
        asset = parse_id(anim.get("id"))
        if asset is None:
            (todos if allow_todo else errors).append(f"{where}: no asset id yet (upload it, then paste the id)")
        elif asset in seen_ids:
            warnings.append(f"{where}: same id as {seen_ids[asset]}")
        else:
            seen_ids[asset] = name
        if anim.get("rig", rig) != rig:
            errors.append(f"{where}: made for {anim.get('rig')} but the manifest rig is {rig}; R15 and R6 animations don't play on each other")
        if "R6" in rigs[1:]:
            r6 = parse_id(anim.get("idR6"))
            if r6 is None:
                (todos if allow_todo else errors).append(f"{where}: no R6 asset id yet (idR6; the game ships R6 too)")
            elif asset is not None and r6 == asset:
                errors.append(f"{where}: idR6 is the R15 id; R6 needs its own upload")
        if "accept" in anim:
            check_accept(anim["accept"], where, errors, per_animation=True)
        elif manifest.get("accept") is not None or any("accept" in a for a in manifest.get("animations", [])):
            if LOCOMOTION.match(name) and not anim.get("graph"):
                warnings.append(f"{where}: locomotion without 'accept' (grounded, speed): anim_accept.py won't check its feet")
        if anim.get("graph"):
            if not anim.get("parameters"):
                warnings.append(f"{where}: animation graph without 'parameters'; list the ones code sets with SetParameter")
            continue
        priority = anim.get("priority")
        if priority not in PRIORITIES:
            errors.append(f"{where}: priority '{priority}' must be one of {PRIORITIES}")
            continue
        level = PRIORITIES.index(priority)
        looped = anim.get("looped")
        if looped is None:
            errors.append(f"{where}: set 'looped' explicitly (it's saved in the asset, the code overrides it)")
        if LOCOMOTION.match(name) and level > PRIORITIES.index("Movement"):
            warnings.append(f"{where}: locomotion at {priority} overrides attacks and emotes; use Idle/Movement")
        elif ACTIONS.search(name) and not LOCOMOTION.match(name) and level < PRIORITIES.index("Action"):
            warnings.append(f"{where}: one-off action at {priority} is overridden by walking; use Action or higher")
        if LOOPING.match(name) and looped is False:
            warnings.append(f"{where}: '{name}' usually loops")
        if ACTIONS.search(name) and not LOOPING.match(name) and looped is True:
            warnings.append(f"{where}: one-off action marked looped")
        if TIMED.search(name) and not anim.get("markers"):
            warnings.append(f"{where}: add a marker (e.g. 'Hit') so code times damage/sounds/VFX to the animation instead of task.wait")
    return errors, warnings, todos


def lua_string(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def generate(manifest, source_name):
    rigs = manifest.get("rigs") or [manifest.get("rig", "R15")]
    lines = [
        f"-- Generated by anim_manifest.py from {source_name}. Edit the JSON and regenerate.",
        f"-- Rig: {' + '.join(rigs)}. Owner: {manifest.get('owner', '?')}. Load with AnimationSet.new(animator, Animations.specsFor(humanoid)).",
        "",
        "local Animations = {}",
        "",
        f"Animations.Rig = {lua_string(rigs[0])}",
        f"Animations.Rigs = {{ {', '.join(lua_string(r) for r in rigs)} }}",
        "",
    ]
    lines += spec_table(manifest, "Specs", "id")
    if "R6" in rigs[1:]:
        lines += ["", "-- Same clips retargeted to R6 (no elbows, no knees): uploaded separately."]
        lines += spec_table(manifest, "SpecsR6", "idR6")
    lines += [
        "",
        "-- The specs for a character's rig (R6 characters get SpecsR6 when the game ships it).",
        "function Animations.specsFor(humanoid: Humanoid?)",
        "\tif humanoid and humanoid.RigType == Enum.HumanoidRigType.R6 and Animations.SpecsR6 then",
        "\t\treturn Animations.SpecsR6",
        "\tend",
        "\treturn Animations.Specs",
        "end",
    ]
    lines += ["", "-- Plain id table (the roblox-luau-codegen Animations pattern reads this shape).", "Animations.Ids = {}", "for name, spec in Animations.Specs do", "\tAnimations.Ids[name] = spec.Id", "end", "", "return Animations", ""]
    return "\n".join(lines)


def spec_table(manifest, table, id_key):
    lines = [f"Animations.{table} = {{"]
    for anim in manifest.get("animations", []):
        asset = parse_id(anim.get(id_key))
        fields = [f"Id = {lua_string(f'rbxassetid://{asset}' if asset else 'rbxassetid://0')}"]
        if anim.get("graph"):
            fields.append("Graph = true")
            params = ", ".join(lua_string(p) for p in anim.get("parameters", []))
            fields.append(f"Parameters = {{ {params} }}" if params else "Parameters = {}")
        else:
            fields.append(f"Priority = Enum.AnimationPriority.{anim['priority']}")
            fields.append(f"Looped = {'true' if anim.get('looped') else 'false'}")
        markers = ", ".join(lua_string(m) for m in anim.get("markers", []))
        fields.append(f"Markers = {{ {markers} }}" if markers else "Markers = {}")
        body = ", ".join(fields)
        todo = " -- TODO: upload and paste the id" if not asset else ""
        lines.append(f"\t{anim['name']} = {{ {body} }},{todo}")
    lines.append("}")
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("manifest")
    ap.add_argument("-o", "--out")
    ap.add_argument("--allow-todo", action="store_true", help="missing ids are TODOs, not errors")
    args = ap.parse_args()
    with open(args.manifest, encoding="utf-8") as fh:
        manifest = json.load(fh)
    errors, warnings, todos = validate(manifest, args.allow_todo)
    for e in errors:
        print(f"error: {e}")
    for w in warnings:
        print(f"warning: {w}")
    for t in todos:
        print(f"todo: {t}")
    total = len(manifest.get("animations", []))
    print(f"{total} animation(s): {len(errors)} error(s), {len(warnings)} warning(s), {len(todos)} todo(s)")
    if errors:
        sys.exit(1)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(generate(manifest, args.manifest.split("/")[-1]))
        print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
