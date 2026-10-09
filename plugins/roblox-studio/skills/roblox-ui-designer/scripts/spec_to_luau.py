#!/usr/bin/env python3
"""Turn a ui-spec JSON file into one Luau script that builds the UI in Roblox Studio.

Usage: spec_to_luau.py ui-spec.json [-o BuildUi.luau]

The spec is checked for structure and dangling token/font/image references first; property
names and value types are checked later by validate_ui.luau (Lune, real Roblox reflection)
or by Studio itself when the script runs.
"""

import argparse
import json
import re
import sys
from pathlib import Path

BUILDER = Path(__file__).resolve().parent.parent / "assets" / "ui_builder.luau"

ENCODINGS = {
    "udim2": 4,
    "udim": 2,
    "vector2": 2,
    "rect": 4,
    "color": None,
    "token": None,
    "enum": None,
    "font": None,
    "image": None,
    "colorseq": None,
    "numseq": None,
}
NODE_KEYS = {"class", "name", "props", "children", "tags", "attributes"}
SPEC_KEYS = {"name", "parent", "tokens", "fonts", "images", "styles", "screens", "reference"}
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


class SpecError(Exception):
    pass


def check_value(spec, value, path):
    if isinstance(value, (bool, int, float, str)):
        return
    if not isinstance(value, dict) or len(value) != 1:
        raise SpecError(f"{path}: expected a number/bool/string or one encoding object like {{\"udim2\": [...]}}")
    (kind, payload), = value.items()
    if kind not in ENCODINGS:
        raise SpecError(f"{path}: unknown encoding '{kind}' (known: {', '.join(ENCODINGS)})")
    size = ENCODINGS[kind]
    if size is not None:
        if not (isinstance(payload, list) and len(payload) == size and all(isinstance(n, (int, float)) for n in payload)):
            raise SpecError(f"{path}: '{kind}' needs {size} numbers")
    elif kind == "color":
        if not (isinstance(payload, str) and HEX.match(payload)):
            raise SpecError(f"{path}: color must be '#RRGGBB'")
    elif kind == "token":
        if payload not in (spec.get("tokens") or {}):
            raise SpecError(f"{path}: unknown token '{payload}'")
    elif kind == "enum":
        if not (isinstance(payload, str) and re.match(r"^\w+\.\w+$", payload)):
            raise SpecError(f"{path}: enum must look like 'ScaleType.Slice'")
    elif kind == "font":
        if isinstance(payload, str):
            if payload not in (spec.get("fonts") or {}):
                raise SpecError(f"{path}: unknown font '{payload}'")
        elif not (isinstance(payload, dict) and isinstance(payload.get("family"), str)):
            raise SpecError(f"{path}: font must be a name from 'fonts' or {{\"family\": ...}}")
    elif kind == "image":
        if payload not in (spec.get("images") or {}):
            raise SpecError(f"{path}: unknown image '{payload}' (add it to 'images')")
    elif kind in ("colorseq", "numseq"):
        if not (isinstance(payload, list) and len(payload) >= 2):
            raise SpecError(f"{path}: '{kind}' needs at least 2 keypoints [time, value]")
        for point in payload:
            if not (isinstance(point, list) and len(point) == 2 and isinstance(point[0], (int, float))):
                raise SpecError(f"{path}: keypoint must be [time, value]")
            if kind == "colorseq" and not (isinstance(point[1], str) and HEX.match(point[1])):
                raise SpecError(f"{path}: colorseq values must be '#RRGGBB'")


def check_node(spec, node, path):
    if not isinstance(node, dict) or not isinstance(node.get("class"), str):
        raise SpecError(f"{path}: node needs a 'class'")
    unknown = set(node) - NODE_KEYS
    if unknown:
        raise SpecError(f"{path}: unknown node keys {sorted(unknown)}")
    here = f"{path}/{node.get('name', node['class'])}"
    for prop, value in (node.get("props") or {}).items():
        if not IDENT.match(prop):
            raise SpecError(f"{here}: bad property name '{prop}'")
        check_value(spec, value, f"{here}.{prop}")
    for name, value in (node.get("attributes") or {}).items():
        check_value(spec, value, f"{here}@{name}")
    for child in node.get("children") or []:
        check_node(spec, child, here)


GUI_SIZED = re.compile(r"^(Frame|TextLabel|TextButton|TextBox|ImageLabel|ImageButton|ScrollingFrame|CanvasGroup|ViewportFrame|VideoFrame)$")


