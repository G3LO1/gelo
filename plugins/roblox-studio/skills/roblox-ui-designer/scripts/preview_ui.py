#!/usr/bin/env python3
"""Render an approximate browser preview of a ui-spec, to look at layouts without Studio.

Usage: preview_ui.py ui/ui-spec.json -o ui/preview.html [--images ui/images]
Open the HTML in a browser. URL parameters pick one view: preview.html?screen=Hud&w=844&h=390
Headless screenshot (Chrome/Chromium):
  chromium --headless --hide-scrollbars --window-size=844,390 --screenshot=hud-phone.png "file:///.../preview.html?screen=Hud&w=844&h=390"

What it models: Scale/Offset sizes, AnchorPoint, UIAspectRatioConstraint, UISizeConstraint, UIPadding,
UIListLayout (direction, padding, alignment, flex SpaceBetween/Around/Evenly, UIFlexItem Fill),
UIGridLayout, UICorner, UIStroke, UIGradient, transparency, Visible, ZIndex, TextScaled with
UITextSizeConstraint, simple RichText, style rules (class/.tag/#name selectors, ::UICorner/::UIStroke).
Approximate: fonts (browser fallbacks), AutomaticSize, text fitting, stroke placement, images
(local PNGs from --images when the id is still rbxassetid://0, otherwise a labeled placeholder).
Overlays show the Roblox top bar and phone thumb zones (approximate) so you can check safe areas.
Studio remains the final check.
"""

import argparse
import json
from pathlib import Path

