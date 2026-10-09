#!/usr/bin/env python3
"""Convert a Photoshop PSD into a ui-spec JSON plus trimmed PNG images for Roblox.

Usage: psd_to_spec.py design.psd -o out/ [--name HudUI]
Needs: pip install psd-tools

Layer conventions (see references/photoshop.md):
  top-level group        -> one ScreenGui (canvas size = reference resolution)
  group                  -> Frame (transparent) with children
  pixel/shape/smart obj  -> ImageLabel with an exported PNG
  text layer             -> TextLabel (editable, scales; font mapped to a Roblox family)
  name tags (anywhere in the layer name, removed from the Roblox name):
    #button   -> ImageButton (group or image) / TextButton (text)
    #slice=N  or #slice=L,T,R,B -> 9-slice image (pixels kept fixed at the edges)
    #list-v=GAP / #list-h=GAP   -> group children laid out by UIListLayout
    #scroll   -> group becomes a ScrollingFrame
    #raster   -> export a text layer as an image instead of a TextLabel
    #skip     -> ignored (guides, notes, mockup backgrounds)
Hidden layers are ignored too.
"""

import argparse
import json
import re
import sys
from pathlib import Path

try:
    from psd_tools import PSDImage
except ImportError:  # pragma: no cover
    sys.exit("psd-tools is required: pip install psd-tools")

TAG = re.compile(r"#([a-z\-]+)(?:=([0-9,]+))?", re.IGNORECASE)

# Photoshop font name fragment -> Roblox font family (rbxasset://fonts/families/<Family>.json)
FONT_MAP = [
    ("fredoka", "FredokaOne"),
    ("luckiest", "LuckiestGuy"),
    ("bangers", "Bangers"),
    ("creepster", "Creepster"),
    ("michroma", "Michroma"),
    ("montserrat", "Montserrat"),
    ("gotham", "GothamSSm"),
    ("roboto mono", "RobotoMono"),
    ("robotomono", "RobotoMono"),
    ("roboto", "Roboto"),
    ("pressstart", "PressStart2P"),
    ("press start", "PressStart2P"),
    ("oswald", "Oswald"),
    ("nunito", "Nunito"),
    ("titillium", "TitilliumWeb"),
    ("ubuntu", "Ubuntu"),
    ("permanentmarker", "PermanentMarker"),
    ("permanent marker", "PermanentMarker"),
    ("specialelite", "SpecialElite"),
    ("special elite", "SpecialElite"),
    ("sarpanch", "Sarpanch"),
    ("jura", "Jura"),
    ("denk", "DenkOne"),
    ("source sans", "SourceSansPro"),
    ("sourcesans", "SourceSansPro"),
    ("arimo", "Arimo"),
    ("arial", "Arimo"),
]
DEFAULT_FONT = "BuilderSans"


def parse_name(raw):
    tags = {}
    for match in TAG.finditer(raw):
        tags[match.group(1).lower()] = match.group(2)
    name = TAG.sub("", raw).strip()
    name = re.sub(r"[^A-Za-z0-9_]+", "_", name).strip("_") or "Layer"
    if name[0].isdigit():
        name = "_" + name
    return name, tags


def roblox_font(photoshop_name):
    lowered = (photoshop_name or "").lower()
    for fragment, family in FONT_MAP:
        if fragment in lowered:
            weight = "Bold" if "bold" in lowered or "black" in lowered or "heavy" in lowered else "Regular"
            return family, weight
    weight = "Bold" if "bold" in lowered else "Regular"
    return DEFAULT_FONT, weight


def anchor_and_layout(box, parent_box):
    """Scale-based position/size inside the parent, anchored to the nearest third so HUD
    corners stay in their corners on other aspect ratios."""
    left, top, right, bottom = box
    p_left, p_top, p_right, p_bottom = parent_box
    pw, ph = max(p_right - p_left, 1), max(p_bottom - p_top, 1)
    w, h = right - left, bottom - top
    cx, cy = (left + right) / 2 - p_left, (top + bottom) / 2 - p_top
    ax = 0 if cx < pw / 3 else (0.5 if cx < 2 * pw / 3 else 1)
    ay = 0 if cy < ph / 3 else (0.5 if cy < 2 * ph / 3 else 1)
    px = (left - p_left + ax * w) / pw
    py = (top - p_top + ay * h) / ph
    r = lambda v: round(v, 4)
    return {
        "AnchorPoint": {"vector2": [ax, ay]},
        "Position": {"udim2": [r(px), 0, r(py), 0]},
        "Size": {"udim2": [r(w / pw), 0, r(h / ph), 0]},
    }, (w, h, pw, ph)