def lint_node(node, path, warnings, in_layout_axis=None):
    """Catch layouts that are valid Roblox but render wrong (they pass validation)."""
    here = f"{path}/{node.get('name', node['class'])}"
    props = node.get("props") or {}
    children = node.get("children") or []
    classes = {child["class"] for child in children if isinstance(child, dict)}
    if GUI_SIZED.match(node["class"]):
        size = (props.get("Size") or {}).get("udim2") if isinstance(props.get("Size"), dict) else None
        auto = props.get("AutomaticSize")
        auto = auto.get("enum", "") if isinstance(auto, dict) else ""
        if size:
            zero_x = size[0] == 0 and size[1] == 0 and not auto.endswith((".X", ".XY"))
            zero_y = size[2] == 0 and size[3] == 0 and not auto.endswith((".Y", ".XY"))
            flex = "UIFlexItem" in classes and in_layout_axis is not None
            if (zero_x and not (flex and in_layout_axis == "x")) or (zero_y and not (flex and in_layout_axis == "y")):
                hint = (" UIAspectRatioConstraint only shrinks an element, it never gives a zero axis a size:"
                        " give that axis a real size (e.g. Offset height in a ScrollingFrame list)."
                        if "UIAspectRatioConstraint" in classes else " Give it a size, AutomaticSize or a UIFlexItem.")
                warnings.append(f"{here}: Size {size} is zero on one axis, so it renders invisible.{hint}")
    layout = next((c for c in children if isinstance(c, dict) and c["class"] == "UIListLayout"), None)
    axis = None
    if layout:
        direction = ((layout.get("props") or {}).get("FillDirection") or {}).get("enum", "FillDirection.Vertical")
        axis = "x" if direction.endswith("Horizontal") else "y"
    for child in children:
        if isinstance(child, dict) and isinstance(child.get("class"), str):
            lint_node(child, here, warnings, axis)


def check_spec(spec):
    if not isinstance(spec, dict):
        raise SpecError("spec must be a JSON object")
    unknown = set(spec) - SPEC_KEYS
    if unknown:
        raise SpecError(f"unknown top-level keys {sorted(unknown)}")
    if not isinstance(spec.get("name"), str) or not IDENT.match(spec["name"]):
        raise SpecError("'name' must be an identifier, e.g. 'FoodTruckUI'")
    screens = spec.get("screens")
    if not isinstance(screens, list) or not screens:
        raise SpecError("'screens' must be a non-empty list of ScreenGui nodes")
    for name, value in (spec.get("tokens") or {}).items():
        if isinstance(value, dict) and "token" in value:
            raise SpecError(f"tokens.{name}: tokens can't reference other tokens")
        check_value(spec, value, f"tokens.{name}")
    for name, font in (spec.get("fonts") or {}).items():
        if not (isinstance(font, dict) and isinstance(font.get("family"), str)):
            raise SpecError(f"fonts.{name}: needs a 'family'")
    for index, rule in enumerate(spec.get("styles") or []):
        if not isinstance(rule.get("selector"), str):
            raise SpecError(f"styles[{index}]: needs a 'selector'")
        for prop, value in (rule.get("props") or {}).items():
            check_value(spec, value, f"styles[{index}].{prop}")
    for screen in screens:
        check_node(spec, screen, spec["name"])
        if screen["class"] not in ("ScreenGui", "SurfaceGui", "BillboardGui"):
            raise SpecError(f"screen '{screen.get('name')}' must be a ScreenGui/SurfaceGui/BillboardGui")
        if not screen.get("name"):
            raise SpecError("every screen needs a 'name'")


def luau_string(text):
    return json.dumps(text, ensure_ascii=False)


def to_luau(value, indent=0):
    pad = "\t" * (indent + 1)
    end_pad = "\t" * indent
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return luau_string(value)
    if isinstance(value, list):
        if not value:
            return "{}"
        items = [to_luau(item, indent + 1) for item in value]
        if all(not isinstance(item, (dict, list)) for item in value):
            return "{ " + ", ".join(items) + " }"
        return "{\n" + "".join(f"{pad}{item},\n" for item in items) + end_pad + "}"
    if isinstance(value, dict):
        if not value:
            return "{}"
        lines = []
        for key, item in value.items():
            field = key if IDENT.match(key) else f"[{luau_string(key)}]"
            lines.append(f"{pad}{field} = {to_luau(item, indent + 1)},\n")
        return "{\n" + "".join(lines) + end_pad + "}"
    raise SpecError(f"unsupported JSON value {value!r}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("spec")
    parser.add_argument("-o", "--output")
    args = parser.parse_args()

    spec = json.loads(Path(args.spec).read_text(encoding="utf-8"))
    try:
        check_spec(spec)
    except SpecError as error:
        sys.exit(f"spec error: {error}")
    warnings = []
    for screen in spec["screens"]:
        lint_node(screen, spec["name"], warnings)
    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)

    script = (
        f"-- Generated by roblox-ui-designer from {Path(args.spec).name}. Do not edit by hand: edit the spec and regenerate.\n"
        "-- Run in Roblox Studio (Command Bar, or the Studio MCP execute_luau tool) while editing, not in a live game.\n"
        "-- An existing ScreenGui with the same name is kept, renamed to <Name>_Backup and disabled.\n\n"
        f"local SPEC = {to_luau(spec)}\n\n"
        + BUILDER.read_text(encoding="utf-8")
        + "\nrun(SPEC)\n"
    )
    if args.output:
        Path(args.output).write_text(script, encoding="utf-8")
        print(f"wrote {args.output}")
    else:
        sys.stdout.write(script)


if __name__ == "__main__":
    main()