HTML = r"""<!doctype html>
<html><head><meta charset="utf-8"><title>UI preview: __NAME__</title>
<style>
  body { margin: 0; background: #1b1d22; color: #ddd; font: 13px/1.4 system-ui, sans-serif; }
  .view { margin: 16px; display: inline-block; vertical-align: top; }
  .caption { margin: 0 0 6px; color: #aab; }
  .screen { position: relative; overflow: hidden; background: linear-gradient(180deg, #6fa6d8 0%, #9cc8a0 60%, #6e8f5a 100%); }
  .single .view { margin: 0; } .single .caption { display: none; }
  .el { position: absolute; box-sizing: border-box; }
  .txt { display: flex; width: 100%; height: 100%; white-space: pre-wrap; overflow: hidden; line-height: 1.05; }
  .img { width: 100%; height: 100%; display: flex; align-items: center; justify-content: center;
         background: repeating-conic-gradient(#c8c8c8 0 25%, #eee 0 50%) 0 0 / 16px 16px; color: #333; font-size: 11px; opacity: .85; }
  .ov-top { position: absolute; left: 0; right: 0; top: 0; background: rgba(255,0,0,.18); border-bottom: 1px dashed #f55; pointer-events: none; z-index: 100000; }
  .ov-zone { position: absolute; border: 2px dashed rgba(255,60,60,.8); border-radius: 50%; background: rgba(255,0,0,.12); pointer-events: none; z-index: 100000; }
  .ov-label { position: absolute; color: #fff; font-size: 10px; background: rgba(200,0,0,.6); padding: 1px 4px; z-index: 100001; }
</style></head>
<body>
<div id="root"></div>
<script>
const SPEC = __SPEC__;
const LOCAL_IMAGES = __IMAGES__;
const SIZES = [[1920, 1080], [844, 390], [1180, 820]];
const FONT_CSS = {
  FredokaOne: "'Fredoka One','Fredoka','Baloo 2','Arial Rounded MT Bold',sans-serif",
  LuckiestGuy: "'Luckiest Guy','Bangers',Impact,sans-serif", Bangers: "'Bangers',Impact,sans-serif",
  BuilderSans: "'Builder Sans','Inter','Segoe UI',system-ui,sans-serif", GothamSSm: "'Gotham','Montserrat','Segoe UI',sans-serif",
  SourceSansPro: "'Source Sans Pro','Segoe UI',sans-serif", Michroma: "'Michroma','Orbitron',sans-serif", Zekton: "'Orbitron',sans-serif",
  PressStart2P: "'Press Start 2P',monospace", Creepster: "'Creepster',fantasy", SpecialElite: "'Special Elite','Courier New',monospace",
  RobotoMono: "'Roboto Mono',monospace", Oswald: "'Oswald','Arial Narrow',sans-serif", RobotoCondensed: "'Roboto Condensed','Arial Narrow',sans-serif",
};
const WEIGHT = { Thin: 100, ExtraLight: 200, Light: 300, Regular: 400, Medium: 500, SemiBold: 600, Bold: 700, ExtraBold: 800, Heavy: 900 };

function hex(h) { return [parseInt(h.slice(1,3),16), parseInt(h.slice(3,5),16), parseInt(h.slice(5,7),16)]; }
function decode(v) {
  if (v === null || typeof v !== "object") return v;
  if (v.token !== undefined) return decode(SPEC.tokens[v.token]);
  if (v.font !== undefined) return typeof v.font === "string" ? { font: SPEC.fonts[v.font] } : { font: v.font };
  if (v.image !== undefined) return { image: v.image, id: (SPEC.images || {})[v.image] };
  return v;
}
function rgba(c, transparency) {
  if (!c || !c.color) return null;
  const [r, g, b] = hex(c.color);
  return `rgba(${r},${g},${b},${1 - (transparency || 0)})`;
}
function enumItem(v, fallback) { return v && v.enum ? v.enum.split(".")[1] : fallback; }

// ---- style rules ------------------------------------------------------------
function compoundMatches(compound, node) {
  const m = compound.match(/^([A-Za-z]\w*)?((?:[.#][\w]+)*)((?::\w+)*)$/);
  if (!m) return false;
  if (m[3]) return false; // :Hover / :Pressed states are not previewed
  if (m[1] && m[1] !== node.class) return false;
  for (const part of (m[2].match(/[.#][\w]+/g) || [])) {
    if (part[0] === "." && !(node.tags || []).includes(part.slice(1))) return false;
    if (part[0] === "#" && (node.name || node.class) !== part.slice(1)) return false;
  }
  return true;
}
function applyStyles(node) {
  for (const rule of SPEC.styles || []) {
    const last = rule.selector.trim().split(/\s*>\s*|\s+/).pop();
    const [compound, pseudo] = last.split("::");
    if (!compoundMatches(compound, node)) continue;
    if (pseudo) {
      node.children = node.children || [];
      let child = node.children.find(c => c.class === pseudo);
      if (!child) { child = { class: pseudo, props: {} }; node.children.push(child); }
      child.props = Object.assign({}, child.props, rule.props);
    } else {
      node.props = Object.assign({}, node.props, rule.props);
    }
  }
  for (const c of node.children || []) applyStyles(c);
}

// ---- layout -----------------------------------------------------------------
const MODIFIERS = new Set(["UICorner","UIStroke","UIGradient","UIPadding","UIListLayout","UIGridLayout","UIFlexItem",
  "UIAspectRatioConstraint","UISizeConstraint","UITextSizeConstraint","UIScale","StyleLink","UIPageLayout","UITableLayout"]);
function mod(node, cls) { return (node.children || []).find(c => c.class === cls); }
function P(node, key, fallback) { const v = (node.props || {})[key]; return v === undefined ? fallback : decode(v); }
function udim2(v, def) { return v && v.udim2 ? v.udim2 : def; }

function baseSize(node, pw, ph) {
  const s = udim2(P(node, "Size"), [0, 100, 0, 100]);
  let w = s[0] * pw + s[1], h = s[2] * ph + s[3];
  const sc = enumItem(P(node, "SizeConstraint"), "RelativeXY");
  if (sc === "RelativeYY") w = s[0] * ph + s[1];
  if (sc === "RelativeXX") h = s[2] * pw + s[3];
  const ar = mod(node, "UIAspectRatioConstraint");
  if (ar) {
    const ratio = P(ar, "AspectRatio", 1);
    const type = enumItem(P(ar, "AspectType"), "FitWithinMaxSize");
    const axis = enumItem(P(ar, "DominantAxis"), "Width");
    // Both types only fit inside a box (own Size, or the parent for ScaleWithParentSize); never grow a zero axis.
    let bw = w, bh = h;
    if (type === "ScaleWithParentSize") { bw = pw; bh = ph; }
    if (bw / Math.max(bh, 1e-9) > ratio) { w = bh * ratio; h = bh; } else { w = bw; h = bw / ratio; }
    void axis;
  }
  const sz = mod(node, "UISizeConstraint");
  if (sz) {
    const mn = (P(sz, "MinSize") || {}).vector2 || [0, 0], mx = (P(sz, "MaxSize") || {}).vector2 || [1e9, 1e9];
    w = Math.min(Math.max(w, mn[0]), mx[0]); h = Math.min(Math.max(h, mn[1]), mx[1]);
  }
  return [Math.max(0, w), Math.max(0, h)];
}
function padding(node, w, h) {
  const p = mod(node, "UIPadding"); const u = k => { const v = p && P(p, k); return v && v.udim ? v.udim : [0, 0]; };
  const L = u("PaddingLeft"), R = u("PaddingRight"), T = u("PaddingTop"), B = u("PaddingBottom");
  return { l: L[0]*w + L[1], r: R[0]*w + R[1], t: T[0]*h + T[1], b: B[0]*h + B[1] };
}

function render(node, parentEl, pw, ph, placed) {
  if (MODIFIERS.has(node.class)) return;
  if (P(node, "Visible", true) === false) return;
  let x, y, w, h;
  if (placed) { [x, y, w, h] = placed; }
  else {
    [w, h] = baseSize(node, pw, ph);
    const pos = udim2(P(node, "Position"), [0, 0, 0, 0]);
    const ap = (P(node, "AnchorPoint") || {}).vector2 || [0, 0];
    x = pos[0] * pw + pos[1] - ap[0] * w; y = pos[2] * ph + pos[3] - ap[1] * h;
  }
  const el = document.createElement("div");
  el.className = "el"; el.title = node.name || node.class;
  Object.assign(el.style, { left: x + "px", top: y + "px", width: w + "px", height: h + "px", zIndex: P(node, "ZIndex", 1) });
  const rot = P(node, "Rotation", 0); if (rot) el.style.transform = `rotate(${rot}deg)`;
  const isText = /^Text(Label|Button|Box)$/.test(node.class);
  const isImage = /^Image(Label|Button)$/.test(node.class);
  const bgT = P(node, "BackgroundTransparency", 0);
  let bg = rgba(P(node, "BackgroundColor3", { color: "#A3A2A5" }), bgT);
  const grad = mod(node, "UIGradient");
  if (grad && bgT < 1) {
    const seq = (P(grad, "Color") || {}).colorseq || [[0, "#FFFFFF"], [1, "#FFFFFF"]];
    const base = hex((P(node, "BackgroundColor3") || { color: "#FFFFFF" }).color || "#FFFFFF");
    const stops = seq.map(([t, c]) => { const k = hex(c); return `rgba(${Math.round(k[0]*base[0]/255)},${Math.round(k[1]*base[1]/255)},${Math.round(k[2]*base[2]/255)},${1-bgT}) ${t*100}%`; });
    bg = `linear-gradient(${90 + P(grad, "Rotation", 0)}deg, ${stops.join(",")})`;
  }
  if (bgT < 1 && node.class !== "ScreenGui") el.style.background = bg;
  const corner = mod(node, "UICorner");
  if (corner) { const r = (P(corner, "CornerRadius") || { udim: [0, 8] }).udim || [0, 8]; el.style.borderRadius = (r[0] * Math.min(w, h) + r[1]) + "px"; }
  const strokes = (node.children || []).filter(c => c.class === "UIStroke");
  for (const s of strokes) {
    const color = rgba(P(s, "Color", { color: "#000000" }), P(s, "Transparency", 0)); const t = P(s, "Thickness", 1);
    const mode = enumItem(P(s, "ApplyStrokeMode"), "Contextual");
    if (isText && mode === "Contextual") el.dataset.textStroke = `${t}px ${color}`;
    else el.style.boxShadow = `0 0 0 ${t}px ${color}`;
  }
  if (P(node, "ClipsDescendants", false) || node.class === "ScrollingFrame") el.style.overflow = "hidden";
  if (isImage) {
    const img = P(node, "Image");
    const box = document.createElement("div");
    if (img && img.image && LOCAL_IMAGES[img.image] && (!img.id || /rbxassetid:\/\/0$/.test(img.id))) {
      box.style.cssText = `width:100%;height:100%;background:url('${LOCAL_IMAGES[img.image]}') center/100% 100% no-repeat;opacity:${1 - P(node, "ImageTransparency", 0)}`;
    } else if (img && (img.image || typeof img === "string")) {
      box.className = "img"; box.textContent = img.image || "image";
    }
    el.appendChild(box);
  }
  if (isText) {
    const t = document.createElement("div"); t.className = "txt";
    const font = (P(node, "FontFace") || {}).font || { family: "BuilderSans" };
    t.style.fontFamily = FONT_CSS[font.family] || `'${font.family}',system-ui,sans-serif`;
    t.style.fontWeight = WEIGHT[font.weight || "Regular"] || 400;
    t.style.color = rgba(P(node, "TextColor3", { color: "#000000" }), P(node, "TextTransparency", 0));
    const xa = enumItem(P(node, "TextXAlignment"), "Center"), ya = enumItem(P(node, "TextYAlignment"), "Center");
    t.style.justifyContent = { Left: "flex-start", Right: "flex-end", Center: "center" }[xa];
    t.style.alignItems = { Top: "flex-start", Bottom: "flex-end", Center: "center" }[ya];
    t.style.textAlign = xa.toLowerCase();
    const text = String(P(node, "Text", node.class === "TextBox" ? "" : "Label"));
    const span = document.createElement("span"); // one inline box so rich text runs stay on the same line
    if (P(node, "RichText", false)) span.innerHTML = text.replace(/<font color="(#[0-9a-fA-F]{6})">/g, '<span style="color:$1">').replace(/<\/font>/g, "</span>");
    else span.textContent = text;
    t.appendChild(span);
    if (el.dataset.textStroke) t.style.webkitTextStroke = el.dataset.textStroke, t.style.paintOrder = "stroke fill";
    let size = P(node, "TextSize", 14);
    const tsc = mod(node, "UITextSizeConstraint");
    if (P(node, "TextScaled", false)) {
      const lines = text.split("\n").map(l => l.replace(/<[^>]+>/g, ""));
      const ctx = (window.__measure = window.__measure || document.createElement("canvas").getContext("2d"));
      ctx.font = `${t.style.fontWeight} 100px ${t.style.fontFamily}`;
      const widest = Math.max(...lines.map(l => ctx.measureText(l).width), 1);
      size = Math.min(h / lines.length * 0.92, (w * 0.98) / widest * 100);
    }
    if (tsc) size = Math.min(Math.max(size, P(tsc, "MinTextSize", 1)), P(tsc, "MaxTextSize", 100));
    t.style.fontSize = Math.max(1, size) + "px";
    el.appendChild(t);
  }
  parentEl.appendChild(el);
  layoutChildren(node, el, w, h);
}

function layoutChildren(node, el, w, h) {
  const pad = padding(node, w, h);
  const cw = w - pad.l - pad.r, ch = h - pad.t - pad.b;
  const inner = document.createElement("div");
  inner.className = "el"; Object.assign(inner.style, { left: pad.l + "px", top: pad.t + "px", width: cw + "px", height: ch + "px" });
  el.appendChild(inner);
  const kids = (node.children || []).filter(c => !MODIFIERS.has(c.class) && P(c, "Visible", true) !== false);
  const list = mod(node, "UIListLayout"), grid = mod(node, "UIGridLayout");
  const order = arr => arr.map((c, i) => [c, i]).sort((a, b) => (P(a[0], "LayoutOrder", 0) - P(b[0], "LayoutOrder", 0)) || a[1] - b[1]).map(p => p[0]);
  if (list) {
    const horiz = enumItem(P(list, "FillDirection"), "Vertical") === "Horizontal";
    const gapU = (P(list, "Padding") || { udim: [0, 0] }).udim || [0, 0];
    const gap = gapU[0] * (horiz ? cw : ch) + gapU[1];
    const items = order(kids).map(c => ({ c, s: baseSize(c, cw, ch), fill: mod(c, "UIFlexItem") && enumItem(P(mod(c, "UIFlexItem"), "FlexMode"), "None") !== "None" }));
    const main = horiz ? cw : ch;
    let used = items.reduce((a, it) => a + (horiz ? it.s[0] : it.s[1]), 0) + gap * Math.max(0, items.length - 1);
    const fills = items.filter(it => it.fill);
    if (fills.length && used < main) { const extra = (main - used) / fills.length; for (const it of fills) { if (horiz) it.s[0] += extra; else it.s[1] += extra; } used = main; }
    const flex = enumItem(P(list, horiz ? "HorizontalFlex" : "VerticalFlex"), "None");
    const align = enumItem(P(list, horiz ? "HorizontalAlignment" : "VerticalAlignment"), horiz ? "Left" : "Top");
    const cross = enumItem(P(list, horiz ? "VerticalAlignment" : "HorizontalAlignment"), horiz ? "Top" : "Left");
    let start = 0, between = gap;
    const free = main - used, n = items.length;
    if (flex === "SpaceBetween" && n > 1) between = gap + free / (n - 1);
    else if (flex === "SpaceAround" && n) { between = gap + free / n; start = free / n / 2; }
    else if (flex === "SpaceEvenly" && n) { between = gap + free / (n + 1); start = free / (n + 1); }
    else if (["Center", "Middle"].includes(align)) start = free / 2;
    else if (["Right", "Bottom"].includes(align)) start = free;
    let cur = start;
    for (const it of items) {
      const [iw, ih] = it.s;
      const crossSize = horiz ? ch : cw, own = horiz ? ih : iw;
      const off = ["Center", "Middle"].includes(cross) ? (crossSize - own) / 2 : (["Right", "Bottom"].includes(cross) ? crossSize - own : 0);
      render(it.c, inner, cw, ch, horiz ? [cur, off, iw, ih] : [off, cur, iw, ih]);
      cur += (horiz ? iw : ih) + between;
    }
  } else if (grid) {
    const cs = (P(grid, "CellSize") || { udim2: [0, 100, 0, 100] }).udim2, cp = (P(grid, "CellPadding") || { udim2: [0, 5, 0, 5] }).udim2;
    const cellW = cs[0] * cw + cs[1], cellH = cs[2] * ch + cs[3], gx = cp[0] * cw + cp[1], gy = cp[2] * ch + cp[3];
    const perRow = Math.max(1, Math.floor((cw + gx) / (cellW + gx)));
    order(kids).forEach((c, i) => render(c, inner, cw, ch, [(i % perRow) * (cellW + gx), Math.floor(i / perRow) * (cellH + gy), cellW, cellH]));
  } else {
    for (const c of kids) render(c, inner, cw, ch);
  }
}

function overlays(screenEl, w, h) {
  const top = h >= 600 ? 58 : 44;
  const t = document.createElement("div"); t.className = "ov-top"; t.style.height = top + "px"; screenEl.appendChild(t);
  const lt = document.createElement("div"); lt.className = "ov-label"; lt.style.left = "4px"; lt.style.top = "2px"; lt.textContent = "Roblox top bar (approx.)"; screenEl.appendChild(lt);
  if (Math.min(w, h) < 600) {
    const stick = document.createElement("div"); stick.className = "ov-zone";
    Object.assign(stick.style, { left: (w * 0.03) + "px", bottom: (h * 0.04) + "px", width: (h * 0.42) + "px", height: (h * 0.42) + "px" });
    const jump = document.createElement("div"); jump.className = "ov-zone";
    Object.assign(jump.style, { right: (w * 0.05) + "px", bottom: (h * 0.08) + "px", width: (h * 0.24) + "px", height: (h * 0.24) + "px" });
    screenEl.appendChild(stick); screenEl.appendChild(jump);
  }
}

function view(screen, w, h) {
  const box = document.createElement("div"); box.className = "view";
  const cap = document.createElement("div"); cap.className = "caption"; cap.textContent = `${screen.name}  ${w}x${h}`;
  const scr = document.createElement("div"); scr.className = "screen"; scr.style.width = w + "px"; scr.style.height = h + "px";
  box.appendChild(cap); box.appendChild(scr);
  const insets = enumItem(P(screen, "ScreenInsets"), "CoreUISafeInsets");
  const topInset = insets === "CoreUISafeInsets" ? (h >= 600 ? 58 : 44) : 0;
  const area = document.createElement("div"); area.className = "el";
  Object.assign(area.style, { left: 0, top: topInset + "px", width: w + "px", height: (h - topInset) + "px" });
  scr.appendChild(area);
  layoutChildren(screen, area, w, h - topInset);
  overlays(scr, w, h);
  return box;
}

const params = new URLSearchParams(location.search);
const root = document.getElementById("root");
const screens = SPEC.screens.map(s => JSON.parse(JSON.stringify(s)));
screens.forEach(applyStyles);
if (params.get("screen")) {
  document.body.classList.add("single");
  const s = screens.find(x => x.name === params.get("screen")) || screens[0];
  root.appendChild(view(s, +params.get("w") || 1920, +params.get("h") || 1080));
} else {
  for (const s of screens) for (const [w, h] of SIZES) root.appendChild(view(s, w, h));
}
</script></body></html>
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("spec")
    parser.add_argument("-o", "--output", required=True)
    parser.add_argument("--images", help="folder with exported PNGs named <image key>.png (e.g. from psd_to_spec.py)")
    args = parser.parse_args()

    spec = json.loads(Path(args.spec).read_text(encoding="utf-8"))
    out = Path(args.output).resolve()
    images = {}
    if args.images:
        folder = Path(args.images).resolve()
        for key in spec.get("images") or {}:
            png = folder / f"{key}.png"
            if png.exists():
                images[key] = Path(png).as_uri()
    html = (HTML.replace("__NAME__", spec.get("name", "UI"))
                .replace("__SPEC__", json.dumps(spec))
                .replace("__IMAGES__", json.dumps(images)))
    out.write_text(html, encoding="utf-8")
    print(f"wrote {out}")
    for screen in spec.get("screens", []):
        print(f"  {out.as_uri()}?screen={screen.get('name')}&w=844&h=390")


if __name__ == "__main__":
    main()