def aspect_child(w, h, pw, ph):
    # Keep shapes undistorted on other screens, except for near full-size panels.
    if w >= 0.9 * pw and h >= 0.9 * ph:
        return []
    return [{"class": "UIAspectRatioConstraint", "props": {"AspectRatio": round(w / max(h, 1), 4)}}]


def text_props(layer, font_names_used):
    props = {"Text": (layer.text or "").replace("\r", "\n")}
    font_name, size, color, align = None, None, None, 0
    try:
        run = layer.engine_dict["StyleRun"]["RunArray"][0]["StyleSheet"]["StyleSheetData"]
        size = float(run.get("FontSize", 0)) or None
        font_index = int(run.get("Font", 0))
        fonts = layer.resource_dict["FontSet"]
        font_name = str(fonts[font_index]["Name"]).strip("'\"")
        fill = run.get("FillColor", {}).get("Values")
        if fill and len(fill) == 4:
            color = "#%02X%02X%02X" % tuple(max(0, min(255, round(float(c) * 255))) for c in fill[1:])
    except (KeyError, IndexError, TypeError, ValueError):
        pass
    try:
        paragraph = layer.engine_dict["ParagraphRun"]["RunArray"][0]["ParagraphSheet"]["Properties"]
        align = int(paragraph.get("Justification", 0))
    except (KeyError, IndexError, TypeError, ValueError):
        pass
    try:
        if size and layer.transform:
            size *= abs(float(layer.transform[3]))  # free-transformed text keeps size in the matrix
    except (TypeError, IndexError, ValueError):
        pass
    family, weight = roblox_font(font_name)
    font_names_used.add((font_name or "?", family))
    props["FontFace"] = {"font": {"family": family, "weight": weight}}
    props["TextScaled"] = True
    props["BackgroundTransparency"] = 1
    props["TextColor3"] = {"color": color or "#FFFFFF"}
    props["TextXAlignment"] = {"enum": ["TextXAlignment.Left", "TextXAlignment.Right", "TextXAlignment.Center"][align if align in (0, 1, 2) else 0]}
    children = []
    if size:
        children.append({"class": "UITextSizeConstraint", "props": {"MaxTextSize": max(1, round(size))}})
    return props, children


