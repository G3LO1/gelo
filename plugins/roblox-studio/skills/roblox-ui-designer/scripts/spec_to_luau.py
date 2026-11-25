#!/usr/bin/env python3
"""Turn a ui-spec JSON file into one Luau script that builds the UI in Roblox Studio.

Usage: spec_to_luau.py ui-spec.json [-o BuildUi.luau] [--images ui/images]

The spec is checked for structure and dangling token/font/image references first; property
names and value types are checked later by validate_ui.luau (Lune, real Roblox reflection)
or by Studio itself when the script runs. Style selectors are checked for Roblox's syntax
(states :Hover/:Press/:NonInteractable/:Idle, descendants with >>). The optional `motion`
table (shared animation numbers) is range-checked and becomes Motion* tokens. With --images,
9-slice SliceCenter rects are checked against the real PNG sizes.
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
SPEC_KEYS = {"name", "parent", "tokens", "fonts", "images", "styles", "screens", "reference", "motion"}
# Shared animation numbers (one table for the whole UI): key -> (min, max, default).
# Scales feed UIScale.Scale, times are seconds, glow* are the glow layer's ImageTransparency.
MOTION = {
    "hoverScale": (1.0, 1.15, 1.04),
    "pressScale": (0.85, 1.0, 0.98),
    "hoverTime": (0.03, 0.5, 0.12),
    "pressTime": (0.03, 0.3, 0.08),
    "openTime": (0.1, 0.8, 0.3),
    "stagger": (0.0, 0.2, 0.05),
    "glowIdle": (0.0, 1.0, 1.0),
    "glowFocused": (0.0, 1.0, 0.35),
    "glowPressed": (0.0, 1.0, 0.15),
    "disabledTransparency": (0.0, 0.9, 0.5),
    "breathe": (0.0, 5.0, 1.6),
}
STATES = {"Hover", "Press", "NonInteractable", "Idle"}  # Enum.GuiState
STATE_FIXES = {"Pressed": "Press", "Pressing": "Press", "Disabled": "NonInteractable", "Selected": "Hover (or a tag set by code)", "Focused": "Hover (or a tag set by code)"}
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


def lint_slice(spec, node, here, props, warnings, image_sizes):
    """9-slice images: a missing or wrong SliceCenter stretches the corners or shows a band
    (the "dark strip down every card" bug)."""
    scale = props.get("ScaleType")
    if not (isinstance(scale, dict) and scale.get("enum") == "ScaleType.Slice"):
        if "SliceCenter" in props:
            warnings.append(f"{here}: SliceCenter without ScaleType.Slice does nothing")
        return
    rect = props.get("SliceCenter")
    if not (isinstance(rect, dict) and "rect" in rect):
        warnings.append(f"{here}: ScaleType.Slice without SliceCenter: the whole image stretches, corners included. Add SliceCenter {{\"rect\": [left, top, right, bottom]}} in image pixels")
        return
    left, top, right, bottom = rect["rect"]
    if not (0 <= left < right and 0 <= top < bottom):
        warnings.append(f"{here}: SliceCenter {rect['rect']} must have left < right and top < bottom (in image pixels)")
        return
    image = props.get("Image")
    key = image.get("image") if isinstance(image, dict) else None
    if key and key in image_sizes:
        width, height = image_sizes[key]
        if right > width or bottom > height:
            warnings.append(f"{here}: SliceCenter {rect['rect']} reaches past the {width}x{height} image '{key}'")
        elif right - left >= width or bottom - top >= height:
            warnings.append(f"{here}: SliceCenter {rect['rect']} covers the whole {width}x{height} image '{key}': no corners are kept")


def lint_node(node, path, warnings, in_layout_axis=None, spec=None, image_sizes=None):
    """Catch layouts that are valid Roblox but render wrong (they pass validation)."""
    here = f"{path}/{node.get('name', node['class'])}"
    props = node.get("props") or {}
    if node["class"] in ("ImageLabel", "ImageButton"):
        lint_slice(spec, node, here, props, warnings, image_sizes or {})
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
            lint_node(child, here, warnings, axis, spec, image_sizes)


def motion_token(key):
    return "Motion" + key[0].upper() + key[1:]


def expand_motion(spec):
    """Checks `motion` and returns a copy of the spec whose tokens include Motion* entries
    (defaults filled in), so props and style rules can use { "token": "MotionHoverScale" }."""
    motion = spec.get("motion")
    if motion is None:
        return spec
    if not isinstance(motion, dict):
        raise SpecError("'motion' must be an object like { \"hoverScale\": 1.04 }")
    unknown = set(motion) - set(MOTION)
    if unknown:
        raise SpecError(f"motion: unknown key(s) {sorted(unknown)} (known: {', '.join(MOTION)})")
    tokens = dict(spec.get("tokens") or {})
    for key, (low, high, default) in MOTION.items():
        value = motion.get(key, default)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not low <= value <= high:
            raise SpecError(f"motion.{key}: {value!r} must be a number from {low} to {high}")
        name = motion_token(key)
        if name in tokens:
            raise SpecError(f"tokens.{name}: reserved for motion.{key}")
        tokens[name] = value
    expanded = dict(spec)
    expanded["tokens"] = tokens
    return expanded


SELECTOR_COMPOUND = re.compile(r"^(?:[A-Za-z]\w*)?(?:[.#]\w+)*(?::\w+)*(?:::\w+)?$")


def check_selector(selector, where):
    for part in selector.split(","):
        part = part.strip()
        if not part:
            raise SpecError(f"{where}: empty selector in a list")
        tokens = re.split(r"\s*(>>|>)\s*", part)
        compounds = tokens[::2]
        for compound in compounds:
            if compound == "" and compounds.index(compound) == 0:
                continue  # nested rule like "> TextButton"
            if re.search(r"\s", compound):
                raise SpecError(f"{where}: '{part}': Roblox has no space combinator; use '>>' for descendants or '>' for children")
            if not SELECTOR_COMPOUND.match(compound):
                raise SpecError(f"{where}: '{compound}' is not a selector (Class, .Tag, #Name, :State, ::UIComponent)")
            for state in re.findall(r"(?<!:):(\w+)", compound):
                if state not in STATES:
                    hint = f" (use :{STATE_FIXES[state]})" if state in STATE_FIXES else ""
                    raise SpecError(f"{where}: unknown state ':{state}' in '{part}'; states are :Hover, :Press, :NonInteractable, :Idle{hint}")


EASING = {"Linear", "Sine", "Back", "Quad", "Quart", "Quint", "Bounce", "Elastic", "Exponential", "Circular", "Cubic"}


def check_transition(spec, transition, where):
    """{ "time": 0.12 | {"token": "MotionHoverTime"}, "easing": "Quad", "direction": "Out" }:
    the rule's properties tween to their new values (StyleRule:SetDefaultPropertyTransition)."""
    if not isinstance(transition, dict) or "time" not in transition:
        raise SpecError(f"{where}: needs at least {{\"time\": seconds}}")
    unknown = set(transition) - {"time", "easing", "direction"}
    if unknown:
        raise SpecError(f"{where}: unknown key(s) {sorted(unknown)}")
    time = transition["time"]
    if isinstance(time, dict) and "token" in time:
        check_value(spec, time, f"{where}.time")
        time = spec["tokens"][time["token"]]
    if isinstance(time, bool) or not isinstance(time, (int, float)) or not 0 <= time <= 2:
        raise SpecError(f"{where}.time: {time!r} must be 0-2 seconds")
    if transition.get("easing", "Quad") not in EASING:
        raise SpecError(f"{where}.easing: one of {', '.join(sorted(EASING))}")
    if transition.get("direction", "Out") not in ("In", "Out", "InOut"):
        raise SpecError(f"{where}.direction: In, Out or InOut")


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
        check_selector(rule["selector"], f"styles[{index}]")
        unknown_rule = set(rule) - {"selector", "props", "priority", "transition"}
        if unknown_rule:
            raise SpecError(f"styles[{index}]: unknown key(s) {sorted(unknown_rule)}")
        if "transition" in rule:
            check_transition(spec, rule["transition"], f"styles[{index}].transition")
        for prop, value in (rule.get("props") or {}).items():
            check_value(spec, value, f"styles[{index}].{prop}")
    for screen in screens:
        check_node(spec, screen, spec["name"])
        if screen["class"] not in ("ScreenGui", "SurfaceGui", "BillboardGui"):
            raise SpecError(f"screen '{screen.get('name')}' must be a ScreenGui/SurfaceGui/BillboardGui")
        if not screen.get("name"):
            raise SpecError("every screen needs a 'name'")


def read_image_sizes(spec, folder):
    """{image key: (width, height)} for the keys that have a PNG in the folder (PNG header, no Pillow)."""
    sizes = {}
    if not folder:
        return sizes
    for key in spec.get("images") or {}:
        png = Path(folder) / f"{key}.png"
        if png.exists():
            head = png.read_bytes()[:24]
            if head[:8] == b"\x89PNG\r\n\x1a\n":
                sizes[key] = (int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big"))
    return sizes


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
    parser.add_argument("--images", help="folder with <image key>.png: checks SliceCenter against the real image sizes")
    args = parser.parse_args()

    spec = json.loads(Path(args.spec).read_text(encoding="utf-8"))
    try:
        spec = expand_motion(spec)
        check_spec(spec)
    except SpecError as error:
        sys.exit(f"spec error: {error}")
    image_sizes = read_image_sizes(spec, args.images)
    warnings = []
    for screen in spec["screens"]:
        lint_node(screen, spec["name"], warnings, None, spec, image_sizes)
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