class Exporter:
    def __init__(self, psd, out_dir, spec_name):
        self.psd = psd
        self.out_dir = out_dir
        self.images_dir = out_dir / "images"
        self.images_dir.mkdir(parents=True, exist_ok=True)
        self.images = {}
        self.fonts = set()
        self.spec_name = spec_name
        self.warnings = []

    def export_image(self, layer, key):
        image = layer.composite()
        if image is None:
            self.warnings.append(f"{key}: layer has no pixels, skipped")
            return None
        file_name = f"{key}.png"
        image.save(self.images_dir / file_name)
        self.images[key] = "rbxassetid://0"
        if image.width > 1024 or image.height > 1024:
            self.warnings.append(f"{file_name}: {image.width}x{image.height}, consider <= 1024 px for memory on phones")
        return key

    def unique(self, name, used):
        candidate, n = name, 2
        while candidate in used:
            candidate = f"{name}_{n}"
            n += 1
        used.add(candidate)
        return candidate

    def node(self, layer, parent_box, path, used, z):
        if not layer.is_visible():
            return None
        name, tags = parse_name(layer.name)
        if "skip" in tags:
            return None
        name = self.unique(name, used)
        key = f"{path}__{name}" if path else name
        box = layer.bbox
        if box[2] <= box[0] or box[3] <= box[1]:
            return None
        layout, (w, h, pw, ph) = anchor_and_layout(box, parent_box)
        props = dict(layout)
        props["ZIndex"] = z
        props["LayoutOrder"] = z
        children = aspect_child(w, h, pw, ph)

        if layer.is_group():
            if "scroll" in tags:
                cls = "ScrollingFrame"
                props["CanvasSize"] = {"udim2": [0, 0, 0, 0]}
                props["AutomaticCanvasSize"] = {"enum": "AutomaticSize.Y"}
                props["ScrollBarThickness"] = 6
                props["BorderSizePixel"] = 0
            elif "button" in tags:
                cls = "ImageButton"
                props["Image"] = ""
            else:
                cls = "Frame"
            props["BackgroundTransparency"] = 1
            for list_tag, direction in (("list-v", "Vertical"), ("list-h", "Horizontal")):
                if list_tag in tags:
                    gap = int((tags[list_tag] or "0").split(",")[0])
                    children.append({"class": "UIListLayout", "props": {
                        "FillDirection": {"enum": f"FillDirection.{direction}"},
                        "Padding": {"udim": [0, gap]},
                        "SortOrder": {"enum": "SortOrder.LayoutOrder"},
                    }})
            child_used = set()
            built_children = []
            for index, child in enumerate(layer, start=1):
                built = self.node(child, box, key, child_used, index)
                if built:
                    built_children.append((child, built))
            # In a list, order follows the position on the canvas, not the layer stack.
            axis = 0 if "list-h" in tags else (1 if "list-v" in tags else None)
            if axis is not None:
                ranked = sorted(built_children, key=lambda pair: pair[0].bbox[axis])
                for rank, (_, built) in enumerate(ranked, start=1):
                    built["props"]["LayoutOrder"] = rank
            children.extend(built for _, built in built_children)
            return {"class": cls, "name": name, "props": props, "children": children}

        if layer.kind == "type" and "raster" not in tags:
            tprops, tchildren = text_props(layer, self.fonts)
            props.update(tprops)
            if "button" in tags:
                props["AutoButtonColor"] = True
            return {"class": "TextButton" if "button" in tags else "TextLabel", "name": name, "props": props,
                    "children": children + tchildren}

        image_key = self.export_image(layer, key)
        if not image_key:
            return None
        props["Image"] = {"image": image_key}
        props["BackgroundTransparency"] = 1
        if "slice" in tags:
            values = [int(v) for v in (tags["slice"] or "0").split(",") if v]
            if len(values) == 1:
                values = values * 4
            if len(values) == 4:
                l, t, r, b = values
                props["ScaleType"] = {"enum": "ScaleType.Slice"}
                props["SliceCenter"] = {"rect": [l, t, max(l + 1, w - r), max(t + 1, h - b)]}
                children = [c for c in children if c["class"] != "UIAspectRatioConstraint"]  # 9-slice is meant to stretch
            else:
                self.warnings.append(f"{key}: #slice needs 1 or 4 numbers")
        return {"class": "ImageButton" if "button" in tags else "ImageLabel", "name": name, "props": props,
                "children": children}

    def run(self):
        canvas = (0, 0, self.psd.width, self.psd.height)
        screens, loose = [], []
        used = set()
        for index, layer in enumerate(self.psd, start=1):
            if layer.is_group():
                if not layer.is_visible() or "skip" in parse_name(layer.name)[1]:
                    continue
                name = self.unique(parse_name(layer.name)[0], used)
                children, child_used = [], set()
                for child_index, child in enumerate(layer, start=1):
                    built = self.node(child, canvas, name, child_used, child_index)
                    if built:
                        children.append(built)
                screens.append({"class": "ScreenGui", "name": name, "props": {
                    "ResetOnSpawn": False,
                    "ZIndexBehavior": {"enum": "ZIndexBehavior.Sibling"},
                    "ScreenInsets": {"enum": "ScreenInsets.CoreUISafeInsets"},
                }, "children": children})
            else:
                loose.append((index, layer))
        if loose:
            children, child_used = [], set()
            for index, layer in loose:
                built = self.node(layer, canvas, "Main", child_used, index)
                if built:
                    children.append(built)
            if children:
                screens.append({"class": "ScreenGui", "name": self.unique("Main", used), "props": {
                    "ResetOnSpawn": False,
                    "ZIndexBehavior": {"enum": "ZIndexBehavior.Sibling"},
                    "ScreenInsets": {"enum": "ScreenInsets.CoreUISafeInsets"},
                }, "children": children})
        return {
            "name": self.spec_name,
            "reference": [self.psd.width, self.psd.height],
            "images": self.images,
            "screens": screens,
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("psd")
    parser.add_argument("-o", "--out", required=True, help="output folder")
    parser.add_argument("--name", help="spec name (identifier), default from the file name")
    args = parser.parse_args()

    psd = PSDImage.open(args.psd)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    spec_name = args.name or re.sub(r"[^A-Za-z0-9_]", "", Path(args.psd).stem.title()) or "PsdUI"
    exporter = Exporter(psd, out_dir, spec_name)
    spec = exporter.run()
    if not spec["screens"]:
        sys.exit("No visible layers found to export.")
    (out_dir / "ui-spec.json").write_text(json.dumps(spec, indent=2), encoding="utf-8")

    print(f"ui-spec.json: {len(spec['screens'])} screen(s), {len(exporter.images)} image(s) in {exporter.images_dir}")
    for ps_font, family in sorted(exporter.fonts):
        print(f"font: '{ps_font}' -> {family}")
    for warning in exporter.warnings:
        print(f"warning: {warning}")
    if exporter.images:
        print("next: upload images/ (Studio Asset Manager > Bulk Import), then put each rbxassetid into 'images' in ui-spec.json")


if __name__ == "__main__":
    main()
